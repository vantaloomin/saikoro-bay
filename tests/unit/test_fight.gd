extends GutTest
## Fight: the dice fight rules (specs/dice-fight-rules.md), one rule per test.
## Most tests set die values by hand so each rule is checked on a known hand.

## Rule tests use fixed enemies, so tuning data/enemies.json never breaks
## them. Everything else comes from the shipped data files.
const TEST_ENEMIES: Array[Dictionary] = [
	{"id": "card_shark", "name": "Card Shark", "tier": "regular", "hp": 18, "intents": ["attack:6", "attack:4+guard:4"],
		"twist": "none", "twist_text": ""},
	{"id": "hermit_croupier", "name": "Hermit Croupier", "tier": "regular", "hp": 22, "intents": ["attack:5", "attack:7"],
		"twist": "house_lock", "twist_text": "t"},
	{"id": "snake_eyes_eel", "name": "Snake-Eyes Eel", "tier": "regular", "hp": 16, "intents": ["attack:4", "attack:4", "attack:9"],
		"twist": "snake_eyes", "twist_text": "t"},
	{"id": "test_puffer", "name": "Test Puffer", "tier": "regular", "hp": 30, "intents": ["attack:9"],
		"twist": "spines", "twist_text": "t"},
	{"id": "test_crab", "name": "Test Crab", "tier": "regular", "hp": 30, "intents": ["attack:4", "attack:5"],
		"twist": "rising_stakes", "twist_text": "t"},
	{"id": "test_elite", "name": "Test Elite", "tier": "elite", "hp": 40, "intents": ["attack:8"],
		"twist": "none", "twist_text": ""},
]

var data: GameData
var shipped: GameData


func before_all() -> void:
	shipped = GameData.load_dir()
	var texts: Dictionary[String, String] = {}
	for table: String in GameData.TABLES:
		texts[table] = FileAccess.get_file_as_string("%s/%s.json" % [GameData.DATA_DIR, table])
	texts["enemies"] = JSON.stringify({"schema": GameData.SCHEMA, "items": TEST_ENEMIES})
	data = GameData.new()
	data.load_texts(texts)
	assert_eq(data.errors, PackedStringArray())


func _fight(enemy: String = "card_shark", perks: Array[Dictionary] = [], seed_value: int = 7) -> Fight:
	var fight: Fight = Fight.create(data, "fresh", enemy, RngStreams.new(seed_value), perks)
	assert_not_null(fight)
	return fight


## Sets the hand to `values` (in die-id order) and reapplies the House lock.
func _set_hand(fight: Fight, values: Array[int]) -> void:
	for i: int in values.size():
		fight.hand[i].value = values[i]
	fight.table.apply_lock()
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


func test_unknown_perks_are_reported_and_skipped() -> void:
	var fight: Fight = _fight("card_shark", [{"perk": "ghost", "source": "x"}])
	assert_false(fight.has_perk("ghost"))
	assert_push_error("unknown perk \"ghost\"")


func test_no_fight_for_a_defeated_player() -> void:
	assert_null(Fight.create(data, "fresh", "card_shark", RngStreams.new(1), [], 0))


func test_intents_and_faces_are_frozen() -> void:
	var fight: Fight = _fight()
	assert_true(fight.current_intent().is_read_only())
	assert_true(fight.hand[0].faces.is_read_only())


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
	expected_rng.load_dict(fight.table._rng.to_dict())
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


func test_spines_stop_block_from_unused_dice() -> void:
	var fight: Fight = _fight("test_puffer")
	_set_hand(fight, [1, 1, 4, 3])
	fight.place(2, "guard")
	fight.place(3, "strike")
	var preview: Dictionary = fight.preview_end_turn()
	fight.end_turn()
	# Guard 5 only, no unused-die block: 9 - 5 = 4 through.
	assert_eq(fight.player_hp, 26)
	assert_eq(preview["player_hp"], 26, "the preview runs the same rule")
	var spined: Array[Dictionary] = _events_of(fight, "twist")
	assert_eq(spined.size(), 1)
	assert_eq(spined[0]["amount"], 2, "the block it stopped is in the event")
	for event: Dictionary in _events_of(fight, "block"):
		assert_ne(event["source"], "unused_dice")


func test_rising_stakes_grow_each_attack_by_one() -> void:
	var fight: Fight = _fight("test_crab")
	var attacks: Array[int] = []
	for t: int in 4:
		attacks.append(fight.current_intent()["attack"] as int)
		if t == 0:
			assert_eq(fight.next_intent()["attack"], 6, "the next intent shows its raise too")
		_set_hand(fight, [6, 6, 6, 6])
		for d: int in 4:
			fight.place(d, "guard") if d < 2 else fight.place(d, "strike")
		fight.end_turn()
		if fight.state != Fight.State.PLAYER_TURN:
			break
	assert_eq(attacks, [4, 6, 6, 8] as Array[int])


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
	assert_eq(fight.preview(0, "strike"), {"ok": true, "reason": "", "effect": "damage", "amount": 3,
		"landed": 3, "blocked": 0, "complete": true, "can_complete": true})
	assert_eq(fight.preview(1, "high_roller")["amount"], 8)
	assert_eq(fight.preview(0, "guard")["amount"], 4)
	assert_eq(fight.preview(1, "guard")["reason"], "Needs 1 to 4.")
	var half: Dictionary = fight.preview(2, "pair_bet")
	assert_false(half["complete"])
	assert_eq(half["amount"], 8, "assumes the match arrives")
	assert_true(half["can_complete"])
	fight.place(2, "pair_bet")
	assert_eq(fight.preview(3, "pair_bet")["amount"], 8)
	assert_true(fight.preview(3, "pair_bet")["complete"])
	assert_true(fight.slot("strike").dice.is_empty(), "previews don't place")


func test_end_turn_preview_is_exact_and_moves_nothing() -> void:
	for seed_value: int in 20:
		var fight: Fight = _fight("snake_eyes_eel", [{"perk": "brace", "source": "shipwright"}], seed_value)
		_play_greedy_turn(fight)
		var rng_before: Dictionary = fight.table._rng.to_dict()
		var preview: Dictionary = fight.preview_end_turn()
		assert_eq(fight.table._rng.to_dict(), rng_before, "preview leaves the real RNG alone")
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


func test_slot_preview_counts_enemy_guard() -> void:
	var fight: Fight = _fight()
	fight.end_turn()
	assert_eq(fight.enemy_block, 4)
	_set_hand(fight, [6, 5, 1, 1])
	var strike: Dictionary = fight.preview(0, "strike")
	assert_eq(strike["amount"], 6)
	assert_eq(strike["landed"], 2)
	assert_eq(strike["blocked"], 4)
	var high: Dictionary = fight.preview(1, "high_roller")
	assert_eq([high["landed"], high["blocked"]], [4, 4])
	fight.place(0, "strike")
	high = fight.preview(1, "high_roller")
	assert_eq([high["landed"], high["blocked"]], [8, 0], "Strike resolves first and uses up the guard")
	var hp: int = fight.enemy_hp
	fight.place(1, "high_roller")
	fight.end_turn()
	assert_eq(fight.enemy_hp, hp - 2 - 8)


func test_pair_preview_says_when_no_match_is_left() -> void:
	var fight: Fight = _fight()
	_set_hand(fight, [6, 1, 2, 3])
	var pair: Dictionary = fight.preview(0, "pair_bet")
	assert_eq(pair["amount"], 24)
	assert_false(pair["complete"])
	assert_false(pair["can_complete"])
	_set_hand(fight, [6, 1, 6, 3])
	assert_true(fight.preview(0, "pair_bet")["can_complete"])


func test_pair_match_must_be_free_and_unlocked() -> void:
	var fight: Fight = _fight("hermit_croupier")
	_set_hand(fight, [6, 6, 2, 3])
	# Die 0 is locked (lowest id of the two 6s), so die 1 has no match.
	assert_true(fight.hand[0].locked)
	assert_false(fight.preview(1, "pair_bet")["can_complete"])


func test_snake_eyes_kill_ends_before_the_enemy_attacks() -> void:
	var fight: Fight = _fight("snake_eyes_eel")
	fight.player_hp = 1
	_set_hand(fight, [1, 1, 4, 3])
	fight.end_turn()
	assert_eq(fight.state, Fight.State.LOST)
	assert_eq(fight.player_hp, 0)
	for event: Dictionary in _events_of(fight, "damage"):
		assert_ne(event["source"], "enemy", "a defeated player isn't hit again")


func test_the_fight_and_its_table_share_one_log() -> void:
	var fight: Fight = _fight()
	assert_true(is_same(fight.events, fight.table.events))
	assert_true(is_same(fight.moves, fight.table.moves))
	var fresh_events: Array[Dictionary] = []
	var fresh_moves: Array[Dictionary] = []
	fight.events = fresh_events
	fight.moves = fresh_moves
	assert_true(is_same(fight.table.events, fresh_events), "reassigning rebinds the table")
	assert_true(is_same(fight.table.moves, fresh_moves))
	_set_hand(fight, [3, 3, 3, 3])
	fight.place(0, "strike")
	fight.end_turn()
	assert_eq(fresh_moves, [{"move": "place", "die": 0, "slot": "strike"}, {"move": "end_turn"}] as Array[Dictionary])


func test_planning_copy_matches_the_fight_and_cant_roll() -> void:
	var fight: Fight = _fight("hermit_croupier", [{"perk": "nudge", "source": "pearl_diver"}, {"perk": "brace", "source": "shipwright"}])
	_set_hand(fight, [4, 6, 2, 2])
	fight.place(2, "pair_bet")
	fight.nudge(0)
	var copy: Fight = fight.planning_copy()
	var skip: Array[String] = ["events", "moves", "_rng", "_is_preview"]
	assert_eq(_vars(copy, skip), _vars(fight, skip), "every field is copied, the dice table's too")
	assert_true(copy.table.events == copy.events and is_same(copy.table.events, copy.events), "one event log per room")
	assert_true(is_same(copy.table.moves, copy.moves), "one move log per room")
	assert_false(is_same(copy.table.hand, fight.table.hand), "dice aren't shared")
	assert_false(copy.table.can_roll())
	assert_eq(copy.reroll_refusal(3), "Planning copies can't reroll.")
	assert_true(copy.end_turn())
	assert_eq(copy.turn, fight.turn, "a planning copy stops before the next roll")
	copy._perks["brace"].amount = 99
	assert_eq(fight._perks["brace"].amount, 2, "perks aren't shared")


## Script variables of `value`, recursing into objects, arrays and
## dictionaries. `skip` names are left out at every depth.
func _vars(value: Variant, skip: Array[String] = []) -> Variant:
	if value is Object:
		var out: Dictionary = {}
		for prop: Dictionary in (value as Object).get_property_list():
			var prop_name: String = prop["name"]
			if (prop["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE and not prop_name in skip:
				out[prop_name] = _vars((value as Object).get(prop_name), skip)
		return out
	if value is Array:
		var items: Array = []
		for item: Variant in value as Array:
			items.append(_vars(item, skip))
		return items
	if value is Dictionary:
		var entries: Dictionary = {}
		for key: Variant in value as Dictionary:
			entries[key] = _vars((value as Dictionary)[key], skip)
		return entries
	return value


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


func test_later_fights_of_a_delve_replay_from_their_start() -> void:
	var perks: Array[Dictionary] = [{"perk": "nudge", "source": "pearl_diver"}]
	for seed_value: int in 10:
		var rng: RngStreams = RngStreams.new(seed_value)
		var first: Fight = Fight.create(data, "fresh", "card_shark", rng, perks, 999)
		first.player_hp = 999
		while first.state == Fight.State.PLAYER_TURN:
			_play_greedy_turn(first)
			first.end_turn()
		var second: Fight = Fight.create(data, "fresh", "snake_eyes_eel", rng, perks, 20)
		while second.state == Fight.State.PLAYER_TURN:
			_play_greedy_turn(second)
			second.end_turn()
		var rebuilt: RngStreams = RngStreams.new()
		assert_true(rebuilt.load_dict(second.start_rng))
		var replay: Fight = Fight.create(data, "fresh", "snake_eyes_eel", rebuilt, perks, second.start_hp)
		assert_true(replay.apply_moves(second.moves))
		assert_eq(replay.events, second.events, "seed %d" % seed_value)


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
	for enemy: String in shipped.ids("enemies"):
		assert_eq(Fight.intent_errors(shipped.row("enemies", enemy)), PackedStringArray(), enemy)
	for slot_id: String in shipped.ids("slots"):
		var row: Dictionary = shipped.row("slots", slot_id)
		assert_between(row["min_dice"] as int, 1, 4, slot_id)
		assert_between(row["max_dice"] as int, row["min_dice"] as int, 4, slot_id)
		assert_true((row["min"] as int) <= (row["max"] as int), slot_id)
	for loadout: String in shipped.ids("loadouts"):
		assert_gt((shipped.row("loadouts", loadout)["hp"] as int), 0, loadout)


## Places each die, in id order, in the first slot (card order) that takes it.
## Deterministic, so replays and previews are comparable.
func _play_greedy_turn(fight: Fight) -> void:
	for d: Fight.Die in fight.hand:
		if fight.has_perk("nudge") and fight.nudges_left > 0 and d.value == 4:
			fight.nudge(d.id)
		for s: Fight.Slot in fight.slots:
			if fight.place(d.id, s.id):
				break


# --- Persistent slots (Imogen's #23 audit, finding 1) -------------------------

func test_a_sealed_slot_fires_once_and_never_again() -> void:
	var fight: Fight = _fight()
	var strike: Fight.Slot = fight.slot("strike")
	var row: Dictionary = strike.row.duplicate()
	row["persists"] = true
	strike.row = row
	_set_hand(fight, [5, 1, 1, 1])
	assert_true(fight.place(0, "strike"))
	fight.end_turn()
	var hits: int = 0
	for event: Dictionary in fight.events:
		if event.get("source", "") == "slot:strike":
			hits += 1
	assert_eq(hits, 1)
	assert_true(strike.sealed, "the strike stays filled")
	assert_eq(fight.slot_amount(strike), 0, "and previews agree it won't fire again")
	fight.events.clear()
	fight.end_turn()
	for event: Dictionary in fight.events:
		assert_ne(event.get("source", ""), "slot:strike", "a sealed slot doesn't fire on later turns")
