extends GutTest
## GameData: the real data files load cleanly, and bad data is reported.


func test_shipped_data_is_valid() -> void:
	var data: GameData = GameData.load_dir()
	assert_eq(data.errors, PackedStringArray(), "\n".join(data.errors))
	assert_true(data.is_valid())


func test_slice_villagers_and_their_perks() -> void:
	var data: GameData = GameData.load_dir()
	assert_eq(data.ids("villagers"), PackedStringArray(["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]))
	assert_eq(data.row("villagers", "shrine_keeper")["perk"], "foresight")
	assert_eq(data.row("perks", "foresight")["kind"], "map")


func test_whole_numbers_come_back_as_ints() -> void:
	var data: GameData = GameData.load_dir()
	assert_typeof(data.row("perks", "brace")["amount"], TYPE_INT)


func test_rows_are_read_only() -> void:
	var data: GameData = GameData.load_dir()
	assert_true(data.row("perks", "nudge").is_read_only())


func test_missing_row_is_empty() -> void:
	var data: GameData = GameData.load_dir()
	assert_false(data.has_row("perks", "nope"))
	assert_eq(data.row("perks", "nope"), {})
	assert_eq(data.ids("nope"), PackedStringArray())


func test_bad_rows_are_reported() -> void:
	var perks: String = JSON.stringify({"schema": 1, "items": [
		{"id": "ok", "name": "Ok", "kind": "map", "text": "t", "amount": 1, "uses_per_turn": 0, "happy_amount": 0, "happy_uses_per_turn": 0, "cost_amount": 0, "die": "", "gain": "g", "cost": "", "happy_gain": ""},
		{"id": "ok", "name": "Dup", "kind": "map", "text": "t", "amount": 1, "uses_per_turn": 0, "happy_amount": 0, "happy_uses_per_turn": 0, "cost_amount": 0, "die": "", "gain": "g", "cost": "", "happy_gain": ""},
		{"id": "Bad Id", "name": "N", "kind": "map", "text": "t", "amount": 1, "uses_per_turn": 0, "happy_amount": 0, "happy_uses_per_turn": 0, "cost_amount": 0, "die": "", "gain": "g", "cost": "", "happy_gain": ""},
		{"id": "frac", "name": "N", "kind": "map", "text": "t", "amount": 1.5, "uses_per_turn": 0, "happy_amount": 0, "happy_uses_per_turn": 0, "cost_amount": 0, "die": "", "gain": "g", "cost": "", "happy_gain": ""},
		{"id": "typo", "name": "N", "kind": "map", "text": "t", "amount": 1, "uses_per_turn": 0, "happy_amount": 0, "happy_uses_per_turn": 0, "cost_amount": 0, "die": "", "gain": "g", "cost": "", "happy_gain": "", "amout": 2},
		{"id": "missing", "name": "N", "kind": "map", "text": "t", "amount": 1},
		{"id": "blank", "name": "", "kind": "map", "text": "t", "amount": 1, "uses_per_turn": 0, "happy_amount": 0, "happy_uses_per_turn": 0, "cost_amount": 0, "die": "", "gain": "g", "cost": "", "happy_gain": ""},
	]})
	var villagers: String = JSON.stringify({"schema": 1, "items": [
		{"id": "v", "role": "R", "personality": "", "bet_lost": "", "perk": "ghost",
			"wish": "sea", "wish_buildings": [], "wish_text": "Next to the sea", "wish_line": ""},
		{"id": "w", "role": "R", "personality": "", "bet_lost": "", "perk": "ok",
			"wish": "sea", "wish_buildings": [], "wish_text": "Next to the sea", "wish_line": ""},
		{"id": "x", "role": "R", "personality": "", "bet_lost": "", "perk": "ok",
			"wish": "sea", "wish_buildings": [], "wish_text": "Next to the sea", "wish_line": ""},
	]})
	var data: GameData = GameData.new()
	data.load_texts({"perks": perks, "villagers": villagers})
	var all: String = "\n".join(data.errors)
	assert_string_contains(all, "duplicate id \"ok\"")
	assert_string_contains(all, "snake_case id")
	assert_string_contains(all, "\"amount\" must be a whole number")
	assert_string_contains(all, "unknown field \"amout\"")
	assert_string_contains(all, "missing \"uses_per_turn\"")
	assert_string_contains(all, "\"name\" must be some text")
	assert_string_contains(all, "points to missing perks \"ghost\"")
	assert_string_contains(all, "villagers \"x\": perk \"ok\" is already w's", "one villager per perk")
	assert_eq(data.ids("perks"), PackedStringArray(["ok"]), "only the good row loads")


func test_bad_files_are_reported() -> void:
	var data: GameData = GameData.new()
	data.load_texts({"perks": "{not json", "rooms": JSON.stringify({"schema": 2, "items": []})})
	var all: String = "\n".join(data.errors)
	assert_string_contains(all, "perks: JSON error")
	assert_string_contains(all, "rooms: schema must be 1")


func test_lists_and_enums_are_checked() -> void:
	var dice: String = JSON.stringify({"schema": 1, "items": [
		{"id": "d6", "name": "D6", "faces": [1, 2, 3, 4, 5, 6]},
		{"id": "empty", "name": "E", "faces": []},
		{"id": "words", "name": "W", "faces": ["1"]},
	]})
	var slots: String = JSON.stringify({"schema": 1, "items": [
		{"id": "s", "name": "S", "text": "t", "accepts": "anything", "min": 1, "max": 6,
			"min_dice": 1, "max_dice": 1, "persists": false, "effect": "damage", "resource": "", "mult": 1, "add": 0, "icon_shape": "x"},
	]})
	var loadouts: String = JSON.stringify({"schema": 1, "items": [
		{"id": "kit", "hp": 30, "dice": ["d6", "d8"], "slots": [], "rerolls_per_turn": 1, "unused_die_block": 1},
	]})
	var data: GameData = GameData.new()
	data.load_texts({"dice": dice, "slots": slots, "loadouts": loadouts})
	var all: String = "\n".join(data.errors)
	assert_string_contains(all, "\"faces\" must be a non-empty list of whole numbers")
	assert_eq(data.ids("dice"), PackedStringArray(["d6"]))
	assert_typeof(data.row("dice", "d6")["faces"][0], TYPE_INT)
	assert_string_contains(all, "\"accepts\" must be one of any, range")
	assert_string_contains(all, "points to missing dice \"d8\"")


func test_slots_need_min_dice_at_most_max_dice() -> void:
	var slots: String = JSON.stringify({"schema": 1, "items": [
		{"id": "upside_down", "name": "S", "text": "t", "accepts": "any", "min": 1, "max": 6,
			"min_dice": 3, "max_dice": 2, "persists": false, "effect": "damage", "resource": "", "mult": 1, "add": 0, "icon_shape": "x"},
		{"id": "fine", "name": "S", "text": "t", "accepts": "any", "min": 1, "max": 6,
			"min_dice": 1, "max_dice": 3, "persists": false, "effect": "damage", "resource": "", "mult": 1, "add": 0, "icon_shape": "x"},
	]})
	var data: GameData = GameData.new()
	data.load_texts({"slots": slots})
	assert_eq(data.errors, PackedStringArray(["slots \"upside_down\": needs 1 <= min_dice <= max_dice, got 3 and 2"]))


func test_matching_slots_need_enough_dice_to_match() -> void:
	var slots: String = JSON.stringify({"schema": 1, "items": [
		{"id": "short_triple", "name": "S", "text": "t", "accepts": "three_kind", "min": 1, "max": 6,
			"min_dice": 2, "max_dice": 3, "persists": false, "effect": "damage", "resource": "", "mult": 1, "add": 0, "icon_shape": "x"},
		{"id": "lone_pair", "name": "S", "text": "t", "accepts": "pair", "min": 1, "max": 6,
			"min_dice": 1, "max_dice": 2, "persists": false, "effect": "damage", "resource": "", "mult": 1, "add": 0, "icon_shape": "x"},
	]})
	var data: GameData = GameData.new()
	data.load_texts({"slots": slots})
	assert_eq(data.errors, PackedStringArray([
		"slots \"short_triple\": three_kind needs min_dice of at least 3",
		"slots \"lone_pair\": pair needs min_dice of at least 2"]))


func test_resource_slots_name_a_real_resource() -> void:
	var slots: String = JSON.stringify({"schema": 1, "items": [
		{"id": "pays_nothing", "name": "S", "text": "t", "accepts": "any", "min": 1, "max": 6,
			"min_dice": 1, "max_dice": 1, "persists": false, "effect": "resource", "resource": "gold", "mult": 1, "add": 0, "icon_shape": "x"},
		{"id": "hits_and_pays", "name": "S", "text": "t", "accepts": "any", "min": 1, "max": 6,
			"min_dice": 1, "max_dice": 1, "persists": false, "effect": "damage", "resource": "driftwood", "mult": 1, "add": 0, "icon_shape": "x"},
	]})
	var resources: String = JSON.stringify({"schema": 1, "items": [{"id": "driftwood", "name": "Driftwood", "found": ""}]})
	var data: GameData = GameData.new()
	data.load_texts({"slots": slots, "resources": resources})
	assert_eq(data.errors, PackedStringArray([
		"slots \"pays_nothing\": a resource slot needs a resource, got \"gold\"",
		"slots \"hits_and_pays\": only a resource slot names a resource"]))


func test_dice_rooms_are_room_types_with_turns_and_slots() -> void:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	texts["dice_rooms"] = JSON.stringify({"schema": 1, "items": [
		{"id": "rest", "slots": [], "turns": 0, "rerolls_per_turn": -1, "open_all": false, "tide_damage": 0},
		{"id": "sauna", "slots": ["soak"], "turns": 1, "rerolls_per_turn": 0, "open_all": false, "tide_damage": 0},
	]})
	var data: GameData = GameData.new()
	data.load_texts(texts)
	assert_eq(data.errors, PackedStringArray([
		"dice_rooms \"sauna\": \"id\" points to missing rooms \"sauna\"",
		"dice_rooms \"rest\": needs at least one turn and one slot",
		"dice_rooms \"rest\": rerolls and tide damage can't be negative"]))


func test_vault_nudges_come_from_data_and_cant_be_negative() -> void:
	assert_eq(GameData.load_dir().row("vaults", "koban")["nudges_per_vault"], 1)
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var vaults: Dictionary = JSON.parse_string(texts["vaults"])
	(vaults["items"] as Array)[0]["nudges_per_vault"] = -1
	texts["vaults"] = JSON.stringify(vaults)
	var data: GameData = GameData.new()
	data.load_texts(texts)
	assert_eq(data.errors, PackedStringArray(["vaults \"koban\": nudges_per_vault can't be negative"]))


func test_a_slot_only_goes_where_its_effect_works() -> void:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var loadouts: Dictionary = JSON.parse_string(texts["loadouts"])
	(loadouts["items"] as Array)[0]["slots"] = ["strike", "small_lock"]
	texts["loadouts"] = JSON.stringify(loadouts)
	var rooms: Dictionary = JSON.parse_string(texts["dice_rooms"])
	(rooms["items"] as Array)[1]["slots"] = ["soak", "guard"]
	texts["dice_rooms"] = JSON.stringify(rooms)
	var data: GameData = GameData.new()
	data.load_texts(texts)
	assert_eq(data.errors, PackedStringArray([
		"loadouts \"fresh\": slot \"small_lock\" has effect resource, which does nothing there",
		"dice_rooms \"rest\": slot \"guard\" has effect block, which does nothing there"]))


func test_loot_is_only_for_fights() -> void:
	var loot: String = JSON.stringify({"schema": 1, "items": [
		{"id": "chest_bonus", "room": "treasure", "resource": "driftwood", "chance_percent": 100, "min": 1, "max": 2},
	]})
	var data: GameData = GameData.new()
	data.load_texts({"loot": loot})
	assert_string_contains(", ".join(data.errors), "\"room\" must be one of fight, elite", "treasure pays through its locks")


func test_shop_perks_are_checked() -> void:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var buildings: Dictionary = JSON.parse_string(texts["buildings"])
	for item: Dictionary in buildings["items"] as Array:
		match str(item["id"]):
			"net_shed":
				item["perk"] = ""
			"tea_stall":
				item["perk"] = "brace"
			"boat_shed":
				item["perk"] = "ghost"
			"cottage":
				item["perk"] = "chum"
	texts["buildings"] = JSON.stringify(buildings)
	var perks: Dictionary = JSON.parse_string(texts["perks"])
	for item: Dictionary in perks["items"] as Array:
		match str(item["id"]):
			"spare_die":
				item["die"] = ""
			"mend":
				item["die"] = "d6"
			"chum":
				item["cost_amount"] = -1
	texts["perks"] = JSON.stringify(perks)
	var data: GameData = GameData.new()
	data.load_texts(texts)
	assert_eq(data.errors, PackedStringArray([
		"perks \"mend\": only a die_faces or add_die perk names a die",
		"perks \"chum\": cost_amount can't be negative",
		"perks \"spare_die\": add_die needs a real die, got \"\"",
		"buildings \"cottage\": every shop gives a perk, and nothing else does",
		"buildings \"cottage\": a shop with a perk needs max_count 1",
		"buildings \"net_shed\": every shop gives a perk, and nothing else does",
		"buildings \"tea_stall\": perk \"brace\" needs a cost line",
		"buildings \"tea_stall\": perk \"brace\" is already shipwright's",
		"buildings \"bait_shop\": perk \"chum\" is already cottage's",
		"buildings \"boat_shed\": \"perk\" points to missing perks \"ghost\"",
	]))


func test_a_happy_bonus_has_words_and_only_a_bonus_does() -> void:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var perks: Dictionary = JSON.parse_string(texts["perks"])
	for item: Dictionary in perks["items"] as Array:
		match str(item["id"]):
			"brace":
				item["happy_gain"] = ""
			"chum":
				item["happy_gain"] = "More fish"
	texts["perks"] = JSON.stringify(perks)
	var data: GameData = GameData.new()
	data.load_texts(texts)
	assert_eq(data.errors, PackedStringArray([
		"perks \"brace\": happy_gain says the happy bonus, and only a perk with one has it",
		"perks \"chum\": happy_gain says the happy bonus, and only a perk with one has it",
	]))
