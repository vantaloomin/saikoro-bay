extends GutTest
## The room board drives a DiceRoom only through its moves, and says what
## the big button will do before you press it (Mara's map review #7, #9).

const NUDGE: Array[Dictionary] = [{"perk": "nudge", "source": "pearl_diver"}]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func before_each() -> void:
	Settings.reduce_motion = true


func after_each() -> void:
	Settings.reduce_motion = false


func _board(room_id: String, values: Array, hp: int = 30, caged: String = "") -> RoomBoard:
	var room: DiceRoom = DiceRoom.create(data, "fresh", room_id, RngStreams.new(7), NUDGE, hp)
	for i: int in values.size():
		room.hand[i].value = values[i]
	var board: RoomBoard = RoomBoard.new()
	board.setup(room, data, caged)
	add_child_autofree(board)
	return board


func _place(board: RoomBoard, die_id: int, slot_id: String) -> void:
	board._on_die_pressed(die_id)
	board._on_slot_pressed(slot_id)


func test_treasure_previews_its_loot_and_opens_with_one_press() -> void:
	var board: RoomBoard = _board("treasure", [4, 4, 2, 6])
	assert_eq(board._end_preview.text, "Nothing yet")
	assert_eq(board._verb.text, "Open")
	_place(board, 0, "pearl_lock")
	_place(board, 1, "pearl_lock")
	_place(board, 3, "small_lock")
	assert_eq(board._end_preview.text, "+6 driftwood · +2 pearls")
	assert_eq(board._slot_cards["pearl_lock"].preview_text, "+2 pearls")
	var finished: Array[bool] = [false]
	board.finished.connect(func() -> void: finished[0] = true)
	board._on_verb()
	assert_eq(board.room.state, DiceRoom.State.DONE)
	assert_eq(board.room.payout, {"driftwood": 6, "pearls": 2} as Dictionary[String, int])
	assert_true(board._results.visible)
	assert_string_starts_with(board._results_text.text, "You found 6 driftwood, 2 pearls.")
	board._continue.pressed.emit()
	assert_false(finished[0], "the result can't be skipped by a press meant for Open")
	board._results_shown_at -= RoomBoard.RESULT_GUARD_MS
	board._continue.pressed.emit()
	assert_true(finished[0])


func test_rest_caps_the_heal_before_showing_it() -> void:
	var board: RoomBoard = _board("rest", [5, 6, 1, 2], 26)
	_place(board, 0, "soak")
	_place(board, 1, "soak")
	assert_eq(board._end_preview.text, "Heal 4 (7 wasted, you're at 26/30)")
	assert_eq(board._slot_cards["soak"].preview_text, "Heal 4 (7 wasted)")
	assert_eq(board._verb.text, "Soak")
	assert_eq(board._hp_bar.gain, 4, "the heal shows on the HP bar")
	board._on_verb()
	assert_eq(board.room.hp, 30)


func test_a_held_die_previews_the_running_total_on_the_sum_lock() -> void:
	var board: RoomBoard = _board("rescue", [3, 3, 6, 5], 22, "pearl_diver")
	_place(board, 2, "cage_sum")
	assert_eq(board._slot_cards["cage_sum"].preview_text, "6 / 10")
	assert_eq(board._slot_cards["cage_sum"].preview_tone, "wait")
	board._on_die_pressed(3)
	assert_eq(board._slot_cards["cage_sum"].preview_text, "Opens", "6 + 5 would open it")


func test_rescue_shows_the_tide_and_keeps_open_locks_open() -> void:
	var board: RoomBoard = _board("rescue", [3, 3, 6, 5], 22, "pearl_diver")
	assert_eq(board._turns.text, "Turn 1 / 3")
	assert_eq(board._end_preview.text, "Opens no locks · Lose 2 · tide")
	_place(board, 0, "cage_pair")
	_place(board, 1, "cage_pair")
	assert_eq(board._end_preview.text, "Opens 1 lock · Lose 2 · tide")
	assert_eq(board._hp_bar.ghost, 2, "the tide's bite shows on the HP bar")
	board._on_verb()
	assert_eq(board._turns.text, "Turn 2 / 3")
	assert_true(board._slot_cards["cage_pair"].opened)
	assert_eq(board._slot_cards["cage_pair"].preview_text, "Open · its dice came back")
	for d: DiceRoom.Die in board.room.hand:
		assert_true(d.is_free(), "every die back in the hand")
	assert_string_contains(board._last_turn.text, "opened the pair lock")


func test_a_failed_rescue_is_kind() -> void:
	var board: RoomBoard = _board("rescue", [1, 2, 4, 6], 22, "pearl_diver")
	while board.room.state == DiceRoom.State.PLAYER_TURN:
		board._on_verb()
	assert_false(board.room.succeeded)
	assert_string_starts_with(board._results_text.text, "The pearl diver is still caged. You'll find them again.")


func test_the_board_only_moves_through_the_room() -> void:
	var board: RoomBoard = _board("treasure", [4, 4, 2, 6])
	_place(board, 0, "jackpot_lock")
	_place(board, 2, "pearl_lock")
	board._on_die_pressed(2)
	assert_eq(board.room.moves.size(), 3, "place, place, take back")
	var replay: DiceRoom = DiceRoom.create(data, "fresh", "treasure", RngStreams.new(7), NUDGE, 30)
	for i: int in 4:
		replay.hand[i].value = [4, 4, 2, 6][i]
	assert_true(replay.apply_moves(board.room.moves))
	assert_eq(replay.slot("jackpot_lock").dice, board.room.slot("jackpot_lock").dice)


func test_a_full_lock_reads_as_a_plan_not_an_error() -> void:
	var board: RoomBoard = _board("treasure", [4, 4, 2, 6])
	_place(board, 0, "pearl_lock")
	_place(board, 1, "pearl_lock")
	board._on_die_pressed(3)
	assert_eq(board._slot_cards["pearl_lock"].preview_text, "Full · +2 pearls")
	assert_eq(board._slot_cards["pearl_lock"].preview_tone, "ok")
	board._on_slot_pressed("pearl_lock")
	assert_eq(board._slot_cards["pearl_lock"].preview_tone, "error", "a refused drop is still red")


func test_the_last_rescue_turn_says_what_failing_means() -> void:
	var board: RoomBoard = _board("rescue", [1, 2, 4, 6], 22, "pearl_diver")
	board._on_verb()
	board._on_verb()
	assert_eq(board._end_preview.text, "Opens no locks · Lose 2 · tide · last turn: they stay caged")
