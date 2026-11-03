extends GutTest
## Koban's vault board drives a Vault only through its moves, shows both
## hands on the ladder, keeps the raise at none until you pick one, and
## shows the round score as pips (Mara's map review #8).

const NUDGE: Array[Dictionary] = [{"perk": "nudge", "source": "pearl_diver"}]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func before_each() -> void:
	Settings.reduce_motion = true


func after_each() -> void:
	Settings.reduce_motion = false


func _haul() -> Haul:
	var haul: Haul = Haul.new()
	haul.add_resource("driftwood", 20)
	haul.add_resource("pearls", 12)
	return haul


func _board(haul: Haul = _haul(), house: Array[int] = [4, 4, 6]) -> VaultBoard:
	var vault: Vault = Vault.create(data, "fresh", "koban", RngStreams.new(3), NUDGE, haul)
	vault.house_hand.assign(house)
	var board: VaultBoard = VaultBoard.new()
	board.setup(vault, data, "Café")
	add_child_autofree(board)
	return board


## Rolls and sets your dice.
func _roll(board: VaultBoard, values: Array[int]) -> void:
	board._on_verb()
	for i: int in values.size():
		board.vault.table.hand[i].value = values[i]
	board._refresh()


func _place(board: VaultBoard, die_id: int) -> void:
	board._on_die_pressed(die_id)
	board._on_slot_pressed()


func _row(rank: int) -> int:
	for i: int in VaultBoard.LADDER.size():
		if VaultBoard.LADDER[i][0] == rank:
			return i
	return -1


func _past_guard(board: VaultBoard) -> void:
	board._panel_shown_at -= VaultBoard.RESULT_GUARD_MS
	board._continue.pressed.emit()


func test_hands_read_in_words() -> void:
	assert_eq(VaultBoard.describe_hand([5, 5, 5] as Array[int]), "three 5s")
	assert_eq(VaultBoard.describe_hand([4, 3, 5] as Array[int]), "a run of 3-4-5")
	assert_eq(VaultBoard.describe_hand([4, 6, 4] as Array[int]), "a pair of 4s and a 6")
	assert_eq(VaultBoard.describe_hand([2, 6, 4] as Array[int]), "high die 6-4-2")
	assert_eq(VaultBoard.describe_hand([3, 3] as Array[int]), "a pair of 3s so far")
	assert_eq(VaultBoard.compare_text([5, 5, 2] as Array[int], [4, 4, 6] as Array[int]), "Same rank. Your pair of 5s beats her pair of 4s.")
	assert_eq(VaultBoard.compare_text([4, 4, 2] as Array[int], [4, 4, 6] as Array[int]), "Same pair. Her odd die 6 beats your 2.")
	assert_eq(VaultBoard.compare_text([3, 3, 3] as Array[int], [5, 5, 5] as Array[int]), "Same rank. Her three 5s beat your three 3s.")
	assert_eq(VaultBoard.compare_text([4, 5, 6] as Array[int], [1, 2, 3] as Array[int]), "Same rank. Your run of 4-5-6 beats her run of 1-2-3.")
	assert_eq(VaultBoard.compare_text([6, 2, 4] as Array[int], [5, 3, 1] as Array[int]), "Same rank. Your high die 6 beats her high die 5.")
	assert_eq(VaultBoard.compare_text([6, 3, 1] as Array[int], [6, 4, 1] as Array[int]), "Same high die. Her next die 4 beats your 3.")
	assert_eq(VaultBoard.compare_text([6, 4, 2] as Array[int], [6, 4, 1] as Array[int]), "Same top dice. Your total of 12 beats her 11.")
	assert_eq(VaultBoard.compare_text([2, 3, 4] as Array[int], [4, 4, 6] as Array[int]), "Your run of 2-3-4 beats her pair of 4s and a 6.")
	assert_eq(VaultBoard.compare_text([6, 6, 6] as Array[int], [4, 4, 6] as Array[int]), "Your three 6s beat her pair of 4s and a 6.")
	assert_eq(VaultBoard.compare_text([6, 4, 2] as Array[int], [4, 4, 6] as Array[int]), "Her pair of 4s and a 6 beats your high die 6-4-2.")
	assert_eq(VaultBoard.compare_text([4, 4, 6] as Array[int], [6, 4, 4] as Array[int]), "Same hand. A full tie goes to Koban.")
	assert_eq(VaultBoard.compare_text([6, 6] as Array[int], [3, 4, 6] as Array[int]), "A hand needs 3 dice. A short hand loses.")


func test_the_raise_starts_at_none_and_previews_both_ways() -> void:
	var board: VaultBoard = _board()
	assert_eq(board._preview.text, "No raise")
	assert_eq(board._verb.text, "Roll")
	for id: String in board._raise_buttons:
		assert_false(board._raise_buttons[id].button_pressed, "no raise is pre-selected")
	assert_eq(board._raise_buttons["pearls"].text, "Raise 3 pearls")
	board._on_raise_toggled("pearls")
	assert_eq(board._preview.text, "Raise 3 pearls: win +3 · lose −3")
	assert_eq(board.vault.haul.resource("pearls"), 12, "picking a raise stakes nothing yet")
	board._on_raise_toggled("pearls")
	assert_eq(board._preview.text, "No raise", "pressing it again takes it back")
	board._on_raise_toggled("pearls")
	board._on_verb()
	assert_eq(board.vault.stake, {"pearls": 3} as Dictionary[String, int])
	assert_eq(board.vault.haul.resource("pearls"), 9)
	assert_eq(board.vault.state, Vault.State.PLAYER_TURN)
	assert_eq(board._verb.text, "Play hand")


func test_the_ladder_marks_both_hands_live() -> void:
	var board: VaultBoard = _board()
	assert_eq(board._ladder_koban[_row(Vault.PAIR)].text, "KOBAN")
	for label: Label in board._ladder_you:
		assert_eq(label.text, "", "your hand isn't on the ladder before the roll")
	_roll(board, [3, 3, 4, 2])
	_place(board, 0)
	_place(board, 1)
	assert_eq(board._ladder_you[_row(Vault.PAIR)].text, "YOU SO FAR")
	board._take_back(1)
	_place(board, 2)
	_place(board, 3)
	assert_eq(board._ladder_you[_row(Vault.RUN)].text, "YOU")
	assert_eq(board._ladder_dice[_row(Vault.RUN)].text, "4 3 2", "a marked row shows the real dice")
	assert_eq(board._ladder_dice[_row(Vault.PAIR)].text, "6 4 4")
	assert_eq(board._ladder_dice[_row(Vault.HIGH_DIE)].text, "6 4 2", "unmarked rows keep the example")
	assert_true(board._ladder_footer.visible)
	assert_eq(board._card.preview_text, "A run of 2-3-4")
	assert_eq(board._preview.text, "Beats Koban")
	assert_eq(board._detail.text, "Your run of 2-3-4 beats her pair of 4s and a 6.")


func test_a_round_ends_on_a_panel_that_shows_both_hands() -> void:
	var board: VaultBoard = _board()
	board._on_raise_toggled("pearls")
	_roll(board, [6, 6, 6, 1])
	for i: int in 3:
		_place(board, i)
	assert_eq(board._preview.text, "Beats Koban · +6 pearls back")
	board._on_verb()
	assert_true(board._panel.visible)
	assert_string_starts_with(board._panel_text.text, "You take round 1.\nYour three 6s beat her pair of 4s and a 6.")
	assert_string_contains(board._panel_text.text, "+6 pearls back.")
	assert_eq(board._house_dice.values, [4, 4, 6] as Array[int], "the panel keeps the round's hands, not Koban's next roll")
	assert_eq(board._pips.results, [true] as Array[bool])
	assert_eq(board._continue.text, "Next round")
	board._continue.pressed.emit()
	assert_true(board._panel.visible, "a press meant for Play hand can't skip the result")
	_past_guard(board)
	assert_false(board._panel.visible)
	assert_eq(board.vault.round_number, 2)
	assert_eq(board._verb.text, "Roll")
	assert_eq(board._preview.text, "No raise", "each round's raise starts at none again")


func test_winning_twice_takes_the_vault() -> void:
	var board: VaultBoard = _board()
	var finished: Array[bool] = [false]
	board.finished.connect(func() -> void: finished[0] = true)
	for r: int in 2:
		board.vault.house_hand.assign([1, 2, 4] as Array[int])
		_roll(board, [5, 5, 5, 1])
		for i: int in 3:
			_place(board, i)
		if r == 1:
			assert_eq(board._preview.text, "Beats Koban · takes the vault")
		board._on_verb()
		_past_guard(board)
	assert_eq(board.vault.state, Vault.State.WON)
	assert_string_contains(board._panel_text.text, "You win the Café. Your haul: 20 driftwood, 12 pearls.")
	assert_true(finished[0])


func test_a_short_hand_loses_and_says_so() -> void:
	var board: VaultBoard = _board()
	_roll(board, [6, 6, 1, 2])
	_place(board, 0)
	_place(board, 1)
	assert_eq(board._preview.text, "Loses to Koban")
	assert_eq(board._detail.text, "A hand needs 3 dice. A short hand loses.")
	assert_eq(board._card.preview_text, "Pair of 6s · needs 1 more")


func test_the_board_moves_replay_on_a_fresh_vault() -> void:
	var haul: Haul = _haul()
	var board: VaultBoard = _board(haul)
	board._on_raise_toggled("driftwood")
	board._on_verb()
	board._on_reroll()
	board._on_die_pressed(0)
	board._on_reroll()
	for die_id: int in [1, 2, 3]:
		_place(board, die_id)
	board._on_verb()
	var again: Vault = Vault.create(data, "fresh", "koban", RngStreams.new(3), NUDGE, _haul())
	again.house_hand.assign([4, 4, 6] as Array[int])
	assert_true(again.apply_moves(board.vault.moves))
	assert_eq(again.events.slice(1), board.vault.events.slice(1), "the same moves make the same round")
	assert_eq(again.haul.to_dict(), board.vault.haul.to_dict())


func test_a_shared_rank_shows_the_tie_rule_on_its_row() -> void:
	var board: VaultBoard = _board()
	_roll(board, [5, 5, 3, 1])
	for i: int in 3:
		_place(board, i)
	var pair: int = _row(Vault.PAIR)
	assert_eq(board._ladder_dice[pair].text, "her 6 4 4 · your 5 5 3")
	assert_true(board._ladder_tie[pair].visible)
	assert_eq(board._ladder_tie[pair].text, "Same rank · higher hand wins · ties go to Koban")
	assert_false(board._ladder_footer.visible, "the rule moves onto the row")


func test_losing_the_vault_names_the_barrel_and_what_you_keep() -> void:
	var board: VaultBoard = _board()
	for r: int in 2:
		board.vault.house_hand.assign([6, 6, 6] as Array[int])
		_roll(board, [1, 2, 4, 1])
		for i: int in 3:
			_place(board, i)
		board._on_verb()
		if r == 0:
			_past_guard(board)
	assert_eq(board.vault.state, Vault.State.LOST)
	assert_string_contains(board._panel_text.text, "Koban wins. You wash up in the barrel and keep half: 10 driftwood, 6 pearls.")
	assert_eq(board._continue.text, "Continue")


func test_a_raise_that_cant_be_made_never_rolls() -> void:
	var haul: Haul = _haul()
	var board: VaultBoard = _board(haul)
	board._on_raise_toggled("pearls")
	haul.take_resource("pearls", 12)
	board._on_verb()
	assert_eq(board.vault.state, Vault.State.WAGER, "no roll without the promised stake")
	assert_eq(board._raise_pick, "")
	assert_string_starts_with(board._message.text, "That raise can't be made now.")


func test_finished_fires_once() -> void:
	var board: VaultBoard = _board()
	var count: Array[int] = [0]
	board.finished.connect(func() -> void: count[0] += 1)
	for r: int in 2:
		board.vault.house_hand.assign([1, 2, 4] as Array[int])
		_roll(board, [5, 5, 5, 1])
		for i: int in 3:
			_place(board, i)
		board._on_verb()
		_past_guard(board)
	board._continue.pressed.emit()
	assert_eq(count[0], 1)


func test_the_vault_says_when_the_spare_die_sits_out() -> void:
	var kit: Kit = Kit.fresh(data, [{"perk": "spare_die", "source": "boat_shed"}] as Array[Dictionary])
	var vault: Vault = Vault.create(data, "fresh", "koban", RngStreams.new(3), kit.perks, _haul(), kit.die_specs())
	var board: VaultBoard = VaultBoard.new()
	board.setup(vault, data, "Café", kit)
	add_child_autofree(board)
	assert_eq(board.sitting_out, "Your four-sided die from the Boat shed sits out: Koban's table takes 4 dice.")
	assert_eq(VaultBoard.sitting_out_line(data, Kit.fresh(data)), "", "nothing to say for the plain kit")
