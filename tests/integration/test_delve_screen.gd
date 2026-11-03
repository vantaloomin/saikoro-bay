extends GutTest
## The delve screen (specs/delve-map.md section 8): the map only shows what
## the player can see, picks are guarded, fights sit under the haul strip,
## and the landing shows the stakes and can't be mashed through.

const SCENE: PackedScene = preload("res://game/delve/delve.tscn")
const VILLAGERS: Array[String] = ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]

var _original_state: GameState
var _original_run: DelveRun


func before_each() -> void:
	_original_state = Game.state
	_original_run = Game.run
	Game.state = GameState.new(77)
	Settings.reduce_motion = true


func after_each() -> void:
	Game.state = _original_state
	Game.run = _original_run
	Settings.reduce_motion = false


func _screen(run: DelveRun) -> Control:
	Game.run = run
	var screen: Control = SCENE.instantiate() as Control
	add_child_autofree(screen)
	return screen


func _new_run(seed_value: int = 5, perks: Array[Dictionary] = []) -> DelveRun:
	return DelveRun.create(Game.data, seed_value, Kit.fresh(Game.data, perks), VILLAGERS, LANDMARKS, 0)


## Plays the run with the bots up to its first landing.
func _to_landing(run: DelveRun) -> bool:
	for guard: int in 40:
		match run.step:
			DelveRun.Step.CHOOSE_ROOM:
				run.choose(run.reachable()[0])
			DelveRun.Step.IN_ROOM:
				if run.fight != null:
					PlannerBot.new().play_fight(run.fight)
				if run.room != null:
					RoomBot.new().play_room(run.room)
				run.finish_room()
				run.hp = maxi(run.hp, 12)
			DelveRun.Step.LANDING:
				return true
			_:
				return false
	return false


func _landing_run() -> DelveRun:
	for s: int in range(1, 60):
		var run: DelveRun = _new_run(s)
		if _to_landing(run):
			return run
	fail_test("no run reached a landing")
	return null


func test_the_map_shows_only_what_the_player_can_see() -> void:
	var run: DelveRun = _new_run()
	var screen: Control = _screen(run)
	var map: MapView = screen.get("_map")
	assert_true(map.visible)
	var rows: Array = RunView.new(run).rows()
	for cell: Vector2i in map._nodes:
		assert_eq(map._nodes[cell].type, (rows[cell.x] as Array)[cell.y]["type"])
		if cell.x > run.reveal_rows - 1:
			assert_eq(map._nodes[cell].type, RunView.HIDDEN, "row %d isn't revealed yet" % cell.x)
	var next: Array[int] = []
	for cell: Vector2i in map._nodes:
		if map._nodes[cell].state == "next":
			next.append(cell.y)
	next.sort()
	assert_eq(next, run.reachable())


func test_focus_starts_where_you_stand_with_no_path_lit() -> void:
	var run: DelveRun = _new_run()
	var map: MapView = _screen(run).get("_map")
	assert_eq(get_viewport().gui_get_focus_owner(), map._entrance, "the way in, not a room")
	for cell: Vector2i in map._nodes:
		assert_false(map._nodes[cell].lit)
	assert_eq(map._room_name.text, "Ways down")


func test_a_pick_right_after_the_map_appears_is_ignored() -> void:
	var run: DelveRun = _new_run()
	var screen: Control = _screen(run)
	var map: MapView = screen.get("_map")
	map._nodes[Vector2i(0, 0)].picked.emit(0)
	assert_eq(run.step, DelveRun.Step.CHOOSE_ROOM, "inside the guard")
	map._guard_until = 0
	map._nodes[Vector2i(0, 0)].picked.emit(0)
	assert_eq(run.step, DelveRun.Step.IN_ROOM)
	var board: FightBoard = screen.get("_board")
	assert_not_null(board, "floor 1 opens on a fight")
	assert_eq(board.top_inset, HaulStrip.HEIGHT, "under the haul strip")
	assert_false(map.visible)


func test_hovering_a_room_lights_the_paths_through_it() -> void:
	var run: DelveRun = _new_run()
	var map: MapView = _screen(run).get("_map")
	map._on_hovered(Vector2i(1, 0), true)
	assert_true(map._nodes[Vector2i(1, 0)].lit)
	assert_string_starts_with(map._summary.text, "Through here:")
	map._on_hovered(Vector2i(1, 0), false)
	assert_false(map._nodes[Vector2i(1, 0)].lit)


func test_the_landing_shows_the_stakes_with_nothing_focused() -> void:
	var run: DelveRun = _landing_run()
	run.haul.add_resource("driftwood", 9)
	run.haul.villagers.append("pearl_diver")
	var screen: Control = _screen(run)
	var landing: LandingPanel = screen.get("_landing")
	assert_true(landing.visible)
	assert_false((screen.get("_map") as MapView).visible)
	assert_null(get_viewport().gui_get_focus_owner(), "the first press only picks a side")
	var keep: int = run.haul.resource("driftwood")
	assert_has(landing.risk_lines(run.haul), "Driftwood  %d → %d" % [keep, keep / 2])
	assert_has(landing.risk_lines(run.haul), "The pearl diver goes back below the tide")
	assert_has(landing.keep_lines(run.haul), "Driftwood  %d" % keep)
	assert_eq(landing._surface.size, landing._deeper.size, "the same size")


func test_the_landing_ignores_presses_for_a_moment() -> void:
	var run: DelveRun = _landing_run()
	var screen: Control = _screen(run)
	var landing: LandingPanel = screen.get("_landing")
	landing._deeper.pressed.emit()
	assert_eq(run.step, DelveRun.Step.LANDING, "inside the guard")
	landing._guard_until = 0
	landing._deeper.pressed.emit()
	assert_eq(run.step, DelveRun.Step.CHOOSE_ROOM)
	assert_eq(run.floor_index, 1)
	assert_true((screen.get("_map") as MapView).visible)


func test_the_peek_names_the_next_floors_prize() -> void:
	var landing: LandingPanel = LandingPanel.new()
	landing.setup(Game.data)
	assert_eq(landing.left_behind_lines({"floor": 1, "rows": [], "prize": {"rescue": "pearl_diver"}}),
		PackedStringArray(["The caged pearl diver waits for another delve", "Floor 2's loot"]), "surfacing costs something too")
	assert_eq(landing.below_text({"floor": 1, "rows": [], "prize": {"rescue": "shipwright"}}),
		"Below: floor 2 · a caged villager (Shipwright)")
	assert_eq(landing.below_text({"floor": 2, "rows": [], "prize": {"vault": {"landmark": "cafe"}}}),
		"Below: floor 3 · Koban's vault · the Café")
	landing.free()


func test_foresight_shows_who_gives_it() -> void:
	var run: DelveRun = null
	for s: int in range(1, 60):
		run = _new_run(s, [{"perk": "foresight", "source": "shrine_keeper"}] as Array[Dictionary])
		if _to_landing(run):
			break
	assert_eq(RunView.new(run).foresight_source(), "shrine_keeper")
	assert_eq((RunView.new(run).peek()["rows"] as Array).size(), 2, "Foresight peeks two rows")


func test_the_strip_says_how_far_the_next_safe_exit_is() -> void:
	var run: DelveRun = _new_run()
	assert_eq(HaulStrip.progress_text(RunView.new(run)), "Floor 1 of 3 · landing in 3 rooms")
	run.choose(run.reachable()[0])
	assert_eq(HaulStrip.progress_text(RunView.new(run)), "Floor 1 of 3 · landing 2 rooms after this")


func test_dice_rooms_play_on_the_room_board() -> void:
	for s: int in range(1, 80):
		var run: DelveRun = _new_run(s)
		for guard: int in 40:
			if run.step == DelveRun.Step.CHOOSE_ROOM:
				var picked: int = run.reachable()[0]
				for c: int in run.reachable():
					if DelveRun.is_dice_room(run.map.room(run.floor_index, run.row + 1, c).type):
						picked = c
				run.choose(picked)
			elif run.step == DelveRun.Step.IN_ROOM and run.fight != null:
				PlannerBot.new().play_fight(run.fight)
				run.finish_room()
				run.hp = maxi(run.hp, 12)
			else:
				break
		if run.step != DelveRun.Step.IN_ROOM or run.room == null:
			continue
		var screen: Control = _screen(run)
		var board: RoomBoard = screen.get("_room_board")
		assert_not_null(board)
		assert_eq(board.top_inset, HaulStrip.HEIGHT)
		while run.room.state == DiceRoom.State.PLAYER_TURN:
			board._on_verb()
		board._results_shown_at -= RoomBoard.RESULT_GUARD_MS
		board._continue.pressed.emit()
		assert_null(run.room, "the room finished")
		assert_true(run.step in [DelveRun.Step.CHOOSE_ROOM, DelveRun.Step.LANDING, DelveRun.Step.WASHED_UP])
		return
	fail_test("no run reached a dice room")


func test_kobans_vault_plays_on_the_vault_board() -> void:
	for s: int in range(1, 80):
		var run: DelveRun = _new_run(s)
		for guard: int in 80:
			match run.step:
				DelveRun.Step.CHOOSE_ROOM:
					run.choose(run.reachable()[0])
				DelveRun.Step.IN_ROOM:
					if run.fight != null:
						PlannerBot.new().play_fight(run.fight)
					if run.room != null:
						RoomBot.new().play_room(run.room)
					run.finish_room()
					run.hp = maxi(run.hp, 12)
				DelveRun.Step.LANDING:
					run.go_deeper()
		if run.step != DelveRun.Step.VAULT:
			continue
		var screen: Control = _screen(run)
		var board: VaultBoard = screen.get("_vault_board")
		assert_not_null(board)
		assert_eq(board.top_inset, HaulStrip.HEIGHT)
		assert_eq(board.vault, run.vault)
		assert_eq(run.vault.round_number, 1, "the screen doesn't play the vault for you")
		assert_false(run.vault.is_over())
		VaultBot.new().play_vault(run.vault)
		board.finished.emit()
		assert_true(run.step in [DelveRun.Step.CLEARED, DelveRun.Step.WASHED_UP], "the vault's end ends the delve")
		screen.call("_on_vault_over")
		assert_true(run.step in [DelveRun.Step.CLEARED, DelveRun.Step.WASHED_UP], "a second end is ignored")
		return
	fail_test("no run reached the vault")
