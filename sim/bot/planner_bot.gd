class_name PlannerBot
extends FightBot
## The ceiling: tries every legal way to place this turn's dice (and every
## Nudge), resolves each on a planning copy, and plays the best. Before
## committing, it weighs one reroll: keep the dice its best plan uses, spend
## the weakest leftover, and reroll the rest. It scores every possible
## result of that reroll (it never sees the real one) and rerolls only if
## the average beats the plan in hand.
##
## It can't see future turns, so it isn't perfect, but the gap between it
## and GreedyBot shows how much skill the fight rewards.


func name() -> String:
	return "planner"


func play_turn(fight: Fight) -> void:
	var plan: Dictionary = best_plan(fight, true)
	if fight.rerolls_left > 0:
		var reroll: Dictionary = _reroll_option(fight, plan)
		if not reroll.is_empty() and (reroll["expected"] as int) > (plan["score"] as int):
			_apply(fight, reroll["keep_plan"] as Dictionary)
			fight.reroll(reroll["discard"] as int)
			plan = best_plan(fight, true)
	_apply(fight, plan)


## The best placement from the fight's current state. Returns
## {"score", "nudge" (die id or -1), "places" (Array of [die, slot])}.
func best_plan(fight: Fight, allow_nudge: bool) -> Dictionary:
	var best: Dictionary = {}
	var nudges: Array[int] = [-1]
	if allow_nudge and fight.nudges_left > 0:
		for d: Fight.Die in fight.hand:
			if d.is_free() and not d.locked and d.value < d.max_face():
				nudges.append(d.id)
	for nudge_id: int in nudges:
		var base: Fight = fight.planning_copy()
		if nudge_id >= 0 and not base.nudge(nudge_id):
			continue
		var free: Array[int] = []
		for d: Fight.Die in base.hand:
			if d.is_free() and not d.locked:
				free.append(d.id)
		var found: Dictionary = _search(fight, base, free, 0, [])
		if best.is_empty() or (found["score"] as int) > (best["score"] as int):
			best = found
			best["nudge"] = nudge_id
	return best


## Depth-first over the free dice in id order: each goes in a slot (card
## order) or stays in hand. Ties keep the first plan found.
func _search(before: Fight, plan: Fight, free: Array[int], index: int, places: Array) -> Dictionary:
	if index == free.size():
		var resolved: Fight = plan.planning_copy()
		resolved.end_turn()
		return {"score": FightBot.score(before, resolved), "places": places.duplicate()}
	var die_id: int = free[index]
	var best: Dictionary = {}
	for s: Fight.Slot in plan.slots:
		if not plan.place(die_id, s.id):
			continue
		places.append([die_id, s.id])
		var found: Dictionary = _search(before, plan, free, index + 1, places)
		places.pop_back()
		plan.take_back(die_id)
		if best.is_empty() or (found["score"] as int) > (best["score"] as int):
			best = found
	var kept: Dictionary = _search(before, plan, free, index + 1, places)
	if best.is_empty() or (kept["score"] as int) > (best["score"] as int):
		best = kept
	return best


## The reroll worth weighing, or {} if there isn't one: keep the plan's
## placed dice, discard the lowest leftover, reroll the other leftovers.
## Returns {"expected", "discard", "keep_plan"}.
func _reroll_option(fight: Fight, plan: Dictionary) -> Dictionary:
	var used: Dictionary = {}
	for place: Variant in plan["places"] as Array:
		used[(place as Array)[0]] = true
	var leftovers: Array[Fight.Die] = []
	for d: Fight.Die in fight.hand:
		if d.is_free() and not d.locked and not used.has(d.id):
			leftovers.append(d)
	if leftovers.size() < 2:
		return {}
	var discard: Fight.Die = leftovers[0]
	for d: Fight.Die in leftovers:
		if d.value < discard.value:
			discard = d
	var rerolled: Array[Fight.Die] = []
	for d: Fight.Die in leftovers:
		if d != discard:
			rerolled.append(d)

	# Keep the plan's Nudge only if it lands on a die the plan places.
	var keep_plan: Dictionary = {"nudge": plan["nudge"] if used.has(plan["nudge"]) else -1, "places": plan["places"]}
	var kept: Fight = fight.planning_copy()
	_apply(kept, keep_plan)
	kept.hand[discard.id].discarded = true
	kept.rerolls_left -= 1

	var total_weight: int = 0
	var total_score: int = 0
	for outcome: Array in _outcomes(rerolled[0].faces, rerolled.size()):
		var trial: Fight = kept.planning_copy()
		var values: Array = outcome[0]
		for i: int in rerolled.size():
			trial.hand[rerolled[i].id].value = values[i] as int
		trial._apply_house_lock()
		var weight: int = outcome[1]
		total_weight += weight
		total_score += weight * (best_plan(trial, false)["score"] as int)
	return {"expected": total_score / maxi(total_weight, 1), "discard": discard.id, "keep_plan": keep_plan}


func _apply(fight: Fight, plan: Dictionary) -> void:
	var nudge_id: int = plan.get("nudge", -1)
	if nudge_id >= 0:
		fight.nudge(nudge_id)
	for place: Variant in plan["places"] as Array:
		fight.place((place as Array)[0] as int, (place as Array)[1] as String)


## Every multiset of `count` faces, as [values (ascending), how many ordered
## rolls give it]. Enumerating multisets instead of ordered rolls keeps
## three dice at 56 cases instead of 216.
static func _outcomes(faces: Array[int], count: int) -> Array[Array]:
	var out: Array[Array] = []
	_multisets(faces, count, 0, [], out)
	return out


static func _multisets(faces: Array[int], count: int, start: int, picked: Array, out: Array[Array]) -> void:
	if picked.size() == count:
		var tally: Dictionary = {}
		for v: Variant in picked:
			tally[v] = (tally.get(v, 0) as int) + 1
		var weight: int = _factorial(count)
		for v: Variant in tally:
			weight /= _factorial(tally[v] as int)
		out.append([picked.duplicate(), weight])
		return
	for i: int in range(start, faces.size()):
		picked.append(faces[i])
		_multisets(faces, count, i, picked, out)
		picked.pop_back()


static func _factorial(n: int) -> int:
	var f: int = 1
	for i: int in range(2, n + 1):
		f *= i
	return f
