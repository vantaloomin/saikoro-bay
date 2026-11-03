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
	Game.state.arrive(Game.data)
	Game.run = null
	Game.saving_locked = false
	Game.save_problem = ""
	SceneFlow.reduce_motion = true


func after_each() -> void:
	if SceneFlow.busy:
		await SceneFlow.transition_finished
	Game.store.erase()
	Game.store = _original_store
	Game.state = _original_state
	SceneFlow.reduce_motion = false


func test_go_down_takes_the_town_s_kit() -> void:
	Game.state._villagers.append("shipwright")
	assert_true(Game.go_down())
	assert_not_null(Game.run.kit)
	assert_eq(Game.run.kit.perk("brace")["source"], "shipwright", "the town is the loadout")
	assert_eq(Game.run.perks, Game.run.kit.perks)
	var saved: Dictionary = SaveStore.new(TEST_SAVE).read().payload
	assert_false(JSON.stringify(saved).contains("\"faces\""), "the kit is never saved (Imogen's bridge review)")


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
	assert_false(Game.come_up(), "not mid-run: only from a landing, the vault or a wash-up")
	Game.run.step = DelveRun.Step.SURFACED
	assert_true(Game.come_up())
	assert_false(Game.come_up())
	assert_true(Game.tally_open)
	assert_false(SceneFlow.busy, "the tide waits for the tally's Continue")
	assert_eq(Game.settlement["outcome"], Haul.SURFACED)
	var banked: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(banked.phase, GameState.Phase.TOWN, "banked and saved before the tally shows")
	assert_true(Game.leave_tally())
	assert_false(Game.leave_tally(), "once only")
	assert_false(Game.tally_open)
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	assert_eq(get_tree().current_scene.scene_file_path, Game.TOWN_SCENE)
	assert_false(Game.settlement.is_empty(), "kept for the town's count-up")
	var loaded: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(loaded.phase, GameState.Phase.TOWN)


func test_load_or_new_resumes_the_saved_town() -> void:
	Game.state.add_resource("pearls", 3)
	Game.save()
	Game.state = GameState.new(1)
	assert_eq(Game.load_or_new(), Game.TOWN_SCENE)
	assert_eq(Game.state.campaign_seed, 1234)
	assert_eq(Game.state.resource("pearls"), 3)


func test_closing_mid_delve_washes_up_with_nothing() -> void:
	Game.state.add_resource("pearls", 3)
	Game.state.start_delve(Game.data)
	Game.save()
	Game.state = GameState.new(1)
	assert_eq(Game.load_or_new(), Game.TOWN_SCENE, "an abandoned delve lands in town")
	assert_eq(Game.state.phase, GameState.Phase.TOWN)
	assert_eq(Game.state.delve_count, 0, "it never happened for time: the next delve reuses its seed")
	assert_eq(Game.state.resource("pearls"), 3, "town resources are untouched")
	assert_eq(Game.state.last_delve["outcome"], Haul.ABANDONED)
	var saved: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(saved.phase, GameState.Phase.TOWN, "the wash-up is saved at once, so a second reload can't retry")


func test_going_down_builds_the_run_from_the_town() -> void:
	assert_true(Game.go_down())
	assert_not_null(Game.run)
	assert_eq(Game.run.delve_seed, Game.state.current_delve_seed())
	assert_eq(Game.run.map.rescue_villager, "pearl_diver")
	assert_eq(Game.run.hp, Game.run.max_hp)
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	Game.run.haul.add_resource("driftwood", 5)
	Game.run.step = DelveRun.Step.WASHED_UP
	assert_true(Game.come_up(), "the outcome comes from the run")
	assert_null(Game.run)
	assert_eq(Game.state.resource("driftwood"), 2)
	var saved: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(saved.resource("driftwood"), 2, "banked and saved before the tide moves")
	assert_eq(saved.phase, GameState.Phase.TOWN)


func test_closing_the_window_writes_a_held_save() -> void:
	Game.go_down()
	var seq_before: int = SaveStore.new(TEST_SAVE).read().seq
	assert_eq(Game.save(), ERR_BUSY, "held while the tide moves")
	Game._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(Game.store.has_pending_write())
	assert_true(Game.store.blocked, "flushing leaves the transition's block alone")
	assert_eq(SaveStore.new(TEST_SAVE).read().seq, seq_before + 1, "written before the window closes")
	await wait_for_signal(SceneFlow.transition_finished, 5.0)


func test_a_save_that_decodes_but_wont_load_is_kept_not_replaced() -> void:
	var bad: Dictionary = GameState.new(55).to_dict()
	bad["resources"] = {"pearls": 99}
	bad["last_delve"] = {"delve": 1, "outcome": "vanished"}
	assert_eq(Game.store.write({GameState.PAYLOAD_KEY: bad}), OK)
	assert_eq(Game.store.write({GameState.PAYLOAD_KEY: bad}), OK, "a second write fills the backup too")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(TEST_SAVE)
	Game.load_or_new()
	assert_push_error("decodes but doesn't load")
	assert_true(Game.saving_locked)
	assert_string_contains(Game.save_problem, "can't read your save")
	assert_eq(Game.save(), ERR_UNAUTHORIZED)
	Game.save()
	assert_eq(FileAccess.get_file_as_bytes(TEST_SAVE), before, "the campaign's bytes survive")
	Game.load_or_new()
	assert_push_error("decodes but doesn't load")
	var kept: PackedStringArray = DirAccess.get_files_at(TEST_SAVE.get_base_dir())
	var copies: int = 0
	for file_name: String in kept:
		if file_name.contains(".unloadable-"):
			copies += 1
			DirAccess.remove_absolute(TEST_SAVE.get_base_dir().path_join(file_name))
	assert_eq(copies, 2, "copied aside once each (main and backup), not again on the next launch")


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


func test_a_saved_town_that_breaks_the_data_locks_saving() -> void:
	var state: GameState = GameState.new(56)
	state.town.place("pagoda", Vector2i(0, 0))
	assert_eq(Game.store.write({GameState.PAYLOAD_KEY: state.to_dict()}), OK)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(TEST_SAVE)
	Game.load_or_new()
	assert_push_error("doesn't match this build's data")
	assert_push_error("decodes but doesn't load")
	assert_true(Game.saving_locked)
	assert_eq(Game.save(), ERR_UNAUTHORIZED)
	assert_eq(FileAccess.get_file_as_bytes(TEST_SAVE), before, "the campaign's bytes survive")
	for file_name: String in DirAccess.get_files_at(TEST_SAVE.get_base_dir()):
		if file_name.contains(".unloadable-"):
			DirAccess.remove_absolute(TEST_SAVE.get_base_dir().path_join(file_name))


func test_building_in_town_saves_at_once() -> void:
	Game.state.town.actions_left = 2
	Game.state.add_resource("driftwood", 4)
	assert_eq(Game.build("cottage", Vector2i(0, 0)), [] as Array[Dictionary])
	var saved: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(saved.town.placed.size(), 1)
	assert_eq([saved.town.actions_left, saved.resource("driftwood")], [1, 0])
	assert_eq(Game.move_building(1, Vector2i(2, 2)), "")
	saved = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq([saved.town.placed[0]["x"], saved.town.placed[0]["y"]], [2, 2], "a free move is saved too")
	assert_eq(Game.build("cottage", Vector2i(3, 3))[0]["text"], "Needs 4 more driftwood (you have 0) · found in fights and small locks below")


func test_a_rescued_villager_moves_into_a_free_home_before_the_save() -> void:
	Game.state.town.actions_left = 1
	Game.state.add_resource("driftwood", 4)
	Game.build("cottage", Vector2i(0, 0))
	assert_true(Game.go_down())
	await wait_for_signal(SceneFlow.transition_finished, 5.0)
	Game.run.haul.villagers.append("pearl_diver")
	Game.run.step = DelveRun.Step.SURFACED
	assert_true(Game.come_up())
	var saved: GameState = GameState.from_dict(SaveStore.new(TEST_SAVE).read().payload[GameState.PAYLOAD_KEY])
	assert_eq(saved.town.homes, {"pearl_diver": 1} as Dictionary[String, int])
	assert_eq(Game.swap_home("pearl_diver", 1), "Already lives here")
	assert_true(Game.leave_tally())
	await wait_for_signal(SceneFlow.transition_finished, 5.0)


## Imogen's town review, finding 1: go down, quit, reload, as often as you
## like. Actions never grow, and the map never changes.
func test_quitting_mid_delve_never_mints_actions_or_a_new_map() -> void:
	Game.state.town.actions_left = 3
	Game.save()
	var seed_before: int = Game.state.delve_seed(1)
	for attempt: int in 3:
		assert_true(Game.state.start_delve(Game.data))
		assert_eq(Game.state.current_delve_seed(), seed_before, "attempt %d gets the same map" % attempt)
		Game.save()
		Game.state = GameState.new(1)
		Game.load_or_new()
		assert_eq(Game.state.town.actions_left, 3, "attempt %d: the actions held at Go down, no more" % attempt)
		assert_eq(Game.state.town.kept, 1)
	assert_eq(Game.state.delve_count, 0)


func test_a_v2_save_gets_exactly_one_budget() -> void:
	for fixture: String in ["TOWN", "DELVE"]:
		var text: String = FileAccess.get_file_as_string("res://tests/saves/v2_cafe_two_villagers.save")
		if fixture == "DELVE":
			var lines: PackedStringArray = text.split("\n")
			var body: String = lines[1].replace("\"phase\":\"TOWN\"", "\"phase\":\"DELVE\"")
			text = JSON.stringify({"format": SaveCodec.FORMAT, "version": 2, "seq": 9,
				"sha256": SaveCodec.digest(2, 9, body)}, "", true) + "\n" + body + "\n"
		DirAccess.make_dir_recursive_absolute(TEST_SAVE.get_base_dir())
		var file: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		Game.load_or_new()
		assert_eq(Game.state.phase, GameState.Phase.TOWN)
		assert_eq(Game.state.last_delve["outcome"], Haul.ABANDONED if fixture == "DELVE" else Haul.CLEARED)
		assert_eq([Game.state.town.actions_left, Game.state.town.kept], [4, 0], fixture)
		Game.state = GameState.new(1)
		Game.load_or_new()
		assert_eq(Game.state.town.actions_left, 4, "%s: reloading doesn't grant another budget" % fixture)
		Game.store.erase()
