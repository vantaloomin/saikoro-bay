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


func test_moves_make_their_sounds() -> void:
	board._on_die_pressed(0)
	board._on_slot_pressed("high_roller")
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	board._on_die_pressed(1)
	board._on_reroll()
	board._on_die_pressed(0)
	board._on_reroll()
	assert_eq(board._sounds.played, ["invalid", "place", "take_back", "roll", "land"] as Array[String])


func test_every_cue_is_a_short_sound() -> void:
	for cue: String in BoardSounds.CUES:
		var wav: AudioStreamWAV = BoardSounds.stream(cue)
		assert_not_null(wav, cue)
		assert_between(wav.get_length(), 0.03, 0.6, cue)


func test_spines_show_their_cost_on_the_block_line() -> void:
	var puffer: Fight = Fight.create(data, "fresh", "pufferfish_bouncer", RngStreams.new(4))
	var values: Array[int] = [1, 1, 4, 3]
	for i: int in 4:
		puffer.hand[i].value = values[i]
	var other: FightBoard = BOARD.instantiate() as FightBoard
	other.setup(puffer, data)
	add_child_autofree(other)
	other._on_die_pressed(2)
	other._on_slot_pressed("guard")
	assert_string_contains(other._player_block.text, "spines stop 3")
	assert_string_contains(other.turn_preview()["detail"], "spines stop 3 block")


func test_rising_stakes_mark_the_raise_on_the_intent() -> void:
	var crab: Fight = Fight.create(data, "fresh", "pot_raiser_crab", RngStreams.new(4))
	crab.intent_index = 2
	var other: FightBoard = BOARD.instantiate() as FightBoard
	other.setup(crab, data)
	add_child_autofree(other)
	assert_eq(other._intent.current["raised"], 2)
	assert_eq(other._intent.next["raised"], 3)


func test_the_buttons_stay_put_as_the_preview_comes_and_goes() -> void:
	await wait_process_frames(2)
	var reroll_y: float = board._reroll.global_position.y
	var end_y: float = board._end_turn.global_position.y
	board._set_detail(true)
	board._on_die_pressed(1)
	board._on_slot_pressed("high_roller")
	await wait_process_frames(2)
	assert_eq(board._reroll.global_position.y, reroll_y, "showing the breakdown leaves Reroll where it was")
	assert_eq(board._end_turn.global_position.y, end_y, "and End turn")
	board._end_preview.text = ""
	board._end_detail.text = "a much longer breakdown line that wraps onto a second line and then a third one, " \
		+ "on and on past what the column can hold"
	await wait_process_frames(2)
	assert_eq(board._end_turn.global_position.y, end_y, "empty or long text never moves the buttons")
	board._set_detail(false)
	await wait_process_frames(2)
	assert_eq(board._end_turn.global_position.y, end_y, "hiding it doesn't either")


func test_slow_pour_rerolls_in_one_press_and_shows_what_it_costs() -> void:
	var kit: Kit = Kit.fresh(data, [{"perk": "slow_pour", "source": "tea_stall"}] as Array[Dictionary])
	var poured: Fight = Fight.create(data, "fresh", "snake_eyes_eel", RngStreams.new(11), kit.perks, -1, kit.die_specs())
	var pour_board: FightBoard = BOARD.instantiate() as FightBoard
	pour_board.setup(poured, data)
	add_child_autofree(pour_board)
	assert_eq(pour_board._reroll.text, "Slow pour (2 left)")
	pour_board._on_reroll()
	assert_eq(poured.table.pours_left, 1, "no discard to pick")
	assert_eq(poured.moves.back(), {"move": "pour"})
	assert_eq(pour_board._badge.text, "Tea stall · Slow pour · used 1 of 2")
	assert_eq(pour_board._reroll.text, "Slow pour (1 left)")
	pour_board._on_reroll()
	assert_true(pour_board._reroll.disabled)
	pour_board._on_reroll()
	assert_eq(poured.moves.size(), 2, "a third press does nothing")


func test_chum_names_itself_on_the_attack_and_kit_dice_are_marked() -> void:
	var kit: Kit = Kit.fresh(data, [
		{"perk": "chum", "source": "bait_shop"},
		{"perk": "weighted_die", "source": "net_shed"},
	] as Array[Dictionary])
	var chummed: Fight = Fight.create(data, "fresh", "snake_eyes_eel", RngStreams.new(11), kit.perks, -1, kit.die_specs())
	var chum_board: FightBoard = BOARD.instantiate() as FightBoard
	chum_board.setup(chummed, data)
	add_child_autofree(chum_board)
	assert_eq(chum_board._intent.chum_source, "Bait shop", "the extra damage has a cause")
	assert_eq(chum_board._intent.current.get("chum", 0), 1)
	assert_true(chum_board._dice[0].kit_mark, "the weighted die is marked on the table")
	assert_eq(chum_board._dice[0].tooltip_text, "Weighted die · Net shed · no 1s or 6s")
	assert_false(chum_board._dice[1].kit_mark, "a plain die isn't")


func test_stacked_raises_fold_into_one_arrow() -> void:
	var view: FightBoard.IntentView = FightBoard.IntentView.new()
	view.chum_source = "Bait shop"
	assert_eq(view.raise_label({"attack": 9, "chum": 1}), "+1 · Bait shop", "one source stays inline")
	assert_eq(view.breakdown({"attack": 9, "chum": 1}), "")
	assert_eq(view.raise_label({"attack": 8, "raised": 2}), "+2")
	assert_eq(view.raise_label({"attack": 11, "raised": 2, "chum": 1}), "+3", "two fold into one")
	assert_eq(view.breakdown({"attack": 11, "raised": 2, "chum": 1}), "Rising stakes +2 · Bait shop +1")
	assert_eq(view.raise_label({"attack": 6}), "")
	view.free()


func test_a_kit_die_shows_its_range_and_names_itself_when_focused() -> void:
	var kit: Kit = Kit.fresh(data, [{"perk": "weighted_die", "source": "net_shed"}] as Array[Dictionary])
	var weighted: Fight = Fight.create(data, "fresh", "snake_eyes_eel", RngStreams.new(11), kit.perks, -1, kit.die_specs())
	var kit_board: FightBoard = BOARD.instantiate() as FightBoard
	kit_board.setup(weighted, data)
	add_child_autofree(kit_board)
	var die: DieView = kit_board._dice[0]
	assert_eq(die.kit_range, "2–5")
	assert_eq(die.kit_note, "Weighted die · Net shed · no 1s or 6s")
	assert_eq(kit_board._dice[1].kit_range, "", "a standard die gets no label")
	die.grab_focus()
	assert_eq(kit_board._end_detail.text, "Weighted die · Net shed · no 1s or 6s", "a pad sees the note too")
	assert_eq(kit_board._end_detail.modulate.a, 1.0)
	kit_board._dice[1].grab_focus()
	assert_ne(kit_board._end_detail.text, die.kit_note, "back to the turn's detail")
	assert_eq(DieView.note_for(data, "d4"), "Four-sided die · Boat shed · added")
