extends GutTest
## Building and moving in town (specs/town.md sections 2 to 4, PR 2):
## one call checks and spends together, refusals come from the sim, a move
## is checked with the building lifted, and the town saves as version 3.

const V2_FIXTURE: String = "res://tests/saves/v2_cafe_two_villagers.save"

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _state(actions: int = 4, driftwood: int = 20, pearls: int = 5) -> GameState:
	var state: GameState = GameState.new(7)
	state.town.actions_left = actions
	state.town.needs_budget = false
	state.add_resource("driftwood", driftwood)
	state.add_resource("pearls", pearls)
	return state


func _kinds(refusals: Array[Dictionary]) -> Array:
	return refusals.map(func(refusal: Dictionary) -> Town.Refusal: return refusal["kind"])


func _texts(refusals: Array[Dictionary]) -> Array:
	return refusals.map(func(refusal: Dictionary) -> String: return refusal["text"])


# --- Spots ----------------------------------------------------------------------

func test_a_spot_says_why_a_building_cant_go_there() -> void:
	var state: GameState = _state()
	var map: TownMap = GameState.town_map(data)
	var town: Town = state.town
	assert_eq(town.spot_problem(data, map, "cottage", Vector2i(0, 0)), "")
	assert_eq(town.spot_problem(data, map, "cottage", Vector2i(12, 0)), "Off the map")
	assert_eq(town.spot_problem(data, map, "cottage", Vector2i(4, 1)), "On a path")
	assert_eq(town.spot_problem(data, map, "cottage", Vector2i(2, 8)), "In the sea")
	assert_eq(town.spot_problem(data, map, "cafe", Vector2i(2, 0)), "Runs off the lot")
	assert_eq(town.spot_problem(data, map, "cafe", Vector2i(0, 7)), "Runs off the lot", "into the sea")
	assert_eq(town.spot_problem(data, map, "cafe", Vector2i(0, 5)), "")
	assert_eq(state.build(data, "net_shed", Vector2i(0, 0)), [] as Array[Dictionary])
	assert_eq(town.spot_problem(data, map, "cottage", Vector2i(1, 0)), "Something's already here")
	assert_eq(town.spot_problem(data, map, "cottage", Vector2i(2, 0)), "")


func test_too_big_means_the_lot_itself_is_too_small() -> void:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var buildings: Dictionary = JSON.parse_string(texts["buildings"])
	for row: Dictionary in buildings["items"]:
		if row["id"] == "cafe":
			row["width"] = 4
	texts["buildings"] = JSON.stringify(buildings)
	var wide: GameData = GameData.new()
	wide.load_texts(texts)
	assert_eq(wide.errors, PackedStringArray())
	var map: TownMap = GameState.town_map(wide)
	assert_eq(Town.new().spot_problem(wide, map, "cafe", Vector2i(5, 5)), "Too big for this lot", "a 3-wide lot")
	assert_eq(Town.new().spot_problem(wide, map, "cafe", Vector2i(0, 5)), "")


# --- Building -------------------------------------------------------------------

func test_a_build_spends_its_action_and_resources_together() -> void:
	var state: GameState = _state(4, 10, 2)
	assert_eq(state.build(data, "tea_stall", Vector2i(5, 0)), [] as Array[Dictionary])
	assert_eq([state.resource("driftwood"), state.resource("pearls"), state.town.actions_left], [7, 1, 3])
	assert_eq(state.town.placed, [{"uid": 1, "building": "tea_stall", "x": 5, "y": 0}] as Array[Dictionary])
	assert_eq(state.build(data, "cottage", Vector2i(6, 0)), [] as Array[Dictionary])
	assert_eq(state.town.placed.back()["uid"], 2, "uids count up")


func test_a_card_lists_everything_youre_short_of_and_nothing_changes() -> void:
	var state: GameState = _state(0, 2, 0)
	var refusals: Array[Dictionary] = state.build(data, "tea_stall", Vector2i(5, 0))
	assert_eq(_kinds(refusals), [Town.Refusal.SHORT, Town.Refusal.SHORT, Town.Refusal.NO_ACTIONS])
	assert_eq(_texts(refusals), [
		"Needs 1 more Driftwood (you have 2) · found in fights and small locks below",
		"Needs 1 more Pearls (you have 0) · found in fights and pearl locks below",
		"No actions left",
	])
	assert_eq([state.resource("driftwood"), state.town.actions_left, state.town.placed.size()], [2, 0, 0])


func test_a_bad_spot_spends_nothing() -> void:
	var state: GameState = _state(4, 10, 2)
	var refusals: Array[Dictionary] = state.build(data, "cottage", Vector2i(4, 0))
	assert_eq(_kinds(refusals), [Town.Refusal.SPOT])
	assert_eq(_texts(refusals), ["On a path"])
	assert_eq([state.resource("driftwood"), state.town.actions_left, state.town.placed.size()], [10, 4, 0])


func test_not_yet_names_the_next_step() -> void:
	var state: GameState = _state()
	assert_eq(_texts(state.build_refusals(data, "bait_shop")), ["Needs 2 buildings placed (you have 0)"])
	assert_eq(_kinds(state.build_refusals(data, "bait_shop")), [Town.Refusal.NOT_YET])
	assert_eq(_texts(state.build_refusals(data, "boat_shed")), ["The Shipwright needs to live in town first"])
	assert_eq(_texts(state.build_refusals(data, "cafe")), ["Win it in Koban's vault"])
	state.build(data, "cottage", Vector2i(0, 0))
	assert_eq(_texts(state.build_refusals(data, "bait_shop")), ["Needs 2 buildings placed (you have 1)"])
	state.build(data, "cottage", Vector2i(1, 0))
	assert_eq(state.build_refusals(data, "bait_shop"), [] as Array[Dictionary])
	state._villagers.append("shipwright")
	assert_eq(state.build_refusals(data, "boat_shed"), [] as Array[Dictionary])


func test_a_build_stops_at_max_count() -> void:
	var state: GameState = _state(10, 40, 10)
	state.build(data, "lantern_post", Vector2i(0, 0))
	state.build(data, "lantern_post", Vector2i(1, 0))
	assert_eq(_kinds(state.build(data, "lantern_post", Vector2i(2, 0))), [Town.Refusal.ALL_BUILT])
	assert_eq(_texts(state.build_refusals(data, "lantern_post")), ["You've built all 2"])
	state.build(data, "tea_stall", Vector2i(3, 0))
	assert_eq(_texts(state.build_refusals(data, "tea_stall")), ["Already built"])
	assert_eq(state.town.actions_left, 7, "refused builds cost nothing")


func test_a_won_landmark_is_placed_free_and_once() -> void:
	var state: GameState = _state(0, 0, 0)
	state._landmarks.append("cafe")
	assert_eq(state.landmarks_waiting(), ["cafe"] as Array[String])
	assert_eq(state.build(data, "cafe", Vector2i(0, 5)), [] as Array[Dictionary], "no actions or resources needed")
	assert_eq(state.landmarks_waiting(), [] as Array[String])
	assert_eq(_texts(state.build_refusals(data, "cafe")), ["Already placed"])
	assert_eq(state.build_refusals(data, "bait_shop")[0]["text"], "Needs 2 buildings placed (you have 1)", "landmarks count")


func test_spending_takes_fresh_actions_before_the_kept_one() -> void:
	var state: GameState = _state(2)
	state.town.kept = 1
	state.build(data, "cottage", Vector2i(0, 0))
	assert_eq([state.town.actions_left, state.town.kept], [1, 1])
	state.build(data, "cottage", Vector2i(1, 0))
	assert_eq([state.town.actions_left, state.town.kept], [0, 0])


func test_unknown_buildings_are_refused() -> void:
	assert_eq(_texts(_state().build(data, "pagoda", Vector2i(0, 0))), ["Not a building"])


# --- Moving ---------------------------------------------------------------------

func test_a_move_is_free_and_checked_with_the_building_lifted() -> void:
	var state: GameState = _state(4)
	state.build(data, "net_shed", Vector2i(0, 0))
	state.build(data, "cottage", Vector2i(0, 1))
	var shed: int = state.town.placed[0]["uid"]
	assert_eq(state.move_building(data, shed, Vector2i(1, 0)), "", "onto one of its own cells")
	assert_eq(state.town.entry(shed), {"uid": shed, "building": "net_shed", "x": 1, "y": 0})
	assert_eq(state.move_building(data, shed, Vector2i(0, 1)), "Something's already here")
	assert_eq(state.move_building(data, shed, Vector2i(3, 0)), "Runs off the lot")
	assert_eq(state.move_building(data, shed, Vector2i(4, 2)), "On a path")
	assert_eq(state.town.entry(shed)["x"], 1, "a refused move changes nothing")
	assert_eq(state.move_building(data, 99, Vector2i(0, 0)), "Nothing to move")
	assert_eq(state.move_building(data, shed, Vector2i(9, 7)), "")
	assert_eq(state.town.actions_left, 2, "moves cost no actions")


func test_a_home_moves_with_whoever_lives_there() -> void:
	var state: GameState = _state()
	state._villagers.append("pearl_diver")
	state.build(data, "cottage", Vector2i(0, 0))
	var home: int = state.town.placed[0]["uid"]
	state.town.homes["pearl_diver"] = home
	state.move_building(data, home, Vector2i(2, 3))
	assert_eq(state.town.homes, {"pearl_diver": home} as Dictionary[String, int])
	assert_eq(state.town_problems(data), PackedStringArray())


# --- Saving (version 3) ------------------------------------------------------------

func _built() -> GameState:
	var state: GameState = _state(4)
	state._villagers.append("pearl_diver")
	state._landmarks.append("hot_spring")
	state.build(data, "cottage", Vector2i(0, 3))
	state.build(data, "hot_spring", Vector2i(5, 5))
	state.town.homes["pearl_diver"] = 1
	state.town.kept = 1
	state.town.held_at_go_down = 2
	return state


func test_the_town_round_trips_through_a_real_save() -> void:
	var state: GameState = _built()
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(SaveCodec.encode({GameState.PAYLOAD_KEY: state.to_dict()}, 1))
	assert_true(decoded.is_ok())
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	assert_eq(loaded.to_dict(), state.to_dict())
	assert_eq(loaded.town.homes, {"pearl_diver": 1} as Dictionary[String, int])
	assert_typeof(loaded.town.placed[0]["x"], TYPE_INT)
	assert_eq(loaded.town_problems(data), PackedStringArray())
	assert_eq(loaded.build(data, "cottage", Vector2i(1, 3)), [] as Array[Dictionary])
	assert_eq(loaded.town.placed.back()["uid"], 3, "next_uid survives the save")


func test_town_from_dict_rejects_bad_shapes() -> void:
	var good: Dictionary = _built().town.to_dict()
	assert_not_null(Town.from_dict(JSON.parse_string(JSON.stringify(good))))
	var cases: Dictionary = {
		"negative actions": {"actions_left": -1},
		"fraction kept": {"kept": 0.5},
		"budget flag not a bool": {"needs_budget": 1},
		"no uids left": {"next_uid": 0},
		"uid not yet given out": {"next_uid": 2},
		"placed not a list": {"placed": {}},
		"building with no id": {"placed": [{"uid": 1, "building": "", "x": 0, "y": 0}]},
		"negative cell": {"placed": [{"uid": 1, "building": "cottage", "x": -1, "y": 0}]},
		"repeated uid": {"placed": [{"uid": 1, "building": "cottage", "x": 0, "y": 0}, {"uid": 1, "building": "cottage", "x": 1, "y": 0}]},
		"home that isn't placed": {"homes": {"pearl_diver": 7}},
		"homes not a dict": {"homes": []},
	}
	for label: String in cases:
		var bad: Dictionary = good.duplicate(true)
		bad.merge(cases[label] as Dictionary, true)
		assert_null(Town.from_dict(bad), label)
	assert_null(Town.from_dict([]), "not a dict")


func test_a_town_that_breaks_the_data_is_caught_on_load() -> void:
	var cases: Dictionary = {
		"too many actions": func(s: GameState) -> void: s.town.actions_left = 6,
		"kept more than keep_max": func(s: GameState) -> void: s.town.kept = 2,
		"unknown building": func(s: GameState) -> void: s.town.placed[0]["building"] = "pagoda",
		"overlap": func(s: GameState) -> void: s.town.placed[1]["x"] = 0; s.town.placed[1]["y"] = 2,
		"on a path": func(s: GameState) -> void: s.town.placed[0]["x"] = 4,
		"over max_count": func(s: GameState) -> void: s.town.place("hot_spring", Vector2i(9, 0)),
		"landmark never won": func(s: GameState) -> void: s._landmarks.clear(),
		"home for a villager not in town": func(s: GameState) -> void: s._villagers.clear(),
		"home in a landmark": func(s: GameState) -> void: s.town.homes["pearl_diver"] = 2,
		"two in one home": func(s: GameState) -> void: s._villagers.append("shipwright"); s.town.homes["shipwright"] = 1,
	}
	assert_eq(_built().town_problems(data), PackedStringArray())
	for label: String in cases:
		var state: GameState = _built()
		(cases[label] as Callable).call(state)
		assert_gt(state.town_problems(data).size(), 0, label)


func test_a_v2_save_migrates_to_an_empty_town_with_its_wins_kept() -> void:
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(FileAccess.get_file_as_string(V2_FIXTURE))
	assert_true(decoded.is_ok(), "the fixture is a real version 2 save")
	assert_eq(decoded.version, SaveCodec.CURRENT_VERSION)
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	assert_eq(loaded.town.placed, [] as Array[Dictionary], "an empty town")
	assert_true(loaded.town.needs_budget, "arrival sets the budget, once")
	assert_eq([loaded.town.actions_left, loaded.town.kept], [0, 0])
	assert_eq(loaded.landmarks(), ["cafe"] as Array[String], "the Café stays won")
	assert_eq(loaded.landmarks_waiting(), ["cafe"] as Array[String], "and waits in the tray")
	assert_eq(loaded.villagers(), ["pearl_diver", "shipwright"] as Array[String])
	assert_eq(loaded.town.homes, {} as Dictionary[String, int], "villagers wait at the dock")
	assert_eq([loaded.delve_count, loaded.resource("driftwood")], [3, 14], "everything else is untouched")
	assert_eq(loaded.town_problems(data), PackedStringArray())
	assert_eq(loaded.build(data, "cafe", Vector2i(0, 5)), [] as Array[Dictionary], "the Café can be placed")


func test_the_town_draws_no_rng() -> void:
	var source: String = FileAccess.get_file_as_string("res://sim/town/town.gd") \
		+ FileAccess.get_file_as_string("res://sim/town/town_map.gd")
	for word: String in ["RngStreams", "randi", "randf", "RandomNumberGenerator"]:
		assert_false(source.contains(word), word)
