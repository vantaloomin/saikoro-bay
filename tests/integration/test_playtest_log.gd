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


func test_delves_record_prompt_and_town_time() -> void:
	assert_eq(PlaytestLog.start(LOG), OK)
	# First delve: the observer nudged the player.
	PlaytestLog.mark_prompt()
	Game.go_down()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	Game.come_up()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	# Second delve: no nudge.
	Game.go_down()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	PlaytestLog.stop()

	var events: Array[Dictionary] = _read_events()
	var names: Array = events.map(func(e: Dictionary) -> String: return e["event"])
	assert_eq(names, ["session_start", "observer_prompt", "delve_start", "delve_end", "delve_start", "session_end"])
	assert_eq(events[2]["prompted"], true)
	assert_eq(events[2]["delve"], 1.0)
	assert_true(events[2].has("time_in_town_ms"))
	assert_eq(events[4]["prompted"], false, "the prompt only counts for the visit it happened in")
	assert_eq(events[4]["seed"], str(Game.state.delve_seed(2)))
	assert_eq(events[0]["campaign_seed"], "77")


func _read_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(LOG).split("\n", false):
		events.append(JSON.parse_string(line) as Dictionary)
	return events
