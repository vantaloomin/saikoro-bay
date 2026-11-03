class_name RoomBot
extends RefCounted
## Plays a treasure, rest or rescue room (DiceRoom) through the same moves
## the board uses, the way a careful new player might.
##
## Each turn it tries every way of putting the free dice into the open
## slots (and leaving some out), with or without one nudge, on planning
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
	value += (after.open_count() - before.open_count()) * OPEN_SCORE
	value += (after.hp - before.hp) * HEAL_WORTH
	for id: String in after.payout:
		value += (after.payout[id] - before.payout.get(id, 0)) * RESOURCE_WORTH.get(id, 1)
	return value


func _best_placement(room: DiceRoom, nudged: int) -> Dictionary:
	var dice: Array[int] = _free_dice(room)
	var targets: Array[String] = []
	for s: DiceRoom.Slot in room.slots:
		if not s.sealed:
			targets.append(s.id)
	var best: Dictionary = {"score": -WIN_SCORE - 1, "nudge": nudged, "places": []}
	var best_used: int = 0
	# Each die goes to one of the targets or stays out (the last choice).
	var choice: Array[int] = []
	choice.resize(dice.size())
	choice.fill(targets.size())
	var combos: int = int(pow(targets.size() + 1, dice.size()))
	for n: int in combos:
		var rest: int = n
		for i: int in dice.size():
			choice[i] = rest % (targets.size() + 1)
			rest /= targets.size() + 1
		var places: Array = []
		for i: int in dice.size():
			if choice[i] < targets.size():
				places.append([dice[i], targets[choice[i]]])
		var trial: DiceRoom = room.planning_copy()
		var ok: bool = true
		for p: Array in places:
			if not trial.place(p[0] as int, p[1] as String):
				ok = false
				break
		if not ok:
			continue
		trial.end_turn()
		var value: int = score(room, trial)
		if value > best["score"] or (value == best["score"] and places.size() < best_used):
			best = {"score": value, "nudge": nudged, "places": places}
			best_used = places.size()
	return best


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
