extends GutTest
## The greybox dice board drives the fight only through its moves and shows
## what the fight says.

const BOARD: PackedScene = preload("res://game/delve/board/fight_board.tscn")

var data: GameData
var board: FightBoard
var fight: Fight


func before_each() -> void:
	data = GameData.load_dir()
	fight = Fight.create(data, "fresh", "snake_eyes_eel", RngStreams.new(11), [{"perk": "nudge", "source": "pearl_diver"}])
	for i: int in 4:
		fight.hand[i].value = [1, 5, 4, 4][i]
	board = BOARD.instantiate() as FightBoard
	board.setup(fight, data)
	add_child_autofree(board)
	Settings.reduce_motion = true


func after_each() -> void:
	Settings.reduce_motion = false


func test_click_die_then_slot_places() -> void:
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	assert_eq(fight.slot("high_roller").dice, [1] as Array[int])
	assert_eq(fight.moves.size(), 1)


func test_invalid_drop_explains_and_changes_nothing() -> void:
	board._on_die_pressed(0)
	board._on_slot_pressed("high_roller")
	assert_true(fight.slot("high_roller").dice.is_empty())
	assert_eq(board._message.text, "Needs 5 to 6.")
	assert_true(fight.moves.is_empty())


func test_pressing_a_placed_die_or_right_clicking_its_slot_takes_it_back() -> void:
	board._on_die_pressed(2)
	board._on_slot_pressed("pair_bet")
	board._on_die_pressed(3)
	board._on_slot_pressed("pair_bet")
	board._on_slot_secondary("pair_bet")
	assert_eq(fight.slot("pair_bet").dice, [2] as Array[int])
	board._on_die_pressed(2)
	assert_true(fight.slot("pair_bet").dice.is_empty())


func test_previews_show_on_every_slot_for_the_held_die() -> void:
	board._on_die_pressed(1)
	assert_eq(board._slot_cards["high_roller"].preview_text, "8 damage")
	assert_eq(board._slot_cards["guard"].preview_text, "Needs 1 to 4.")
	assert_false(board._slot_cards["guard"].preview_ok)
	board._on_die_pressed(1)
	board._on_die_pressed(2)
	assert_eq(board._slot_cards["pair_bet"].preview_text, "16 damage with another 4")


func test_snake_eyes_marks_unplaced_ones() -> void:
	assert_true(board._dice[0].bite_marker)
	assert_false(board._dice[1].bite_marker)


func test_reroll_takes_two_steps() -> void:
	board._on_reroll()
	assert_eq(fight.rerolls_left, 1, "the first press only picks the mode")
	board._on_die_pressed(0)
	assert_eq(fight.rerolls_left, 1, "picking the discard doesn't fire")
	assert_string_contains(board._reroll.text, "Confirm: discard 1, reroll 3")
	board._on_reroll()
	assert_eq(fight.rerolls_left, 0)
	assert_true(fight.hand[0].discarded)


func test_cancel_leaves_reroll_mode() -> void:
	board._on_reroll()
	board._cancel()
	assert_false(board._reroll_mode)
	assert_eq(fight.rerolls_left, 1)


func test_nudge_uses_the_selected_die_and_shows_a_badge() -> void:
	board._on_die_pressed(2)
	board._on_nudge()
	assert_eq(fight.hand[2].value, 5)
	assert_true(board._badge.visible)
	assert_string_contains(board._badge.text, "+1")


func test_end_turn_preview_matches_the_turn() -> void:
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	assert_eq(board.end_turn_summary(), "You deal 8 · Block 3 · Snake eyes 1 · Hits 6, you take 3")
	await board._on_end_turn()
	assert_eq(fight.enemy_hp, 34 - 8)
	assert_eq(fight.player_hp, 26, "3 through block and 1 bite")
	assert_eq(fight.turn, 2)
	assert_eq(board._player_hp.text, "HP 26 / 30")


func test_winning_shows_results() -> void:
	fight.enemy_hp = 8
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	await board._on_end_turn()
	assert_eq(fight.state, Fight.State.WON)
	assert_true(board._results.visible)
	assert_string_contains(board._results_text.text, "You beat the Snake-Eyes Eel")
