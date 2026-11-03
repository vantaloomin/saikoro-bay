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
		"accepts": "enum:any|range|even|odd|exact|pair",
		"min": "int", "max": "int", "dice_needed": "int",
		"effect": "enum:damage|block|heal", "mult": "int", "add": "int",
		"icon_shape": "string",
	},
	"enemies": {
		"id": "id", "name": "string", "hp": "int", "intents": "string_list",
		"twist": "enum:none|house_lock|snake_eyes", "twist_text": "string?",
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
