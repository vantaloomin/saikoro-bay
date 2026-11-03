extends GutTest
## Treasure, rest and rescue rooms (specs/delve-map.md section 3), and the
## room bot that plays them.

const NUDGE: Array[Dictionary] = [{"perk": "nudge", "source": "pearl_diver"}]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()
	assert_eq(data.errors, PackedStringArray())


func _room(room_id: String, hp: int = 20, perks: Array[Dictionary] = [], seed_value: int = 5) -> DiceRoom:
	var room: DiceRoom = DiceRoom.create(data, "fresh", room_id, RngStreams.new(seed_value), perks, hp)
	assert_not_null(room)
	return room


func _set_hand(room: DiceRoom, values: Array[int]) -> void:
	for i: int in values.size():
		room.hand[i].value = values[i]
	room.events.clear()


func _events_of(room: DiceRoom, type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in room.events:
		if event["type"] == type:
			found.append(event)
	return found


func test_bad_inputs_make_no_room() -> void:
	assert_null(DiceRoom.create(data, "fresh", "fight", RngStreams.new(1), [], 20), "a fight isn't a dice room")
	assert_null(DiceRoom.create(data, "nope", "rest", RngStreams.new(1), [], 20))
	assert_null(DiceRoom.create(data, "fresh", "rest", RngStreams.new(1), [], 0), "nobody walks in at 0 HP")


# --- Treasure ---------------------------------------------------------------------

func test_treasure_pays_each_open_lock() -> void:
	var room: DiceRoom = _room("treasure")
	assert_eq(room.slots.size(), 3)
	_set_hand(room, [6, 3, 3, 3])
	assert_true(room.place(0, "small_lock"))
	for die_id: int in [1, 2, 3]:
		assert_true(room.place(die_id, "jackpot_lock"))
	assert_true(room.end_turn())
	assert_eq(room.state, DiceRoom.State.DONE, "one turn, then it's over")
	assert_eq(room.payout, {"driftwood": 6, "koban_coins": 1} as Dictionary[String, int])
	assert_eq(room.hp, 20, "treasure is never a risk")
	assert_false(room.end_turn())


func test_the_pearl_lock_needs_a_pair() -> void:
	var room: DiceRoom = _room("treasure")
	_set_hand(room, [2, 5, 2, 1])
	assert_true(room.place(0, "pearl_lock"))
	assert_eq(room.place_refusal(1, "pearl_lock"), "Needs a 2 to match.")
	assert_true(room.place(2, "pearl_lock"))
	room.end_turn()
	assert_eq(room.payout, {"pearls": 2} as Dictionary[String, int])


func test_a_half_filled_lock_pays_nothing() -> void:
	var room: DiceRoom = _room("treasure")
	_set_hand(room, [4, 4, 1, 2])
	room.place(0, "jackpot_lock")
	room.place(1, "jackpot_lock")
	room.end_turn()
	assert_true(room.payout.is_empty())
	assert_eq(_events_of(room, "loot"), [] as Array[Dictionary])


func test_treasure_has_one_reroll_that_keeps_placed_dice() -> void:
	var room: DiceRoom = _room("treasure")
	_set_hand(room, [6, 1, 2, 3])
	room.place(0, "small_lock")
	assert_true(room.reroll(1))
	assert_eq(room.die(0).value, 6)
	assert_eq(room.reroll_refusal(2), "No rerolls left this turn.")


# --- Rest ---------------------------------------------------------------------------

func test_rest_heals_by_the_soak_total_up_to_max_hp() -> void:
	var room: DiceRoom = _room("rest", 22)
	_set_hand(room, [6, 5, 1, 1])
	assert_true(room.place(0, "soak"))
	assert_true(room.place(1, "soak"))
	assert_eq(room.place_refusal(2, "soak"), "This slot is full.")
	assert_eq(room.reroll_refusal(2), "No rerolls left this turn.", "rest is one roll")
	room.end_turn()
	assert_eq(room.hp, 30, "11 healed, capped at 30")
	assert_eq(_events_of(room, "heal")[0]["amount"], 8, "the event shows what really healed")
	assert_eq(room.state, DiceRoom.State.DONE)


func test_one_die_is_enough_to_soak() -> void:
	var room: DiceRoom = _room("rest", 10)
	_set_hand(room, [4, 1, 1, 1])
	room.place(0, "soak")
	room.end_turn()
	assert_eq(room.hp, 14)


# --- Rescue -------------------------------------------------------------------------

func test_the_tide_takes_two_hp_a_turn_while_the_cage_is_shut() -> void:
	var room: DiceRoom = _room("rescue", 20)
	assert_eq(room.turns_left(), 3)
	for turn: int in 3:
		room.end_turn()
	assert_eq(room.state, DiceRoom.State.DONE)
	assert_false(room.succeeded, "out of turns: they stay caged")
	assert_eq(room.hp, 14)
	for event: Dictionary in _events_of(room, "damage"):
		assert_eq(event["source"], "tide")
		assert_eq(event["blocked"], 0, "the tide ignores block")


func test_the_tide_can_wash_you_up() -> void:
	var room: DiceRoom = _room("rescue", 3)
	room.end_turn()
	assert_eq(room.hp, 1)
	room.end_turn()
	assert_eq(room.hp, 0)
	assert_eq(room.state, DiceRoom.State.LOST)
	assert_false(room.end_turn())


func test_open_locks_stay_open_and_give_their_dice_back() -> void:
	var room: DiceRoom = _room("rescue", 20)
	_set_hand(room, [5, 5, 3, 1])
	room.place(0, "cage_pair")
	room.place(1, "cage_pair")
	room.place(2, "cage_sum")
	room.end_turn()
	assert_eq(room.open_count(), 1, "the pair opened; the half-filled sum didn't")
	assert_eq(room.hp, 18)
	assert_eq(room.hand.filter(func(d: DiceRoom.Die) -> bool: return d.is_free()).size(), 4, "all four dice roll again")
	_set_hand(room, [2, 3, 4, 6])
	for die_id: int in [0, 1, 2]:
		assert_true(room.place(die_id, "cage_run"))
	assert_eq(room.place_refusal(3, "cage_pair"), "This lock is already open.")
	room.end_turn()
	assert_eq(room.open_count(), 2)
	assert_eq(room.hp, 16)
	_set_hand(room, [6, 5, 1, 1])
	room.place(0, "cage_sum")
	room.place(1, "cage_sum")
	room.end_turn()
	assert_true(room.succeeded, "all three open: the villager is free")
	assert_eq(room.state, DiceRoom.State.DONE)
	assert_eq(room.hp, 16, "no tide on the turn the cage opens")
	assert_eq(_events_of(room, "opened").size(), 1)


func test_two_locks_can_open_in_one_turn() -> void:
	var room: DiceRoom = _room("rescue", 20)
	_set_hand(room, [5, 5, 6, 4])
	room.place(0, "cage_pair")
	room.place(1, "cage_pair")
	room.place(2, "cage_sum")
	room.place(3, "cage_sum")
	room.end_turn()
	assert_eq(room.open_count(), 2)
	assert_eq(_events_of(room, "open").size(), 2)
	room.events.clear()
	room.end_turn()
	assert_eq(_events_of(room, "open"), [] as Array[Dictionary], "an open lock opens once")


func test_the_bot_opens_the_cage_often_enough() -> void:
	var opened: int = 0
	for s: int in range(1, 41):
		var room: DiceRoom = _room("rescue", 20, [], s)
		RoomBot.new().play_room(room)
		if room.succeeded:
			opened += 1
	assert_between(opened, 8, 28, "about 40%% without Nudge (got %d of 40)" % opened)


# --- Nudge, replay, copies --------------------------------------------------------------

func test_nudge_works_in_rooms_too() -> void:
	var room: DiceRoom = _room("rest", 10, NUDGE)
	_set_hand(room, [5, 1, 1, 1])
	assert_true(room.nudge(0))
	assert_eq(room.die(0).value, 6)
	assert_false(room.nudge(1), "once a turn")
	assert_false(_room("rest", 10).nudge(0), "only with the perk")


func test_a_room_replays_from_its_seed_and_moves() -> void:
	var room: DiceRoom = _room("rescue", 20, NUDGE, 31)
	RoomBot.new().play_room(room)
	var again: DiceRoom = DiceRoom.create(data, "fresh", "rescue", RngStreams.new(31), NUDGE, 20)
	assert_true(again.apply_moves(room.moves))
	assert_eq(again.hp, room.hp)
	assert_eq(again.state, room.state)
	assert_eq(again.events, room.events)
	assert_eq(again.start_rng, room.start_rng)


func test_a_planning_copy_cant_touch_the_room() -> void:
	var room: DiceRoom = _room("treasure")
	_set_hand(room, [6, 6, 1, 2])
	var copy: DiceRoom = room.planning_copy()
	copy.place(0, "pearl_lock")
	copy.place(1, "pearl_lock")
	assert_true(copy.end_turn())
	assert_eq(copy.payout, {"pearls": 2} as Dictionary[String, int])
	assert_true(room.payout.is_empty())
	assert_true(room.moves.is_empty())
	assert_eq(room.state, DiceRoom.State.PLAYER_TURN)


# --- The room bot -------------------------------------------------------------------------

func test_the_bot_takes_the_best_payout() -> void:
	var room: DiceRoom = _room("treasure")
	_set_hand(room, [5, 5, 5, 6])
	RoomBot.new().play_turn(room)
	room.end_turn()
	assert_eq(room.payout, {"driftwood": 6, "koban_coins": 1} as Dictionary[String, int])


func test_the_bot_soaks_its_two_highest_dice() -> void:
	var room: DiceRoom = _room("rest", 5)
	_set_hand(room, [2, 6, 3, 5])
	RoomBot.new().play_room(room)
	assert_eq(room.hp, 16)


func test_the_bot_plays_the_same_every_time() -> void:
	for room_id: String in ["treasure", "rest", "rescue"]:
		var first: DiceRoom = _room(room_id, 20, NUDGE, 77)
		var second: DiceRoom = _room(room_id, 20, NUDGE, 77)
		RoomBot.new().play_room(first)
		RoomBot.new().play_room(second)
		assert_eq(first.moves, second.moves, room_id)


func test_a_planning_copy_resolves_its_turn_once() -> void:
	var room: DiceRoom = _room("treasure")
	_set_hand(room, [6, 1, 2, 3])
	var copy: DiceRoom = room.planning_copy()
	copy.place(0, "small_lock")
	assert_true(copy.end_turn())
	assert_false(copy.end_turn(), "a second preview would pay again")
	assert_eq(copy.payout, {"driftwood": 6} as Dictionary[String, int])
	copy.start_rng["changed"] = true
	assert_false(room.start_rng.has("changed"), "the copy shares nothing")
