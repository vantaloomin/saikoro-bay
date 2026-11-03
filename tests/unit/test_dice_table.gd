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
