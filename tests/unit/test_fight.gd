extends GutTest
## Fight: the dice fight rules (specs/dice-fight-rules.md), one rule per test.
## Most tests set die values by hand so each rule is checked on a known hand.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _fight(enemy: String = "card_shark", perks: Array[Dictionary] = [], seed_value: int = 7) -> Fight:
	var fight: Fight = Fight.create(data, "fresh", enemy, RngStreams.new(seed_value), perks)
	assert_not_null(fight)
	return fight


## Sets the hand to `values` (in die-id order) and reapplies the House lock.
func _set_hand(fight: Fight, values: Array[int]) -> void:
	for i: int in values.size():
		fight.hand[i].value = values[i]
	fight._apply_house_lock()
	fight.events.clear()


func _events_of(fight: Fight, type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in fight.events:
		if event["type"] == type:
			found.append(event)
	return found


# --- Setup --------------------------------------------------------------------

func test_unknown_ids_make_no_fight() -> void:
	var rng: RngStreams = RngStreams.new(1)
	assert_null(Fight.create(data, "nope", "card_shark", rng))
	assert_null(Fight.create(data, "fresh", "nope", rng))


func test_new_fight_matches_the_kit() -> void:
	var fight: Fight = _fight()
	assert_eq(fight.state, Fight.State.PLAYER_TURN)
	assert_eq(fight.turn, 1)
	assert_eq(fight.player_hp, 30)
	assert_eq(fight.enemy_hp, 18)
	assert_eq(fight.hand.size(), 4)
	for i: int in 4:
		assert_eq(fight.hand[i].id, i, "dice keep stable ids")
		assert_between(fight.hand[i].value, 1, 6)
	assert_eq(fight.slots.size(), 4)
	assert_eq(fight.rerolls_left, 1)
	assert_eq(fight.current_intent(), {"attack": 6})
	assert_eq(fight.next_intent(), {"attack": 4, "guard": 4})


func test_hp_carries_in_and_is_capped() -> void:
	var rng: RngStreams = RngStreams.new(1)
	assert_eq(Fight.create(data, "fresh", "card_shark", rng, [], 12).player_hp, 12)
	assert_eq(Fight.create(data, "fresh", "card_shark", rng, [], 99).player_hp, 30)


func test_unknown_perks_are_ignored() -> void:
	var fight: Fight = _fight("card_shark", [{"perk": "ghost", "source": "x"}])
	assert_false(fight.has_perk("ghost"))


# --- Placing ------------------------------------------------------------------

func test_range_slots_check_the_die() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [5, 4, 1, 6])
	assert_eq(fight.place_refusal(0, "guard"), "Needs 1 to 4.")
	assert_false(fight.place(0, "guard"))
	assert_eq(fight.place_refusal(1, "high_roller"), "Needs 5 to 6.")
	assert_true(fight.place(1, "guard"))
	assert_true(fight.place(0, "high_roller"))
	assert_eq(fight.place_refusal(3, "high_roller"), "This slot is full.")


func test_a_die_goes_in_one_slot_at_a_time() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 3, 3, 3])
	assert_true(fight.place(0, "strike"))
	assert_eq(fight.place_refusal(0, "guard"), "That die is already placed.")
	assert_eq(fight.place_refusal(9, "guard"), "No such die or slot.")
	assert_eq(fight.place_refusal(1, "nope"), "No such die or slot.")


func test_placing_changes_nothing_until_end_turn() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [6, 3, 3, 3])
	fight.place(0, "strike")
	assert_eq(fight.enemy_hp, 18)
	assert_eq(fight.player_block, 0)


func test_pair_bet_fills_socket_by_socket() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [4, 5, 4, 2])
	assert_true(fight.place(0, "pair_bet"))
	assert_false(fight.slot("pair_bet").is_complete())
	assert_eq(fight.place_refusal(1, "pair_bet"), "Needs a 4 to match.")
	assert_true(fight.place(2, "pair_bet"))
	assert_true(fight.slot("pair_bet").is_complete())


func test_pair_bet_take_back_rechecks_against_the_die_left() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [4, 4, 2, 2])
	fight.place(0, "pair_bet")
	fight.place(1, "pair_bet")
	assert_true(fight.take_back(0))
	assert_eq(fight.slot("pair_bet").dice, [1] as Array[int], "the second die stays in place")
	assert_eq(fight.place_refusal(2, "pair_bet"), "Needs a 4 to match.")
	assert_true(fight.place(0, "pair_bet"))


func test_take_back_is_free_and_repeatable() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 3, 3, 3])
	assert_false(fight.take_back(0), "can't take back a die in the hand")
	for i: int in 3:
		assert_true(fight.place(0, "strike"))
		assert_true(fight.take_back(0))
	assert_true(fight.hand[0].is_free())
	assert_true(fight.slot("strike").dice.is_empty())


# --- Reroll -------------------------------------------------------------------

func test_reroll_spends_the_discard_and_rerolls_the_free_dice_in_id_order() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(1, "strike")
	var expected_rng: RngStreams = RngStreams.new()
	expected_rng.load_dict(fight._rng.to_dict())
	var expected: Array[int] = []
	for i: int in 2:
		expected.append(fight.hand[0].faces[expected_rng.index(RngStreams.Stream.ROLLS, 6)])
	assert_true(fight.reroll(0))
	assert_true(fight.hand[0].discarded)
	assert_eq(fight.hand[0].value, 3, "the discard isn't rerolled")
	assert_eq(fight.hand[1].value, 3, "placed dice never change")
	assert_eq([fight.hand[2].value, fight.hand[3].value] as Array[int], expected)
	assert_eq(fight.rerolls_left, 0)
	assert_eq(fight.place_refusal(0, "guard"), "That die was spent on a reroll.")
	assert_eq(fight.reroll_refusal(2), "No rerolls left this turn.")


func test_reroll_needs_something_to_reroll() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(0, "strike")
	fight.place(1, "guard")
	fight.place(2, "pair_bet")
	assert_eq(fight.reroll_refusal(3), "Nothing left to reroll.")
	assert_eq(fight.reroll_refusal(0), "Pick an unplaced die to discard.")


func test_reroll_resets_each_turn() -> void:
	var fight: Fight = _fight()
	fight.reroll(0)
	fight.end_turn()
	assert_eq(fight.rerolls_left, 1)
	assert_false(fight.hand[0].discarded)


# --- House lock ---------------------------------------------------------------

func test_house_lock_takes_the_highest_die_lowest_id_on_ties() -> void:
	var fight: Fight = _fight("hermit_croupier")
	_set_hand(fight, [2, 6, 6, 1])
	assert_true(fight.hand[1].locked)
	assert_false(fight.hand[2].locked)
	assert_eq(fight.place_refusal(1, "strike"), "House lock: this die is locked this turn.")
	assert_eq(fight.reroll_refusal(1), "A locked die can't pay for a reroll.")


func test_house_lock_moves_after_a_reroll() -> void:
	var fight: Fight = _fight("hermit_croupier")
	_set_hand(fight, [2, 6, 3, 1])
	assert_true(fight.reroll(3))
	var highest: int = -1
	var locked: Array[int] = []
	for d: Fight.Die in fight.hand:
		if d.is_free() and (highest < 0 or d.value > fight.hand[highest].value):
			highest = d.id
		if d.locked:
			locked.append(d.id)
	assert_eq(locked, [highest] as Array[int], "lock recomputed over the free dice")


func test_house_lock_stays_put_after_a_nudge() -> void:
	var fight: Fight = _fight("hermit_croupier", [{"perk": "nudge", "source": "pearl_diver"}])
	_set_hand(fight, [5, 6, 3, 1])
	assert_true(fight.hand[1].locked)
	assert_true(fight.nudge(0))
	assert_eq(fight.hand[0].value, 6)
	assert_true(fight.hand[1].locked)
	assert_false(fight.hand[0].locked)


# --- Nudge --------------------------------------------------------------------

func test_nudge_needs_the_perk() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 3, 3, 3])
	assert_false(fight.nudge(0))


func test_nudge_raises_one_free_die_once_per_turn() -> void:
	var fight: Fight = _fight("card_shark", [{"perk": "nudge", "source": "pearl_diver"}])
	_set_hand(fight, [6, 3, 3, 3])
	assert_false(fight.nudge(0), "not on the top face")
	fight.place(1, "strike")
	assert_false(fight.nudge(1), "not on a placed die")
	assert_true(fight.nudge(2))
	assert_eq(fight.hand[2].value, 4)
	assert_false(fight.nudge(3), "once per turn")
	var perk_events: Array[Dictionary] = _events_of(fight, "perk")
	assert_eq(perk_events.size(), 1)
	assert_eq(perk_events[0]["source"], "pearl_diver", "badge names the villager")
	fight.end_turn()
	assert_eq(fight.nudges_left, 1)


# --- End turn pipeline --------------------------------------------------------

func test_slots_hit_and_block_then_the_enemy_attacks() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 4, 5, 2])
	fight.place(0, "strike")
	fight.place(1, "guard")
	fight.place(2, "high_roller")
	fight.place(3, "pair_bet")
	assert_true(fight.end_turn())
	assert_eq(fight.enemy_hp, 18 - 3 - 8)
	# Guard 4+1 = 5 block, plus 1 for the half-filled Pair Bet die; attack 6.
	assert_eq(fight.player_hp, 30)
	assert_eq(fight.turn, 2)


func test_unused_dice_give_block() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(0, "strike")
	fight.end_turn()
	# 3 unused dice = 3 block against attack 6.
	assert_eq(fight.player_hp, 27)


func test_locked_dice_give_no_unused_block() -> void:
	var fight: Fight = _fight("hermit_croupier")
	_set_hand(fight, [1, 6, 1, 1])
	fight.place(0, "strike")
	fight.place(2, "guard")
	fight.end_turn()
	# Die 3 gives 1, the locked 6 gives 0, guard gives 2: 3 block against 5.
	assert_eq(fight.player_hp, 28)


func test_every_slot_fires_even_past_zero() -> void:
	var fight: Fight = _fight()
	fight.enemy_hp = 2
	_set_hand(fight, [3, 5, 2, 2])
	fight.place(0, "strike")
	fight.place(1, "high_roller")
	fight.place(2, "pair_bet")
	fight.place(3, "pair_bet")
	fight.end_turn()
	assert_eq(_events_of(fight, "damage").size(), 3)
	assert_eq(fight.state, Fight.State.WON)
	assert_eq(fight.enemy_hp, 0)


func test_a_won_fight_takes_no_enemy_attack() -> void:
	var fight: Fight = _fight()
	fight.enemy_hp = 3
	_set_hand(fight, [3, 1, 1, 1])
	fight.place(0, "strike")
	fight.end_turn()
	assert_eq(fight.player_hp, 30)
	assert_eq(fight.state, Fight.State.WON)
	assert_false(fight.end_turn(), "the fight is over")
	assert_false(fight.place(1, "guard"))


func test_winning_turn_cant_lose_to_snake_eyes() -> void:
	var fight: Fight = _fight("snake_eyes_eel")
	fight.player_hp = 1
	fight.enemy_hp = 6
	_set_hand(fight, [6, 1, 1, 1])
	fight.place(0, "strike")
	fight.end_turn()
	assert_eq(fight.state, Fight.State.WON)
	assert_eq(fight.player_hp, 1)


func test_snake_eyes_bites_through_block() -> void:
	var fight: Fight = _fight("snake_eyes_eel")
	_set_hand(fight, [1, 1, 4, 3])
	fight.place(2, "guard")
	fight.place(3, "strike")
	fight.end_turn()
	# Two unused 1s: 2 bites ignoring block. Block 5 (guard) + 2 (unused) = 7 vs attack 4.
	assert_eq(fight.player_hp, 28)
	var bites: int = 0
	for event: Dictionary in _events_of(fight, "damage"):
		if event["source"] == "twist:snake_eyes":
			bites += 1
	assert_eq(bites, 2)


func test_enemy_guard_protects_during_the_turn_its_shown() -> void:
	var fight: Fight = _fight()
	fight.end_turn()
	assert_eq(fight.current_intent(), {"attack": 4, "guard": 4})
	assert_eq(fight.enemy_block, 4, "guard is up when the intent is shown")
	var hp: int = fight.enemy_hp
	_set_hand(fight, [6, 1, 1, 1])
	fight.place(0, "strike")
	fight.end_turn()
	assert_eq(fight.enemy_hp, hp - 2)
	assert_eq(fight.enemy_block, 0, "turn 3's intent has no guard")


func test_intents_cycle() -> void:
	var fight: Fight = _fight()
	fight.player_hp = 999
	fight.player_max_hp = 999
	var seen: Array[Dictionary] = []
	for i: int in 4:
		seen.append(fight.current_intent())
		fight.end_turn()
	assert_eq(seen, [{"attack": 6}, {"attack": 4, "guard": 4}, {"attack": 6}, {"attack": 4, "guard": 4}] as Array[Dictionary])


func test_losing_ends_the_fight() -> void:
	var fight: Fight = _fight()
	fight.player_hp = 2
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(0, "strike")
	fight.place(1, "high_roller") # refused: 3 isn't 5-6
	fight.place(1, "pair_bet")
	fight.place(2, "pair_bet")
	fight.place(3, "guard")
	fight.end_turn()
	# Guard 4 block vs attack 6: 2 through.
	assert_eq(fight.player_hp, 0)
	assert_eq(fight.state, Fight.State.LOST)
	assert_false(fight.take_back(0))


# --- Perks --------------------------------------------------------------------

func test_brace_gives_block_at_turn_start() -> void:
	var fight: Fight = _fight("card_shark", [{"perk": "brace", "source": "shipwright"}])
	assert_eq(fight.player_block, 2)
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(0, "strike")
	fight.place(1, "guard")
	fight.place(2, "pair_bet")
	fight.place(3, "pair_bet")
	fight.end_turn()
	# 2 brace + 4 guard = 6 vs attack 6.
	assert_eq(fight.player_hp, 30)
	assert_eq(fight.player_block, 2, "block resets, then Brace adds 2")


func test_mend_heals_on_win_up_to_max() -> void:
	var fight: Fight = _fight("card_shark", [{"perk": "mend", "source": "onsen_keeper"}])
	fight.player_hp = 29
	fight.enemy_hp = 1
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(0, "strike")
	fight.end_turn()
	assert_eq(fight.player_hp, 30)
	var perk_events: Array[Dictionary] = _events_of(fight, "perk")
	assert_eq(perk_events.size(), 1)
	assert_eq(perk_events[0]["source"], "onsen_keeper")
	assert_eq(perk_events[0]["amount"], 1, "badge shows what was healed")


# --- Previews -----------------------------------------------------------------

func test_slot_preview_matches_what_happens() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [3, 5, 2, 2])
	assert_eq(fight.preview(0, "strike"), {"ok": true, "reason": "", "effect": "damage", "amount": 3, "complete": true})
	assert_eq(fight.preview(1, "high_roller")["amount"], 8)
	assert_eq(fight.preview(0, "guard")["amount"], 4)
	assert_eq(fight.preview(1, "guard")["reason"], "Needs 1 to 4.")
	var half: Dictionary = fight.preview(2, "pair_bet")
	assert_false(half["complete"])
	assert_eq(half["amount"], 8, "assumes the match arrives")
	fight.place(2, "pair_bet")
	assert_eq(fight.preview(3, "pair_bet")["amount"], 8)
	assert_true(fight.preview(3, "pair_bet")["complete"])
	assert_true(fight.slot("strike").dice.is_empty(), "previews don't place")


func test_end_turn_preview_is_exact_and_moves_nothing() -> void:
	for seed_value: int in 20:
		var fight: Fight = _fight("snake_eyes_eel", [{"perk": "brace", "source": "shipwright"}], seed_value)
		_play_greedy_turn(fight)
		var rng_before: Dictionary = fight._rng.to_dict()
		var preview: Dictionary = fight.preview_end_turn()
		assert_eq(fight._rng.to_dict(), rng_before, "preview leaves the real RNG alone")
		assert_eq(fight.turn, 1)
		var before: int = fight.events.size()
		fight.end_turn()
		var turn_events: Array[Dictionary] = fight.events.slice(before)
		var next_turn: int = turn_events.size()
		for i: int in turn_events.size():
			if turn_events[i]["type"] == "turn_start" or (turn_events[i]["type"] == "perk" and turn_events[i]["perk"] == "brace"):
				next_turn = i
				break
		assert_eq(preview["events"], turn_events.slice(0, next_turn), "seed %d" % seed_value)
		assert_eq(preview["enemy_hp"], fight.enemy_hp)
		assert_eq(preview["player_hp"], fight.player_hp)
		assert_eq(preview["state"], fight.state)


# --- Replay and data ----------------------------------------------------------

func test_seed_and_moves_replay_a_whole_fight() -> void:
	for seed_value: int in 25:
		for enemy: String in data.ids("enemies"):
			var perks: Array[Dictionary] = [{"perk": "nudge", "source": "pearl_diver"}]
			var fight: Fight = _fight(enemy, perks, seed_value)
			var guard: int = 0
			while fight.state == Fight.State.PLAYER_TURN and guard < 40:
				_play_greedy_turn(fight)
				fight.end_turn()
				guard += 1
			assert_ne(fight.state, Fight.State.PLAYER_TURN, "fight ends")
			var replay: Fight = _fight(enemy, perks, seed_value)
			assert_true(replay.apply_moves(fight.moves))
			assert_eq(replay.events, fight.events, "%s seed %d" % [enemy, seed_value])
			assert_eq(replay.state, fight.state)
			assert_eq(replay.player_hp, fight.player_hp)


func test_replay_stops_at_a_bad_move() -> void:
	var fight: Fight = _fight()
	assert_false(fight.apply_moves([{"move": "take_back", "die": 0}] as Array[Dictionary]))
	assert_false(fight.apply_moves([{"move": "dance"}] as Array[Dictionary]))


func test_intents_parse_strictly() -> void:
	assert_eq(Fight.parse_intent("attack:4+guard:4"), {"attack": 4, "guard": 4})
	assert_eq(Fight.parse_intent("attack:4+gaurd:4"), {})
	assert_eq(Fight.parse_intent("attack:x"), {})
	assert_eq(Fight.parse_intent("attack:-1"), {})
	assert_eq(Fight.parse_intent("attack:1+attack:2"), {})
	assert_eq(Fight.parse_intent(""), {})


func test_shipped_enemies_and_kits_are_playable() -> void:
	for enemy: String in data.ids("enemies"):
		assert_eq(Fight.intent_errors(data.row("enemies", enemy)), PackedStringArray(), enemy)
	for slot_id: String in data.ids("slots"):
		var row: Dictionary = data.row("slots", slot_id)
		assert_between(row["dice_needed"] as int, 1, 4, slot_id)
		assert_true((row["min"] as int) <= (row["max"] as int), slot_id)
	for loadout: String in data.ids("loadouts"):
		assert_gt((data.row("loadouts", loadout)["hp"] as int), 0, loadout)


## Places each die, in id order, in the first slot (card order) that takes it.
## Deterministic, so replays and previews are comparable.
func _play_greedy_turn(fight: Fight) -> void:
	for d: Fight.Die in fight.hand:
		if fight.has_perk("nudge") and fight.nudges_left > 0 and d.value == 4:
			fight.nudge(d.id)
		for s: Fight.Slot in fight.slots:
			if fight.place(d.id, s.id):
				break
