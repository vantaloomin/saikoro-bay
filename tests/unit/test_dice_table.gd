extends GutTest
## The dice table on its own, without a fight (fights are covered by
## test_fight.gd and the golden fixtures).

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _table(lock: DiceTable.LockPolicy = DiceTable.LockPolicy.NONE) -> DiceTable:
	var table: DiceTable = DiceTable.create(data, ["d6", "d6", "d6", "d6"], ["strike", "pair_bet"], RngStreams.new(9))
	table.rerolls_per_turn = 1
	table.lock_policy = lock
	table.lock_source = "house_lock"
	table.reset_turn()
	table.roll_hand()
	table.apply_lock()
	return table


func _set_hand(table: DiceTable, values: Array[int]) -> void:
	for i: int in values.size():
		table.hand[i].value = values[i]


func test_unknown_dice_or_slots_make_no_table() -> void:
	assert_null(DiceTable.create(data, ["d7"], ["strike"], RngStreams.new(1)))
	assert_null(DiceTable.create(data, ["d6"], ["nope"], RngStreams.new(1)))


func test_moves_log_into_the_owners_arrays() -> void:
	var table: DiceTable = _table()
	var events: Array[Dictionary] = []
	var moves: Array[Dictionary] = []
	table.events = events
	table.moves = moves
	_set_hand(table, [2, 2, 5, 1])
	assert_true(table.place(0, "pair_bet"))
	assert_true(table.take_back(0))
	assert_eq(moves, [{"move": "place", "die": 0, "slot": "pair_bet"}, {"move": "take_back", "die": 0}] as Array[Dictionary])
	assert_eq(events.size(), 2)


func test_a_slot_refuses_dice_past_max_dice() -> void:
	var table: DiceTable = _table()
	_set_hand(table, [3, 3, 3, 3])
	assert_true(table.place(0, "pair_bet"))
	assert_false(table.slot("pair_bet").is_complete(), "below min_dice")
	assert_true(table.place(1, "pair_bet"))
	assert_true(table.slot("pair_bet").is_complete())
	assert_eq(table.place_refusal(2, "pair_bet"), "This slot is full.")


func test_no_lock_policy_locks_nothing() -> void:
	var table: DiceTable = _table()
	for d: DiceTable.Die in table.hand:
		assert_false(d.locked)


func test_the_highest_free_lock_takes_the_lowest_id_on_ties() -> void:
	var table: DiceTable = _table(DiceTable.LockPolicy.LOCK_HIGHEST_FREE)
	_set_hand(table, [2, 6, 6, 1])
	table.events.clear()
	table.apply_lock()
	assert_true(table.hand[1].locked)
	assert_false(table.hand[2].locked)
	assert_eq(table.events, [{"type": "twist", "twist": "house_lock", "die": 1}] as Array[Dictionary])


func test_nudge_needs_uses_left() -> void:
	var table: DiceTable = _table()
	_set_hand(table, [2, 2, 2, 2])
	assert_false(table.nudge(0), "no nudge perk, no uses")
	table.nudge_uses_per_turn = 1
	table.nudge_amount = 1
	table.reset_turn()
	assert_true(table.nudge(0))
	assert_eq(table.hand[0].value, 3)
	assert_false(table.nudge(1), "once per turn")


func test_a_copy_shares_nothing_and_cant_roll() -> void:
	var table: DiceTable = _table()
	var events: Array[Dictionary] = []
	var moves: Array[Dictionary] = []
	var before: int = table.hand[0].value
	var copy: DiceTable = table.copy(events, moves)
	assert_false(copy.can_roll())
	assert_true(is_same(copy.events, events))
	copy.hand[0].value = before % 6 + 1
	copy.place(1, "strike")
	assert_eq(table.hand[0].value, before, "the original's dice are untouched")
	assert_true(table.slot("strike").dice.is_empty(), "the original's slots are untouched")
	assert_eq(copy.reroll_refusal(0), "Planning copies can't reroll.")


# --- Slot rules for the rooms: three of a kind, runs, sums, persistence ---------

const ROOM_SLOTS: Array[Dictionary] = [
	{"id": "lock_sum", "name": "Sum", "text": "t", "accepts": "sum_at_least", "min": 10, "max": 18,
		"min_dice": 2, "max_dice": 3, "persists": true, "effect": "damage", "resource": "", "mult": 0, "add": 0, "icon_shape": "x"},
	{"id": "lock_pair", "name": "Pair", "text": "t", "accepts": "pair", "min": 1, "max": 6,
		"min_dice": 2, "max_dice": 2, "persists": true, "effect": "damage", "resource": "", "mult": 0, "add": 0, "icon_shape": "x"},
	{"id": "lock_run", "name": "Run", "text": "t", "accepts": "run", "min": 1, "max": 6,
		"min_dice": 3, "max_dice": 3, "persists": true, "effect": "damage", "resource": "", "mult": 0, "add": 0, "icon_shape": "x"},
	{"id": "triple", "name": "Triple", "text": "t", "accepts": "three_kind", "min": 1, "max": 6,
		"min_dice": 3, "max_dice": 3, "persists": false, "effect": "damage", "resource": "", "mult": 0, "add": 0, "icon_shape": "x"},
]


func _room_table(dice_count: int = 6) -> DiceTable:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var slots: Dictionary = JSON.parse_string(texts["slots"])
	(slots["items"] as Array).append_array(ROOM_SLOTS)
	texts["slots"] = JSON.stringify(slots)
	var room_data: GameData = GameData.new()
	room_data.load_texts(texts)
	assert_eq(room_data.errors, PackedStringArray())
	var dice: Array = []
	for i: int in dice_count:
		dice.append("d6")
	var table: DiceTable = DiceTable.create(room_data, dice, ["lock_sum", "lock_pair", "lock_run", "triple"], RngStreams.new(4))
	table.rerolls_per_turn = 1
	table.reset_turn()
	table.roll_hand()
	return table


func test_three_of_a_kind_matches_the_first_die() -> void:
	var table: DiceTable = _room_table()
	_set_hand(table, [4, 4, 5, 4, 1, 1])
	assert_true(table.place(0, "triple"))
	assert_eq(table.place_refusal(2, "triple"), "Needs a 4 to match.")
	assert_true(table.place(1, "triple"))
	assert_false(table.slot("triple").is_complete())
	assert_true(table.place(3, "triple"))
	assert_true(table.slot("triple").is_complete())


func test_a_run_refuses_repeats_and_gaps() -> void:
	var table: DiceTable = _room_table()
	_set_hand(table, [3, 3, 6, 5, 4, 1])
	assert_true(table.place(0, "lock_run"))
	assert_eq(table.place_refusal(1, "lock_run"), "The run already has a 3.")
	assert_eq(table.place_refusal(2, "lock_run"), "Too far from the run.", "3 and 6 can't be in a run of 3")
	assert_true(table.place(3, "lock_run"))
	assert_false(table.slot("lock_run").is_complete())
	assert_true(table.place(4, "lock_run"))
	assert_true(table.slot("lock_run").is_complete(), "3, 5, 4")


func test_a_sum_takes_any_die_and_checks_the_total() -> void:
	var table: DiceTable = _room_table()
	_set_hand(table, [2, 3, 6, 1, 1, 1])
	assert_true(table.place(0, "lock_sum"))
	assert_true(table.place(1, "lock_sum"))
	assert_false(table.slot("lock_sum").is_complete(), "5 is short of 10")
	assert_true(table.place(2, "lock_sum"))
	assert_true(table.slot("lock_sum").is_complete(), "11")
	assert_eq(table.place_refusal(3, "lock_sum"), "This slot is full.")


func _open_the_pair(table: DiceTable) -> void:
	_set_hand(table, [4, 4, 2, 1, 1, 1])
	table.place(0, "lock_pair")
	table.place(1, "lock_pair")
	table.place(2, "lock_sum")
	table.reset_turn()
	table.roll_hand()


func test_a_complete_persistent_slot_stays_open_and_gives_its_dice_back() -> void:
	var table: DiceTable = _room_table()
	_open_the_pair(table)
	var pair: DiceTable.Slot = table.slot("lock_pair")
	assert_true(pair.sealed)
	assert_true(pair.is_complete(), "it stays open")
	assert_eq(pair.opened_with, [4, 4] as Array[int])
	assert_eq(pair.dice, [] as Array[int], "its dice come back")
	assert_eq(table.hand[0].slot_id, "")
	assert_true(table.hand[0].is_free(), "and can go anywhere this turn")
	assert_eq(table.place_refusal(3, "lock_pair"), "This lock is already open.")
	assert_true(table.slot("lock_sum").dice.is_empty(), "an unfinished lock empties at the turn's end")
	assert_false(table.slot("lock_sum").sealed)


func test_returned_dice_roll_again() -> void:
	var table: DiceTable = _room_table()
	_set_hand(table, [4, 4, 2, 1, 1, 1])
	table.place(0, "lock_pair")
	table.place(1, "lock_pair")
	var again: DiceTable = _room_table()
	_set_hand(again, [4, 4, 2, 1, 1, 1])
	table.reset_turn()
	again.reset_turn()
	assert_eq(table.roll_hand(), again.roll_hand(), "an open lock rolls the same dice as none")
	assert_true(table.reroll(2), "they can pay for a reroll too")


func test_an_open_lock_stays_open_through_later_turns() -> void:
	var table: DiceTable = _room_table()
	_open_the_pair(table)
	table.reset_turn()
	table.roll_hand()
	assert_true(table.slot("lock_pair").sealed)
	assert_eq(table.slot("lock_pair").opened_with, [4, 4] as Array[int], "sealed once, never re-recorded")


func test_sealed_slots_survive_a_copy() -> void:
	var table: DiceTable = _room_table()
	_open_the_pair(table)
	var copy: DiceTable = table.copy([] as Array[Dictionary], [] as Array[Dictionary])
	assert_true(copy.slot("lock_pair").sealed)
	assert_true(copy.slot("lock_pair").is_complete())
	assert_eq(copy.slot("lock_pair").opened_with, [4, 4] as Array[int])
	copy.slot("lock_pair").opened_with.append(9)
	assert_eq(table.slot("lock_pair").opened_with, [4, 4] as Array[int], "the copy shares nothing")
	assert_true(is_same(copy.slot("lock_pair").hand, copy.hand), "a copy's slots read the copy's dice")


# --- Completeness checks the rule, not just the count (Imogen's #23 audit) ------

func _loose_slot(accepts: String, min_dice: int, max_dice: int) -> DiceTable.Slot:
	var s: DiceTable.Slot = DiceTable.Slot.new()
	s.row = {"accepts": accepts, "min": 1, "max": 6, "min_dice": min_dice, "max_dice": max_dice}
	return s


func test_a_run_with_room_to_grow_is_complete_only_without_gaps() -> void:
	var run: DiceTable.Slot = _loose_slot("run", 2, 4)
	assert_false(run.is_complete_with([1, 3] as Array[int]), "1 and 3 keep a run possible but aren't one")
	assert_true(run.is_complete_with([3, 2] as Array[int]))
	assert_true(run.is_complete_with([2, 4, 3] as Array[int]))
	assert_false(run.is_complete_with([2, 2, 3] as Array[int]), "no repeats")


func test_matching_slots_complete_only_when_every_die_matches() -> void:
	assert_false(_loose_slot("three_kind", 3, 3).is_complete_with([5, 5, 4] as Array[int]))
	assert_true(_loose_slot("three_kind", 3, 3).is_complete_with([5, 5, 5] as Array[int]))
	assert_false(_loose_slot("pair", 2, 2).is_complete_with([2, 3] as Array[int]))
