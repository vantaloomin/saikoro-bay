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
	assert_true(state.finish_delve(Haul.SURFACED, Haul.new()))
	assert_false(state.finish_delve(Haul.SURFACED, Haul.new()), "banks only once")
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
	state.meet_twist("snake_eyes")
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
	assert_true(loaded.has_seen_twist("snake_eyes"))
	assert_false(loaded.has_seen_twist("house_lock"))


func test_each_twist_is_met_once() -> void:
	var state: GameState = GameState.new(1)
	assert_true(state.meet_twist("house_lock"))
	assert_false(state.meet_twist("house_lock"), "the banner shows only the first time")
	assert_false(state.meet_twist("none"), "the baseline enemy has no twist")
	assert_false(state.meet_twist(""))
	assert_true(state.has_seen_twist("house_lock"))


func test_saves_from_before_seen_twists_still_load() -> void:
	var old: Dictionary = GameState.new(5).to_dict()
	old.erase("seen_twists")
	var loaded: GameState = GameState.from_dict(old)
	assert_not_null(loaded)
	assert_false(loaded.has_seen_twist("snake_eyes"))


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
		"seen twists not a list": {"seen_twists": "snake_eyes"},
		"seen twist not text": {"seen_twists": [3]},
		"villagers not a list": {"villagers": "pearl_diver"},
		"villager not text": {"villagers": [1]},
		"empty landmark id": {"landmarks": [""]},
		"last delve not a dict": {"last_delve": []},
		"last delve unknown outcome": {"last_delve": {"delve": 1, "outcome": "vanished", "kept": {"resources": {}, "villagers": [], "landmark": ""}}},
		"last delve fraction": {"last_delve": {"delve": 1, "outcome": "surfaced", "kept": {"resources": {"pearls": 1.5}, "villagers": [], "landmark": ""}}},
	}
	for label: String in cases:
		var data: Dictionary = good.duplicate(true)
		data.merge(cases[label] as Dictionary, true)
		assert_null(GameState.from_dict(data), label)
	for field: String in ["villagers", "landmarks", "last_delve", "town"]:
		var missing: Dictionary = good.duplicate(true)
		missing.erase(field)
		assert_null(GameState.from_dict(missing), "a version 3 save needs %s" % field)


# --- Banking a delve (delve-map spec 8a, rule 1) ----------------------------------

func _haul() -> Haul:
	var haul: Haul = Haul.new()
	haul.add_resource("driftwood", 9)
	haul.add_resource("pearls", 1)
	haul.villagers.append("pearl_diver")
	haul.landmark = "cafe"
	return haul


func _in_delve() -> GameState:
	var state: GameState = GameState.new(3)
	state.add_resource("driftwood", 2)
	state.start_delve()
	return state


func test_surfacing_banks_the_whole_haul() -> void:
	var state: GameState = _in_delve()
	assert_true(state.finish_delve(Haul.SURFACED, _haul()))
	assert_eq(state.phase, GameState.Phase.TOWN)
	assert_eq(state.resource("driftwood"), 11)
	assert_eq(state.resource("pearls"), 1)
	assert_eq(state.villagers(), ["pearl_diver"] as Array[String])
	assert_eq(state.landmarks(), ["cafe"] as Array[String])
	assert_eq(state.last_delve, {"delve": 1, "outcome": "surfaced", "kept": _haul().to_dict()})


func test_washing_up_keeps_half_and_sends_the_rest_back() -> void:
	var state: GameState = _in_delve()
	assert_true(state.finish_delve(Haul.WASHED_UP, _haul()))
	assert_eq(state.resource("driftwood"), 2 + 4)
	assert_eq(state.resource("pearls"), 0, "half of 1 rounds down")
	assert_eq(state.villagers(), [] as Array[String], "the villager goes back below")
	assert_eq(state.landmarks(), [] as Array[String])
	var data: GameData = GameData.load_dir()
	assert_eq(state.villagers_left(data)[0], "pearl_diver", "and turns up again next delve")


func test_an_abandoned_delve_keeps_nothing() -> void:
	var state: GameState = _in_delve()
	assert_true(state.finish_delve(Haul.ABANDONED, _haul()))
	assert_eq(state.resource("driftwood"), 2)
	assert_eq(state.last_delve["outcome"], "abandoned")
	assert_eq(state.phase, GameState.Phase.TOWN)


func test_banking_refuses_bad_calls_and_never_duplicates() -> void:
	var state: GameState = GameState.new(3)
	assert_false(state.finish_delve(Haul.SURFACED, _haul()), "not in a delve")
	state.start_delve()
	assert_false(state.finish_delve("vanished", _haul()), "unknown outcome")
	assert_eq(state.phase, GameState.Phase.DELVE)
	assert_true(state.finish_delve(Haul.SURFACED, _haul()))
	state.start_delve()
	assert_true(state.finish_delve(Haul.CLEARED, _haul()))
	assert_eq(state.villagers(), ["pearl_diver"] as Array[String], "never twice")
	assert_eq(state.landmarks(), ["cafe"] as Array[String])


func test_town_villagers_bring_their_perks_and_leave_the_pools() -> void:
	var data: GameData = GameData.load_dir()
	var state: GameState = _in_delve()
	state.finish_delve(Haul.SURFACED, _haul())
	assert_eq(state.delve_perks(data), [{"perk": "nudge", "source": "pearl_diver"}] as Array[Dictionary])
	assert_eq(state.villagers_left(data), ["shipwright", "onsen_keeper", "shrine_keeper"] as Array[String])
	assert_eq(state.landmarks_left(data), ["hot_spring"] as Array[String])


func test_banked_state_round_trips_through_a_save() -> void:
	var state: GameState = _in_delve()
	state.finish_delve(Haul.WASHED_UP, _haul())
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(SaveCodec.encode({GameState.PAYLOAD_KEY: state.to_dict()}))
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	assert_eq(loaded.to_dict(), state.to_dict())


func test_version_1_saves_upgrade_with_an_empty_town() -> void:
	var v1: Dictionary = GameState.new(9).to_dict()
	for field: String in ["villagers", "landmarks", "last_delve", "town"]:
		v1.erase(field)
	v1["phase"] = "DELVE"
	v1["delve_count"] = 2
	var body: String = JSON.stringify({GameState.PAYLOAD_KEY: v1}, "", true, true)
	var text: String = JSON.stringify({"format": SaveCodec.FORMAT, "version": 1, "seq": 4,
		"sha256": SaveCodec.digest(1, 4, body)}, "", true) + "\n" + body + "\n"
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(text)
	assert_true(decoded.is_ok())
	assert_eq(decoded.version, SaveCodec.CURRENT_VERSION)
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	assert_eq(loaded.villagers(), [] as Array[String])
	assert_eq(loaded.last_delve, {})
	assert_eq(loaded.phase, GameState.Phase.DELVE, "still mid-delve: Game turns that into a wash-up")
