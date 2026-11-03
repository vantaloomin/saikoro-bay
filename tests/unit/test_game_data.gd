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
		{"id": "ok", "name": "Ok", "kind": "x", "text": "t", "amount": 1, "uses_per_turn": 0},
		{"id": "ok", "name": "Dup", "kind": "x", "text": "t", "amount": 1, "uses_per_turn": 0},
		{"id": "Bad Id", "name": "N", "kind": "x", "text": "t", "amount": 1, "uses_per_turn": 0},
		{"id": "frac", "name": "N", "kind": "x", "text": "t", "amount": 1.5, "uses_per_turn": 0},
		{"id": "typo", "name": "N", "kind": "x", "text": "t", "amount": 1, "uses_per_turn": 0, "amout": 2},
		{"id": "missing", "name": "N", "kind": "x", "text": "t", "amount": 1},
		{"id": "blank", "name": "", "kind": "x", "text": "t", "amount": 1, "uses_per_turn": 0},
	]})
	var villagers: String = JSON.stringify({"schema": 1, "items": [
		{"id": "v", "role": "R", "personality": "", "bet_lost": "", "perk": "ghost"},
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
			"min_dice": 1, "max_dice": 1, "persists": false, "effect": "damage", "mult": 1, "add": 0, "icon_shape": "x"},
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
			"min_dice": 3, "max_dice": 2, "persists": false, "effect": "damage", "mult": 1, "add": 0, "icon_shape": "x"},
		{"id": "fine", "name": "S", "text": "t", "accepts": "any", "min": 1, "max": 6,
			"min_dice": 1, "max_dice": 3, "persists": false, "effect": "damage", "mult": 1, "add": 0, "icon_shape": "x"},
	]})
	var data: GameData = GameData.new()
	data.load_texts({"slots": slots})
	assert_eq(data.errors, PackedStringArray(["slots \"upside_down\": needs 1 <= min_dice <= max_dice, got 3 and 2"]))
