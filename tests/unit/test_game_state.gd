extends GutTest
## GameState: half changes, integer resources, delve seeds and saving.


func test_starts_in_town() -> void:
	var state: GameState = GameState.new(1)
	assert_eq(state.phase, GameState.Phase.TOWN)
	assert_eq(state.delve_count, 0)


func test_delve_can_only_start_once() -> void:
	var state: GameState = GameState.new(1)
	assert_true(state.start_delve())
	assert_false(state.start_delve(), "a double click can't start a second delve")
	assert_eq(state.delve_count, 1)
	assert_true(state.end_delve())
	assert_false(state.end_delve())
	assert_eq(state.phase, GameState.Phase.TOWN)


func test_delve_seeds_are_stable_and_distinct() -> void:
	var state: GameState = GameState.new(42)
	# Golden values: changing these breaks replays of existing campaigns.
	assert_eq(state.delve_seed(1), 267748847088962415)
	assert_eq(state.delve_seed(2), 78818249385557424)
	assert_ne(GameState.new(43).delve_seed(1), state.delve_seed(1))
	assert_gt(state.delve_seed(1), 0)


func test_resources_are_whole_and_never_negative() -> void:
	var state: GameState = GameState.new()
	assert_true(state.add_resource("pearls", 5))
	assert_false(state.add_resource("pearls", 0))
	assert_false(state.add_resource("pearls", -3))
	assert_false(state.spend_resource("pearls", 6), "can't spend more than you have")
	assert_eq(state.resource("pearls"), 5)
	assert_true(state.spend_resource("pearls", 5))
	assert_eq(state.resource("pearls"), 0)
	assert_false(state.resources().has("pearls"), "empty resources are dropped")


func test_resources_copy_is_not_a_back_door() -> void:
	var state: GameState = GameState.new()
	state.add_resource("timber", 2)
	var copy: Dictionary[String, int] = state.resources()
	copy["timber"] = 999
	assert_eq(state.resource("timber"), 2)


func test_round_trip_through_a_real_save() -> void:
	var state: GameState = GameState.new(-8070450532247928832)
	state.add_resource("pearls", 12)
	state.add_resource("koban", 3)
	state.start_delve()
	var text: String = SaveCodec.encode({GameState.PAYLOAD_KEY: state.to_dict()})
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(text)
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	assert_eq(loaded.campaign_seed, -8070450532247928832, "64-bit seed survives JSON")
	assert_eq(loaded.phase, GameState.Phase.DELVE)
	assert_eq(loaded.delve_count, 1)
	assert_eq(loaded.resource("pearls"), 12)
	assert_eq(loaded.resource("koban"), 3)
	assert_eq(loaded.current_delve_seed(), state.current_delve_seed())


func test_from_dict_rejects_bad_data() -> void:
	var good: Dictionary = GameState.new(5).to_dict()
	assert_not_null(GameState.from_dict(good))
	var cases: Dictionary = {
		"unknown phase": {"phase": "BEACH"},
		"numeric seed": {"campaign_seed": 5},
		"fraction count": {"delve_count": 1.5},
		"negative count": {"delve_count": -1},
		"in a delve before any delve": {"phase": "DELVE", "delve_count": 0},
		"fraction resource": {"resources": {"pearls": 2.5}},
		"negative resource": {"resources": {"pearls": -2}},
		"text resource": {"resources": {"pearls": "lots"}},
		"resources not a dict": {"resources": [1, 2]},
	}
	for label: String in cases:
		var data: Dictionary = good.duplicate(true)
		data.merge(cases[label] as Dictionary, true)
		assert_null(GameState.from_dict(data), label)
