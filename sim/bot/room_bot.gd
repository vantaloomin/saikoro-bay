class_name RoomBot
extends RefCounted
## Plays a treasure, rest or rescue room (DiceRoom) through the same moves
## the board uses, the way a careful new player might.
##
## Each turn it lists, for every open slot, the sets of free dice that
## would complete it (a half-filled slot never pays), tries every way of
## combining sets that share no die, with or without one nudge, on planning
## copies, and keeps the plan whose resolved turn scores best. If dice are
## left over and a reroll is available, it keeps the plan's dice in place,
## spends the lowest leftover die to reroll the rest, and plans again.
##
## Like the fight bots it never draws randomness: copies have no streams.
## Ties keep the first plan found (fewest dice, lowest ids), so a seed plays
## out the same every time.

const WIN_SCORE: int = 1_000_000
const OPEN_SCORE: int = 1_000
## What a resource is worth to the bot, per unit. Placeholder, like the
## loot numbers.
const RESOURCE_WORTH: Dictionary[String, int] = {"driftwood": 1, "pearls": 4, "koban_coins": 10}
const HEAL_WORTH: int = 2

## Plans scored so far (each one a planning copy and a resolved turn), so a
## test can pin the work the bot does.
var trials: int = 0


## Plays the room to the end. Returns the number of turns played.
func play_room(room: DiceRoom) -> int:
	while room.state == DiceRoom.State.PLAYER_TURN:
		play_turn(room)
		room.end_turn()
	return room.turn


## Makes this turn's moves (not end_turn).
func play_turn(room: DiceRoom) -> void:
	_apply(room, best_plan(room))
	var leftovers: Array[int] = _free_dice(room)
	if leftovers.size() >= 2 and room.reroll_refusal(leftovers[0]).is_empty():
		var lowest: int = leftovers[0]
		for die_id: int in leftovers:
			if room.die(die_id).value < room.die(lowest).value:
				lowest = die_id
		room.reroll(lowest)
		_apply(room, best_plan(room))


## The best plan for the free dice: {"score", "nudge" (die id or -1),
## "places" ([[die, slot], ...])}.
func best_plan(room: DiceRoom) -> Dictionary:
	var best: Dictionary = _best_placement(room, -1)
	if room.table.nudges_left > 0:
		for die_id: int in _free_dice(room):
			var nudged: DiceRoom = room.planning_copy()
			if not nudged.nudge(die_id):
				continue
			var plan: Dictionary = _best_placement(nudged, die_id)
			if plan["score"] > best["score"]:
				best = plan
	return best


static func score(before: DiceRoom, after: DiceRoom) -> int:
	if after.state == DiceRoom.State.LOST:
		return -WIN_SCORE
	var value: int = 0
	if after.succeeded:
		value += WIN_SCORE
	if after.open_all:
		value += (after.open_count() - before.open_count()) * OPEN_SCORE
	value += (after.hp - before.hp) * HEAL_WORTH
	for id: String in after.payout:
		value += (after.payout[id] - before.payout.get(id, 0)) * RESOURCE_WORTH.get(id, 1)
	return value


func _best_placement(room: DiceRoom, nudged: int) -> Dictionary:
	var dice: Array[int] = _free_dice(room)
	# A half-filled slot never pays, so each slot only needs the sets of free
	# dice that would complete it; a plan is a choice of disjoint sets.
	var options: Array = []
	for s: DiceRoom.Slot in room.slots:
		options.append(_completing_sets(room, s, dice) if not s.sealed else [])
	var plans: Array = []
	_combine(options, 0, 0, [], plans)
	var best: Dictionary = {"score": -WIN_SCORE - 1, "nudge": nudged, "places": []}
	var best_used: int = 0
	for places: Array in plans:
		var trial: DiceRoom = room.planning_copy()
		var ok: bool = true
		for p: Array in places:
			if not trial.place(p[0] as int, p[1] as String):
				ok = false
				break
		if not ok:
			continue
		trials += 1
		trial.end_turn()
		var value: int = score(room, trial)
		if value > best["score"] or (value == best["score"] and places.size() < best_used):
			best = {"score": value, "nudge": nudged, "places": places}
			best_used = places.size()
	return best


## Every set of `dice` (as a bitmask over that list) that completes `s`
## on its own: the right count, each die allowed in, and the slot's rule.
func _completing_sets(room: DiceRoom, s: DiceRoom.Slot, dice: Array[int]) -> Array:
	var sets: Array = []
	for mask: int in range(1, 1 << dice.size()):
		var values: Array[int] = []
		var ids: Array[int] = []
		for i: int in dice.size():
			if mask & (1 << i):
				ids.append(dice[i])
				values.append(room.die(dice[i]).value)
		if values.size() > s.max_dice() or not s.is_complete_with(values):
			continue
		if not _each_die_fits(s, values):
			continue
		sets.append({"mask": mask, "ids": ids, "slot": s.id})
	return sets


## The per-die rules a slot checks on the way in (range, even, odd, exact).
static func _each_die_fits(s: DiceRoom.Slot, values: Array[int]) -> bool:
	for v: int in values:
		match s.row["accepts"] as String:
			"range":
				if v < (s.row["min"] as int) or v > (s.row["max"] as int):
					return false
			"even":
				if v % 2 != 0:
					return false
			"odd":
				if v % 2 == 0:
					return false
			"exact":
				if v != (s.row["min"] as int):
					return false
	return true


## Every way of picking at most one set per slot with no die in two.
func _combine(options: Array, index: int, used: int, places: Array, out: Array) -> void:
	if index == options.size():
		out.append(places.duplicate())
		return
	_combine(options, index + 1, used, places, out)
	for option: Dictionary in options[index] as Array:
		if used & (option["mask"] as int):
			continue
		var more: Array = places.duplicate()
		for die_id: int in option["ids"] as Array:
			more.append([die_id, option["slot"]])
		_combine(options, index + 1, used | (option["mask"] as int), more, out)


func _apply(room: DiceRoom, plan: Dictionary) -> void:
	if plan["nudge"] as int >= 0:
		room.nudge(plan["nudge"] as int)
	for p: Array in plan["places"] as Array:
		room.place(p[0] as int, p[1] as String)


func _free_dice(room: DiceRoom) -> Array[int]:
	var out: Array[int] = []
	for d: DiceRoom.Die in room.hand:
		if d.is_free() and not d.locked:
			out.append(d.id)
	return out
