class_name GameData
extends RefCounted
## Game data loaded from JSON files in data/, so balancing is an edit to a
## file, not to code.
##
## Each file is {"schema": 1, "note": "...", "items": [{ "id": ..., ... }]}.
## TABLES below says which fields each table has and their types. Loading
## checks everything up front and collects readable errors: missing or
## unknown fields, wrong types, duplicate ids, and references to ids that
## don't exist. Rows come back read-only, with whole numbers as ints.
##
## Field types:
##   "id"        non-empty snake_case string, unique in its table
##   "string"    non-empty string
##   "string?"   string, may be empty (for things still being written)
##   "int"       whole number
##   "bool"      true or false
##   "int_list"  non-empty list of whole numbers
##   "string_list"  list of non-empty strings (may be empty)
##   "enum:a|b"  one of the listed words
##   "ref:T"     the id of a row in table T
##   "ref_list:T"  list of ids of rows in table T (may repeat)

const DATA_DIR: String = "res://data"
const SCHEMA: int = 1

const TABLES: Dictionary[String, Dictionary] = {
	"perks": {
		"id": "id", "name": "string", "kind": "string", "text": "string",
		"amount": "int", "uses_per_turn": "int",
	},
	"villagers": {
		"id": "id", "role": "string", "personality": "string?", "bet_lost": "string?",
		"perk": "ref:perks",
	},
	"rooms": {
		"id": "id", "name": "string", "icon_shape": "string",
	},
	"dice": {
		"id": "id", "name": "string", "faces": "int_list",
	},
	"slots": {
		"id": "id", "name": "string", "text": "string",
		"accepts": "enum:any|range|even|odd|exact|pair|three_kind|run|sum_at_least",
		"min": "int", "max": "int", "min_dice": "int", "max_dice": "int", "persists": "bool",
		"effect": "enum:damage|block|heal|resource|open", "resource": "string?", "mult": "int", "add": "int",
		"icon_shape": "string",
	},
	"enemies": {
		"id": "id", "name": "string", "tier": "enum:regular|elite", "hp": "int", "intents": "string_list",
		"twist": "enum:none|house_lock|snake_eyes", "twist_text": "string?",
	},
	"delve": {
		"id": "id", "floors": "int", "rows_per_floor": "int",
		"width_two_weight": "int", "width_three_weight": "int",
		"fight_weight": "int", "treasure_weight": "int", "rest_weight": "int",
		"max_fight_streak": "int", "reveal_rows": "int", "redraw_attempts": "int",
		"fallback_resource_a": "ref:resources", "fallback_amount_a": "int",
		"fallback_resource_b": "ref:resources", "fallback_amount_b": "int",
	},
	"loot": {
		"id": "id", "room": "ref:rooms", "resource": "ref:resources",
		"chance_percent": "int", "min": "int", "max": "int",
	},
	"resources": {
		"id": "id", "name": "string",
	},
	"landmarks": {
		"id": "id", "name": "string",
	},
	"dice_rooms": {
		"id": "ref:rooms", "slots": "ref_list:slots", "turns": "int", "rerolls_per_turn": "int",
		"open_all": "bool", "tide_damage": "int",
	},
	"loadouts": {
		"id": "id", "hp": "int", "dice": "ref_list:dice", "slots": "ref_list:slots",
		"rerolls_per_turn": "int", "unused_die_block": "int",
	},
}

var errors: PackedStringArray = []

## table -> id -> row, in file order.
var _tables: Dictionary[String, Dictionary] = {}
var _id_pattern: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")


## Loads every table from `dir`. Check `is_valid()` (or `errors`) after.
static func load_dir(dir: String = DATA_DIR) -> GameData:
	var data: GameData = GameData.new()
	var texts: Dictionary[String, String] = {}
	for table: String in TABLES:
		var path: String = dir.path_join(table + ".json")
		if not FileAccess.file_exists(path):
			data.errors.append("%s: file missing" % path)
			continue
		texts[table] = FileAccess.get_file_as_string(path)
	data.load_texts(texts)
	return data


## Loads tables from JSON text keyed by table name. Used by load_dir and tests.
func load_texts(texts: Dictionary[String, String]) -> void:
	for table: String in texts:
		_load_table(table, texts[table])
	_check_refs()
	_check_rows()


func is_valid() -> bool:
	return errors.is_empty()


func has_row(table: String, id: String) -> bool:
	return _tables.has(table) and (_tables[table] as Dictionary).has(id)


## The row, or an empty Dictionary if it doesn't exist.
func row(table: String, id: String) -> Dictionary:
	if not has_row(table, id):
		return {}
	return (_tables[table] as Dictionary)[id]


func ids(table: String) -> PackedStringArray:
	if not _tables.has(table):
		return PackedStringArray()
	return PackedStringArray((_tables[table] as Dictionary).keys())


func _load_table(table: String, text: String) -> void:
	if not TABLES.has(table):
		errors.append("%s: unknown table" % table)
		return
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: JSON error on line %d: %s" % [table, json.get_error_line(), json.get_error_message()])
		return
	if not json.data is Dictionary:
		errors.append("%s: top level must be an object" % table)
		return
	var root: Dictionary = json.data
	if SaveCodec.to_int_or(root.get("schema"), -1) != SCHEMA:
		errors.append("%s: schema must be %d" % [table, SCHEMA])
		return
	if not root.get("items") is Array:
		errors.append("%s: \"items\" must be a list" % table)
		return

	var fields: Dictionary = TABLES[table]
	var rows: Dictionary = {}
	var index: int = 0
	for item: Variant in root["items"] as Array:
		var where: String = "%s[%d]" % [table, index]
		index += 1
		if not item is Dictionary:
			errors.append("%s: must be an object" % where)
			continue
		var row_data: Variant = _read_row(where, item as Dictionary, fields)
		if row_data == null:
			continue
		var clean: Dictionary = row_data
		var id: String = clean["id"]
		if rows.has(id):
			errors.append("%s: duplicate id \"%s\"" % [where, id])
			continue
		for key: Variant in clean:
			if clean[key] is Array:
				(clean[key] as Array).make_read_only()
		clean.make_read_only()
		rows[id] = clean
	_tables[table] = rows


## Returns a cleaned row, or null after logging what's wrong with it.
func _read_row(where: String, item: Dictionary, fields: Dictionary) -> Variant:
	var clean: Dictionary = {}
	var ok: bool = true
	for key: Variant in item:
		if not fields.has(key):
			errors.append("%s: unknown field \"%s\"" % [where, key])
			ok = false
	for field: String in fields:
		var kind: String = fields[field]
		if not item.has(field):
			errors.append("%s: missing \"%s\"" % [where, field])
			ok = false
			continue
		var value: Variant = item[field]
		match kind:
			"id":
				if not (value is String and _id_pattern.search(value as String) != null):
					errors.append("%s: \"%s\" must be a snake_case id" % [where, field])
					ok = false
			"string", "string?":
				if not value is String or (kind == "string" and (value as String).is_empty()):
					errors.append("%s: \"%s\" must be %s text" % [where, field, "some" if kind == "string" else ""])
					ok = false
			"int":
				if not SaveCodec.is_int_like(value) or value is String:
					errors.append("%s: \"%s\" must be a whole number" % [where, field])
					ok = false
				else:
					value = SaveCodec.to_int_or(value, 0)
			"bool":
				if not value is bool:
					errors.append("%s: \"%s\" must be true or false" % [where, field])
					ok = false
			"int_list":
				var numbers: Variant = _int_list(value)
				if numbers == null:
					errors.append("%s: \"%s\" must be a non-empty list of whole numbers" % [where, field])
					ok = false
				else:
					value = numbers
			"string_list":
				if not _is_string_list(value):
					errors.append("%s: \"%s\" must be a list of text" % [where, field])
					ok = false
			_:
				if kind.begins_with("enum:"):
					var allowed: PackedStringArray = kind.substr(5).split("|")
					if not (value is String and (value as String) in allowed):
						errors.append("%s: \"%s\" must be one of %s" % [where, field, ", ".join(allowed)])
						ok = false
				elif kind.begins_with("ref_list:"):
					if not _is_string_list(value):
						errors.append("%s: \"%s\" must be a list of ids" % [where, field])
						ok = false
				elif kind.begins_with("ref:"):
					if not value is String:
						errors.append("%s: \"%s\" must be an id" % [where, field])
						ok = false
				else:
					errors.append("%s: field \"%s\" has unknown type \"%s\"" % [where, field, kind])
					ok = false
		clean[field] = value
	return clean if ok else null


## Rules between fields of one row that a field type can't say.
func _check_rows() -> void:
	for id: String in ids("slots"):
		var slot_row: Dictionary = row("slots", id)
		if (slot_row["min_dice"] as int) < 1 or (slot_row["min_dice"] as int) > (slot_row["max_dice"] as int):
			errors.append("slots \"%s\": needs 1 <= min_dice <= max_dice, got %d and %d" % [
				id, slot_row["min_dice"], slot_row["max_dice"]])
		# A pair needs two dice and three of a kind three, or fewer would count.
		var fewest: int = {"pair": 2, "three_kind": 3}.get(slot_row["accepts"], 1)
		if (slot_row["min_dice"] as int) < fewest:
			errors.append("slots \"%s\": %s needs min_dice of at least %d" % [id, slot_row["accepts"], fewest])
		# A resource slot names what it pays; no other slot names one.
		var pays: String = slot_row["resource"]
		if slot_row["effect"] == "resource":
			if not has_row("resources", pays):
				errors.append("slots \"%s\": a resource slot needs a resource, got \"%s\"" % [id, pays])
		elif not pays.is_empty():
			errors.append("slots \"%s\": only a resource slot names a resource" % id)
	for id: String in ids("dice_rooms"):
		var room_row: Dictionary = row("dice_rooms", id)
		if (room_row["turns"] as int) < 1 or (room_row["slots"] as Array).is_empty():
			errors.append("dice_rooms \"%s\": needs at least one turn and one slot" % id)
		if (room_row["rerolls_per_turn"] as int) < 0 or (room_row["tide_damage"] as int) < 0:
			errors.append("dice_rooms \"%s\": rerolls and tide damage can't be negative" % id)
	# Every tier needs an enemy: the map places fight and elite rooms.
	if _tables.has("enemies"):
		var tiers: Dictionary[String, int] = {"regular": 0, "elite": 0}
		for id: String in ids("enemies"):
			var tier: String = row("enemies", id)["tier"]
			tiers[tier] = tiers.get(tier, 0) + 1
		for tier: String in tiers:
			if tiers[tier] == 0:
				errors.append("enemies: needs at least one %s enemy" % tier)
	for id: String in ids("loot"):
		var loot_row: Dictionary = row("loot", id)
		if (loot_row["chance_percent"] as int) < 0 or (loot_row["chance_percent"] as int) > 100:
			errors.append("loot \"%s\": chance_percent must be 0 to 100" % id)
		if (loot_row["min"] as int) < 0 or (loot_row["min"] as int) > (loot_row["max"] as int):
			errors.append("loot \"%s\": needs 0 <= min <= max" % id)


func _check_refs() -> void:
	for table: String in _tables:
		var fields: Dictionary = TABLES[table]
		for id: String in _tables[table] as Dictionary:
			var row_data: Dictionary = (_tables[table] as Dictionary)[id]
			for field: String in fields:
				var kind: String = fields[field]
				var targets: Array = []
				var target: String = ""
				if kind.begins_with("ref:"):
					target = kind.substr(4)
					targets = [row_data[field]]
				elif kind.begins_with("ref_list:"):
					target = kind.substr(9)
					targets = row_data[field] as Array
				for ref: Variant in targets:
					if not has_row(target, ref as String):
						errors.append("%s \"%s\": \"%s\" points to missing %s \"%s\"" % [
							table, id, field, target, ref])


## A whole-number list as Array[int], or null if it isn't one.
static func _int_list(value: Variant) -> Variant:
	if not value is Array or (value as Array).is_empty():
		return null
	var out: Array[int] = []
	for item: Variant in value as Array:
		if item is String or not SaveCodec.is_int_like(item):
			return null
		out.append(SaveCodec.to_int_or(item, 0))
	return out


static func _is_string_list(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value as Array:
		if not (item is String and not (item as String).is_empty()):
			return false
	return true
