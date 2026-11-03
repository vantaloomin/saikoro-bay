extends GutTest
## Going down and coming up through the real Game and SceneFlow autoloads.

const TEST_SAVE: String = "user://test_saves/flow.save"

var _original_store: SaveStore
var _original_state: GameState


func before_each() -> void:
	_original_store = Game.store
	_original_state = Game.state
	Game.store = SaveStore.new(TEST_SAVE)
	Game.store.erase()
	Game.state = GameState.new(1234)
	Game.saving_locked = false
	SceneFlow.reduce_motion = true


func after_each() -> void:
	if SceneFlow.busy:
		await SceneFlow.transition_finished
	Game.store.erase()
	Game.store = _original_store
	Game.state = _original_state
	SceneFlow.reduce_motion = false


func test_go_down_saves_then_transitions_once() -> void:
	assert_true(Game.go_down())
	assert_true(SceneFlow.busy)
	assert_false(Game.go_down(), "a second press during the transition does nothing")
	assert_eq(Game.state.delve_count, 1)

	# The save was written before the transition, with the delve started.
	var saved: SaveStore.ReadResult = SaveStore.new(TEST_SAVE).read()
	assert_true(saved.is_ok())
	var loaded: GameState = GameState.from_dict(saved.payload[GameState.PAYLOAD_KEY])
	assert_eq(loaded.phase, GameState.Phase.DELVE)
	assert_eq(loaded.delve_count, 1)

	# No writing while the tide is moving: a save request is held.
	assert_true(Game.store.blocked)
	var seq_before: int = SaveStore.new(TEST_SAVE).read().seq
	assert_eq(Game.save(), ERR_BUSY)
	assert_eq(SaveStore.new(TEST_SAVE).read().seq, seq_before, "nothing written mid-transition")

	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	assert_false(SceneFlow.busy)
	assert_false(Game.store.blocked)
	assert_eq(SaveStore.new(TEST_SAVE).read().seq, seq_before + 1, "the held save landed after")
	assert_eq(get_tree().current_scene.scene_file_path, Game.DELVE_SCENE)


func test_come_up_returns_to_town_and_saves() -> void:
	Game.go_down()
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	assert_true(Game.come_up())
	assert_false(Game.come_up())
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	assert_eq(get_tree().current_scene.scene_file_path, Game.TOWN_SCENE)
	var loaded: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(loaded.phase, GameState.Phase.TOWN)


func test_load_or_new_resumes_the_saved_half() -> void:
	Game.state.start_delve()
	Game.save()
	Game.state = GameState.new(1)
	assert_eq(Game.load_or_new(), Game.DELVE_SCENE)
	assert_eq(Game.state.campaign_seed, 1234)
	assert_eq(Game.state.delve_count, 1)


func test_empty_slot_starts_a_new_campaign_in_town() -> void:
	assert_eq(Game.load_or_new(), Game.TOWN_SCENE)
	assert_eq(Game.state.delve_count, 0)
	assert_false(Game.saving_locked)


func test_newer_save_locks_saving() -> void:
	var body: String = "{}"
	DirAccess.make_dir_recursive_absolute(TEST_SAVE.get_base_dir())
	var file: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"format": SaveCodec.FORMAT, "version": SaveCodec.CURRENT_VERSION + 1, "sha256": body.sha256_text(),
	}) + "\n" + body + "\n")
	file.close()
	Game.load_or_new()
	assert_true(Game.saving_locked)
	assert_eq(Game.save(), ERR_UNAUTHORIZED)
