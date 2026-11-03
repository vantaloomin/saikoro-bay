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
	assert_eq(board._slot_cards["high_roller"].preview_text, "Needs 5 to 6.", "the refusal shows on the slot")
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
	assert_eq(board._slot_cards["guard"].preview_tone, "error")
	assert_eq(board._slot_cards["guard"].held_fit, -1, "a slot the die can't go in dims")
	assert_eq(board._slot_cards["high_roller"].held_fit, 1, "a slot it can go in lights up")
	board._on_die_pressed(1)
	board._on_die_pressed(2)
	assert_eq(board._slot_cards["pair_bet"].preview_text, "Waits for a 4 · 16 dmg")
	assert_eq(board._slot_cards["pair_bet"].preview_tone, "wait", "waiting is neutral, not an error")


func test_a_held_die_lifts_and_a_placed_die_shows_its_slot() -> void:
	board._on_die_pressed(1)
	assert_true(board._dice[1].selected)
	board._on_slot_pressed("high_roller")
	assert_eq(board._dice[1].placed_order, 3, "High Roller is slot 3 on the card")


func test_an_invalid_drop_explains_itself_on_the_slot() -> void:
	board._on_die_pressed(1)
	board._on_slot_pressed("guard")
	assert_true(fight.hand[1].is_free(), "the die snaps back")
	assert_eq(board._slot_cards["guard"].preview_text, "Needs 1 to 4.")
	assert_eq(board._slot_cards["guard"].preview_tone, "error")


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
	assert_eq(board.end_turn_summary(), "Deal 8 · Lose 4", "HP lost counts the bite as well as the hit")
	var t: Dictionary = board.turn_preview()
	assert_eq(t["bites"], 1)
	assert_eq(t["hit_taken"], 3)
	assert_eq(t["lost"], 4)
	assert_eq(board._player_bar.ghost, 4, "the HP bar ghosts the same 4")
	await board._on_end_turn()
	assert_eq(fight.enemy_hp, 34 - 8)
	assert_eq(fight.player_hp, 26, "3 through block and 1 bite")
	assert_eq(fight.turn, 2)
	assert_eq(board._player_hp.text, "HP 26 / 30")
	assert_string_contains(board._last_turn.text, "Last turn: you dealt 8")
	var free: int = -1
	for d: Fight.Die in fight.hand:
		if d.is_free() and not d.locked and free < 0:
			free = d.id
	board._on_die_pressed(free)
	board._on_slot_pressed("strike")
	assert_eq(board._last_turn.text, "", "the last-turn line clears on the next move")


func test_winning_shows_results() -> void:
	fight.enemy_hp = 8
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	await board._on_end_turn()
	assert_eq(fight.state, Fight.State.WON)
	assert_true(board._results.visible)
	assert_string_contains(board._results_text.text, "You beat the Snake-Eyes Eel")


func test_dragging_a_die_onto_a_slot_places_it() -> void:
	var view: DieView = board._dice[1]
	var payload: Variant = view.drag_payload()
	assert_eq(payload, {"die": 1})
	assert_eq(board._selected, 1, "dragging holds the die so slots preview it")
	var card: SlotCard = board._slot_cards["high_roller"]
	assert_true(card._can_drop_data(Vector2.ZERO, payload))
	card._drop_data(Vector2.ZERO, payload)
	assert_eq(fight.slot("high_roller").dice, [1] as Array[int])


func test_a_bad_drag_explains_itself_and_places_nothing() -> void:
	var payload: Variant = board._dice[0].drag_payload()
	board._slot_cards["high_roller"]._drop_data(Vector2.ZERO, payload)
	assert_true(fight.slot("high_roller").dice.is_empty())
	assert_eq(board._slot_cards["high_roller"].preview_text, "Needs 5 to 6.")


func test_a_placed_die_cannot_be_dragged() -> void:
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	assert_null(board._dice[1].drag_payload())


func test_nudge_shows_the_face_of_the_villager_who_gives_it() -> void:
	assert_eq(board._nudge_chip.villager_id, "pearl_diver")
	assert_eq(board._nudge_chip.initials(), "PD")
	assert_string_contains(board._nudge.text, "Pearl diver")


func test_the_board_uses_the_delve_type() -> void:
	var font: FontVariation = board.theme.default_font as FontVariation
	assert_not_null(font)
	assert_string_contains(font.base_font.resource_path, "BarlowCondensed")
	assert_eq(board._enemy_name.get_theme_font("font").resource_path, BoardStyle.TITLE_FONT_PATH)


func test_twist_banner_shows_on_first_meeting_until_the_first_turn() -> void:
	assert_false(board._banner.visible, "off unless the delve asks for it")
	var other: FightBoard = BOARD.instantiate() as FightBoard
	other.setup(Fight.create(data, "fresh", "snake_eyes_eel", RngStreams.new(3)), data)
	other.twist_banner = true
	add_child_autofree(other)
	assert_true(other._banner.visible)
	assert_string_contains((other._banner.get_child(0) as Label).text, "New twist · Snake eyes")
	await other._on_end_turn()
	assert_false(other._banner.visible)
