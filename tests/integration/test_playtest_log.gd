extends GutTest
## PlaytestLog: events land in the file, and observer prompts mark the next delve.

const LOG: String = "user://test_playtest/session.jsonl"
const TEST_SAVE: String = "user://test_saves/playtest.save"

var _original_store: SaveStore
var _original_state: GameState


func before_each() -> void:
	_original_store = Game.store
	_original_state = Game.state
	Game.store = SaveStore.new(TEST_SAVE)
	Game.store.erase()
	Game.state = GameState.new(77)
	SceneFlow.reduce_motion = true


func after_each() -> void:
	if SceneFlow.busy:
		await SceneFlow.transition_finished
	PlaytestLog.stop()
	DirAccess.remove_absolute(LOG)
	Game.store.erase()
	Game.store = _original_store
	Game.state = _original_state
	SceneFlow.reduce_motion = false


func test_off_by_default_in_tests() -> void:
	assert_false(PlaytestLog.enabled)
	PlaytestLog.log_event("ignored")
	assert_false(FileAccess.file_exists(LOG))


func test_a_session_starts_with_the_campaign_it_loaded() -> void:
	var fake: bool = Game.fake_town
	PlaytestLog.start_after_load(LOG)
	assert_false(FileAccess.file_exists(LOG), "nothing is written before the campaign is in place")
	Game.load_or_new(true)
	PlaytestLog.stop()
	var first: Dictionary = _read_events()[0]
	assert_eq(first["event"], "session_start")
	assert_eq(first["fake_town"], true, "exit-check sessions can be left out")
	assert_eq(first["campaign_seed"], str(FakeTown.SEED), "the log ties back to the campaign")
	SaveStore.new(FakeTown.SAVE_PATH).erase()
	Game.fake_town = fake


func test_delves_record_prompt_and_town_time() -> void:
	assert_eq(PlaytestLog.start(LOG), OK)
	# First delve: the observer nudged the player.
	PlaytestLog.mark_prompt()
	Game.go_down()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	Game.run.step = DelveRun.Step.SURFACED
	Game.come_up()
	Game.leave_tally()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	# Second delve: no nudge.
	Game.go_down()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	PlaytestLog.stop()

	var all_events: Array[Dictionary] = _read_events()
	var fights: Array[Dictionary] = all_events.filter(func(e: Dictionary) -> bool: return e["event"] == "fight_start")
	assert_eq(fights.size(), 0, "each delve opens on the map: no fight until a room is picked")
	var events: Array[Dictionary] = all_events.filter(func(e: Dictionary) -> bool: return e["event"] != "fight_start")
	var names: Array = events.map(func(e: Dictionary) -> String: return e["event"])
	assert_eq(names, ["session_start", "observer_prompt", "delve_start", "delve_end", "delve_start", "session_end"])
	assert_eq(events[2]["prompted"], true)
	assert_eq(events[2]["delve"], 1.0)
	assert_true(events[2].has("time_in_town_ms"))
	assert_eq(events[4]["prompted"], false, "the prompt only counts for the visit it happened in")
	assert_eq(events[4]["seed"], str(Game.state.delve_seed(2)))
	assert_eq((events[2]["map"] as Dictionary)["seed"], str(Game.state.delve_seed(1)), "the map's replay inputs")
	assert_eq(events[2]["roller"], float(RngStreams.ROLLER), "which way the dice drew, for replay")
	assert_not_null(Kit.from_dict(Game.data, events[2]["kit"]), "the kit taken down is logged, strictly replayable")
	assert_eq((events[2]["map"] as Dictionary)["villagers_left"], ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"])
	assert_eq(events[3]["outcome"], "surfaced")
	assert_eq(events[0]["campaign_seed"], "77")


func _read_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(LOG).split("\n", false):
		events.append(JSON.parse_string(line) as Dictionary)
	return events
