extends GutTest
## Dates and affection in the sim (M5: RD-1, RD-2, RD-5, RD-6): a date
## needs the villager in town, a placed date spot and an action; finishing
## spends the action and keeps the affection in one call; affection only
## rises; save version 4 carries both.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


## A town with the Pearl diver (happy, by the sea) and the Shipwright
## (unhappy, no boats) housed, the Café won and placed, and `actions` to spend.
func _town(actions: int = 3, place_cafe: bool = true) -> GameState:
	var state: GameState = GameState.new(5)
	state.town.needs_budget = false
	state.town.actions_left = 10
	state.add_resource("driftwood", 20)
	state._villagers.append_array(["pearl_diver", "shipwright"] as Array[String])
	state._landmarks.append("cafe")
	assert_eq(state.build(data, "cottage", Vector2i(0, 7)), [] as Array[Dictionary])
	assert_eq(state.build(data, "cottage", Vector2i(1, 7)), [] as Array[Dictionary])
	if place_cafe:
		assert_eq(state.build(data, "cafe", Vector2i(0, 0)), [] as Array[Dictionary])
	state.town.actions_left = actions
	state.town.kept = 0
	return state


func _texts(refusals: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for refusal: Dictionary in refusals:
		out.append(str(refusal["text"]))
	return out


func test_the_data_loads_with_a_date_for_every_villager() -> void:
	assert_true(data.is_valid(), "\n".join(data.errors))
	for villager: String in data.ids("villagers"):
		assert_false(GameState.date_row(data, villager).is_empty(), "%s has a date" % villager)
	for spot: String in data.ids("date_spots"):
		assert_true(data.has_row("landmarks", spot), "%s is a landmark" % spot)


func test_one_good_date_can_reach_the_scene_milestone() -> void:
	# Plan: one date per villager unlocks their scene when it goes well.
	for villager: String in data.ids("villagers"):
		var date: Dictionary = GameState.date_row(data, villager)
		assert_true(Affection.scene_unlocked(data, date["max_gain"] as int), "%s's best date reaches it" % villager)


func test_a_date_needs_the_villager_a_placed_spot_and_an_action() -> void:
	var state: GameState = _town()
	assert_eq(state.date_refusals(data, "pearl_diver", "cafe"), [] as Array[Dictionary])
	assert_eq(_texts(state.date_refusals(data, "onsen_keeper", "cafe")), ["Not in town"] as Array[String])
	assert_eq(_texts(state.date_refusals(data, "pearl_diver", "hot_spring")),
		["Win the Hot Spring in Koban's vault"] as Array[String])
	assert_eq(_texts(state.date_refusals(data, "pearl_diver", "net_shed")), ["Not a date spot"] as Array[String])
	state.town.actions_left = 0
	assert_eq(_texts(state.date_refusals(data, "pearl_diver", "cafe")), ["No actions left"] as Array[String])


func test_a_won_spot_waiting_in_the_tray_says_to_place_it() -> void:
	var state: GameState = _town(3, false)
	assert_eq(_texts(state.date_refusals(data, "pearl_diver", "cafe")), ["Place the Café in town first"] as Array[String])
	assert_eq(state.date_spots_placed(data), [] as Array[String])
	assert_eq(state.date_refusals(data, "pearl_diver").size(), 1, "the Date button says it needs a spot")


func test_no_dates_mid_delve() -> void:
	var state: GameState = _town()
	state.phase = GameState.Phase.DELVE
	assert_eq(_texts(state.date_refusals(data, "pearl_diver", "cafe")), ["Not in town"] as Array[String])
	assert_null(state.begin_date(data, "pearl_diver", "cafe", 0))


func test_starting_a_date_changes_nothing() -> void:
	var state: GameState = _town()
	var before: Dictionary = state.to_dict()
	var session: DateSession = state.begin_date(data, "pearl_diver", "cafe", ContentLevel.Level.FULL)
	assert_not_null(session)
	assert_eq([session.spot, session.dates_done, session.affection, session.content_level],
		["cafe", 0, 0, ContentLevel.Level.FULL])
	assert_true(session.villager_happy, "the Pearl diver lives by the sea")
	assert_false(state.begin_date(data, "shipwright", "cafe", 0).villager_happy, "no boats near the Shipwright")
	session.affection += 2
	assert_eq(state.to_dict(), before, "points stay in the session until the date ends")


func test_finishing_spends_the_action_and_keeps_the_points_once() -> void:
	var state: GameState = _town(2)
	var session: DateSession = state.begin_date(data, "shipwright", "cafe", 0)
	session.affection += 1
	assert_eq(state.finish_date(data, session), [] as Array[Dictionary])
	assert_eq(session.kept, 2, "one from the choice, one for finishing")
	assert_eq(state.affection("shipwright"), 2)
	assert_eq(state.dates_done("shipwright"), 1)
	assert_eq(state.town.actions_left, 1)
	assert_eq(_texts(state.finish_date(data, session)), ["This date is over"] as Array[String], "kept once")
	assert_eq([state.affection("shipwright"), state.town.actions_left], [2, 1])
	session.affection += 5
	assert_eq(session.gained(), 1, "a finished session no longer moves")


func test_affection_only_rises_and_a_date_is_capped() -> void:
	var state: GameState = _town()
	var session: DateSession = state.begin_date(data, "pearl_diver", "cafe", 0)
	session.affection += 1
	session.affection -= 1
	assert_eq(session.gained(), 1, "lowering is ignored")
	session.affection = -10
	assert_eq(session.gained(), 1)
	session.affection += 10
	assert_eq(session.gained(), session.max_gain, "capped at max_gain")
	state.finish_date(data, session)
	assert_eq(state.affection("pearl_diver"), session.max_gain, "finishing can't push past the cap")


func test_a_session_from_before_another_date_is_refused() -> void:
	var state: GameState = _town()
	var first: DateSession = state.begin_date(data, "pearl_diver", "cafe", 0)
	var second: DateSession = state.begin_date(data, "pearl_diver", "cafe", 0)
	assert_eq(state.finish_date(data, first), [] as Array[Dictionary])
	var before: Dictionary = state.to_dict()
	assert_eq(_texts(state.finish_date(data, second)), ["This date is out of date"] as Array[String])
	assert_eq(state.to_dict(), before)


func test_finishing_with_no_action_left_changes_nothing() -> void:
	var state: GameState = _town(1)
	var session: DateSession = state.begin_date(data, "pearl_diver", "cafe", 0)
	state.town.actions_left = 0
	var before: Dictionary = state.to_dict()
	assert_eq(_texts(state.finish_date(data, session)), ["No actions left"] as Array[String])
	assert_eq(state.to_dict(), before)
	assert_false(session.finished)


func test_dates_repeat_and_count() -> void:
	var state: GameState = _town(3)
	for i: int in 2:
		var session: DateSession = state.begin_date(data, "pearl_diver", "cafe", 0)
		assert_eq(session.dates_done, i)
		state.finish_date(data, session)
	assert_eq(state.dates_done("pearl_diver"), 2)
	assert_eq(state.affection("pearl_diver"), 2, "one per finished date with no good answers")


func test_milestones_reached_and_next() -> void:
	assert_eq(Affection.reached(data, 0), {})
	assert_eq(Affection.next(data, 0)["id"], "fond")
	assert_eq(Affection.reached(data, 2)["id"], "fond")
	assert_eq(Affection.next(data, 2)["id"], "close")
	assert_eq(Affection.reached(data, 9)["id"], "close")
	assert_eq(Affection.next(data, 9), {})
	assert_false(Affection.scene_unlocked(data, 2))
	assert_true(Affection.scene_unlocked(data, 3))
	assert_eq(Affection.top(data), 3)


func test_affection_and_dates_round_trip_through_the_save() -> void:
	var state: GameState = _town()
	var session: DateSession = state.begin_date(data, "pearl_diver", "cafe", 0)
	session.affection += 1
	state.finish_date(data, session)
	var text: String = SaveCodec.encode({GameState.PAYLOAD_KEY: state.to_dict()})
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(text)
	assert_true(decoded.is_ok())
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	assert_eq(loaded.affection("pearl_diver"), 2)
	assert_eq(loaded.dates_done("pearl_diver"), 1)
	assert_eq(loaded.to_dict(), state.to_dict())
	assert_eq(loaded.town_problems(data), PackedStringArray())


func test_bad_affection_in_a_save_is_refused() -> void:
	var base: Dictionary = _town().to_dict()
	for bad: Variant in [null, [], {"pearl_diver": -1}, {"pearl_diver": 1.5}, {"": 2}, {"pearl_diver": "x"}]:
		for field: String in ["affection", "dates_done"]:
			var payload: Dictionary = JSON.parse_string(JSON.stringify(base))
			payload[field] = bad
			assert_null(GameState.from_dict(payload), "%s = %s" % [field, bad])


func test_affection_for_someone_not_in_town_is_a_problem() -> void:
	var state: GameState = _town()
	state._affection["onsen_keeper"] = 2
	assert_eq(state.town_problems(data).size(), 1)


func test_a_v3_save_upgrades_with_no_affection() -> void:
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(FileAccess.get_file_as_string("res://tests/saves/v3_built_town.save"))
	assert_true(decoded.is_ok(), "the v3 fixture still loads")
	assert_eq(decoded.version, 4)
	var loaded: GameState = GameState.from_dict(decoded.payload[GameState.PAYLOAD_KEY])
	assert_not_null(loaded)
	for villager: String in loaded.villagers():
		assert_eq([loaded.affection(villager), loaded.dates_done(villager)], [0, 0])
	assert_eq(loaded.town_problems(data), PackedStringArray())


func test_a_save_without_affection_is_refused_at_version_4() -> void:
	var payload: Dictionary = JSON.parse_string(JSON.stringify(_town().to_dict()))
	payload.erase("affection")
	assert_null(GameState.from_dict(payload), "an older build's save comes through migrate_to_v4 instead")


func test_date_data_rules() -> void:
	var texts: Dictionary[String, String] = {}
	for table: String in GameData.TABLES:
		texts[table] = FileAccess.get_file_as_string("res://data/%s.json" % table)
	var bad_dates: Dictionary = JSON.parse_string(texts["dates"])
	(bad_dates["items"] as Array)[1]["villager"] = "pearl_diver"
	(bad_dates["items"] as Array)[2]["script"] = "res://data/x.dialogue"
	(bad_dates["items"] as Array)[3]["max_gain"] = -1
	var bad_milestones: Dictionary = JSON.parse_string(texts["affection"])
	(bad_milestones["items"] as Array)[1]["points"] = 2
	texts["dates"] = JSON.stringify(bad_dates)
	texts["affection"] = JSON.stringify(bad_milestones)
	var loaded: GameData = GameData.new()
	loaded.load_texts(texts)
	var joined: String = "\n".join(loaded.errors)
	assert_string_contains(joined, "already has date")
	assert_string_contains(joined, "res://dialogue/")
	assert_string_contains(joined, "max_gain can't be negative")
	assert_string_contains(joined, "rising in file order")
