extends GutTest
## Delve map generation (specs/delve-map.md sections 2 and 8a).

const VILLAGERS: Array[String] = ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _map(seed_value: int, villagers: Array[String] = VILLAGERS, landmarks: Array[String] = LANDMARKS) -> DelveMap:
	return DelveMap.generate(data, seed_value, villagers, landmarks)


func test_maps_pass_the_validator_on_many_seeds() -> void:
	var redrawn: int = 0
	var templates: int = 0
	for s: int in range(1, 301):
		var map: DelveMap = _map(s)
		assert_eq(map.map_errors(), PackedStringArray(), "seed %d" % s)
		if map.attempt > 0:
			redrawn += 1
		if map.attempt < 0:
			templates += 1
	assert_eq(templates, 0, "the template is a last resort, not a habit")
	gut.p("300 seeds: %d redrawn, %d template" % [redrawn, templates])


func test_the_same_seed_draws_the_same_map() -> void:
	assert_eq(_map(42).describe(), _map(42).describe())
	assert_ne(_map(42).describe(), _map(43).describe())


func test_shape_matches_the_slice() -> void:
	var map: DelveMap = _map(7)
	assert_eq(map.floors.size(), 3)
	for f: int in 3:
		assert_eq(map.rows_in_floor(f), 3)
		for r: int in 3:
			assert_between(map.width(f, r), 2, 3)


func test_link_sets_never_cross_and_cover_every_room() -> void:
	for key: String in DelveMap.CANDIDATES:
		var widths: PackedStringArray = key.split(">")
		var sets: Array = DelveMap._valid_link_sets(widths[0].to_int(), widths[1].to_int())
		assert_gt(sets.size(), 0, key)
		for links: Variant in sets:
			assert_true(DelveMap._link_set_ok(links as Array, widths[0].to_int(), widths[1].to_int()))
	assert_false(DelveMap._link_set_ok([[0, 1], [1, 0]], 2, 2), "0>1 with 1>0 crosses")


func test_the_rescue_is_reachable_from_every_start_of_floor_two() -> void:
	for s: int in range(1, 101):
		var map: DelveMap = _map(s)
		assert_true(map._rescue_reachable_from_every_start(DelveMap.RESCUE_FLOOR), "seed %d" % s)
		assert_eq(map.rescue_villager, "pearl_diver", "Pearl diver is rescued first")


func test_rescues_follow_the_fixed_order() -> void:
	var left: Array[String] = VILLAGERS.duplicate()
	var rescued: Array[String] = []
	for s: int in range(1, 5):
		var map: DelveMap = _map(s, left)
		rescued.append(map.rescue_villager)
		left.erase(map.rescue_villager)
	assert_eq(rescued, VILLAGERS, "data order, whatever the seed")
	assert_eq(data.ids("villagers"), PackedStringArray(VILLAGERS), "the order lives in villagers.json")


func test_no_rescue_when_everyone_is_home() -> void:
	for s: int in range(1, 51):
		var map: DelveMap = _map(s, [] as Array[String])
		assert_eq(map.rescue_villager, "")
		assert_eq(map._count(DelveMap.RESCUE), 0, "seed %d" % s)
		assert_eq(map.map_errors(), PackedStringArray())


func test_the_vault_falls_back_to_coins_when_every_landmark_is_won() -> void:
	var map: DelveMap = _map(5, VILLAGERS, [] as Array[String])
	assert_eq(map.vault_prize, {"resources": {"koban_coins": 3, "driftwood": 10}})
	assert_true(LANDMARKS.has(_map(5).vault_prize.get("landmark", "")))


func test_the_elite_is_avoidable() -> void:
	for s: int in range(1, 101):
		assert_true(_map(s)._type_avoidable(DelveMap.ELITE_FLOOR, DelveMap.ELITE), "seed %d" % s)


func test_the_validator_catches_broken_maps() -> void:
	var map: DelveMap = _map(3)
	map.room(0, 0, 0).type = DelveMap.REST
	assert_has(map.map_errors(), "floor 1 must open on fights")
	map = _map(3)
	map.room(0, 0, 0).links.clear()
	assert_false(map.map_errors().is_empty(), "a room with no way out")
	map = _map(3)
	for rm: DelveMap.Room in map.all_rooms():
		if rm.floor_index == 2 and rm.type == DelveMap.FIGHT:
			rm.type = DelveMap.ELITE
	assert_false(map.map_errors().is_empty(), "more than one elite")


func test_the_template_passes_the_validator() -> void:
	var config: Dictionary = data.row("delve", "slice")
	assert_eq(DelveMap.template(config, RngStreams.new(1), VILLAGERS, LANDMARKS).map_errors(), PackedStringArray())
	assert_eq(DelveMap.template_errors(config, VILLAGERS, LANDMARKS), PackedStringArray(), "every pool mix")


func test_a_config_that_breaks_the_template_is_caught() -> void:
	var config: Dictionary = data.row("delve", "slice").duplicate()
	config["max_fight_streak"] = 2
	var errors: PackedStringArray = DelveMap.template_errors(config, VILLAGERS, LANDMARKS)
	assert_eq(errors.size() > 0, true, "a streak of 2 is shorter than the template's")
	assert_string_contains(errors[0], "fights in a row")


func test_mixed_pools_draw_valid_maps() -> void:
	var none: Array[String] = []
	for s: int in range(1, 101):
		var lonely: DelveMap = _map(s, none, LANDMARKS)
		assert_eq(lonely.map_errors(), PackedStringArray(), "no villagers, seed %d" % s)
		assert_eq(lonely.rescue_villager, "")
		var plain: DelveMap = _map(s, VILLAGERS, none)
		assert_eq(plain.map_errors(), PackedStringArray(), "no landmarks, seed %d" % s)
		assert_true(plain.vault_prize.has("resources"))


func test_the_map_records_its_replay_inputs() -> void:
	var villagers: Array[String] = ["shipwright", "pearl_diver"]
	var map: DelveMap = _map(42, villagers, ["hot_spring"] as Array[String])
	assert_eq(map.inputs(), {
		"seed": "42", "config": "slice", "attempt": map.attempt,
		"villagers_left": ["shipwright", "pearl_diver"], "landmarks_left": ["hot_spring"],
	})
	villagers.append("onsen_keeper")
	assert_eq((map.inputs()["villagers_left"] as Array).size(), 2, "a copy, not the caller's list")


func test_fallback_prize_ids_are_checked_at_load() -> void:
	var texts: Dictionary[String, String] = {}
	for table: String in GameData.TABLES:
		texts[table] = FileAccess.get_file_as_string("res://data/%s.json" % table)
	texts["delve"] = texts["delve"].replace("\"koban_coins\"", "\"koban\"")
	var broken: GameData = GameData.new()
	broken.load_texts(texts)
	assert_false(broken.is_valid())
	assert_string_contains("\n".join(broken.errors), "koban")
