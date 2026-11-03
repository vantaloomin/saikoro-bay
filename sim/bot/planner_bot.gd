class_name PlannerBot
extends FightBot
## The ceiling: tries every legal way to place this turn's dice (and every
## Nudge), resolves each on a planning copy, and plays the best. Before
## committing, it weighs one reroll: keep the dice its best plan uses, spend
## the weakest leftover, and reroll the rest. It scores every possible
## result of that reroll (it never sees the real one) and rerolls only if
## the average beats the plan in hand.
##
## With Slow pour in the kit there's no discard reroll; it weighs a pour
## the same way (keep the plan's dice placed, pour the rest) when three
## dice or fewer would roll, so the weighing stays small.
##
## It plays like a strong player, not a perfect one: it looks one turn
## ahead and weighs one keep set per reroll. The gap between it and
## GreedyBot shows how much skill the fight rewards.


## Most dice a pour it weighs may roll.
const POUR_DICE: int = 3


func name() -> String:
	return "planner"


func play_turn(fight: Fight) -> void:
	var plan: Dictionary = best_plan(fight, true)
	if fight.rerolls_left > 0:
		var reroll: Dictionary = _reroll_option(fight, plan)
		if not reroll.is_empty() and (reroll["total_score"] as int) > (plan["score"] as int) * (reroll["total_weight"] as int):
			_apply(fight, reroll["keep_plan"] as Dictionary)
			fight.reroll(reroll["discard"] as int)
			plan = best_plan(fight, true)
	elif fight.pour_refusal().is_empty():
		var pour: Dictionary = _reroll_option(fight, plan, true)
		if not pour.is_empty() and (pour["total_score"] as int) > (plan["score"] as int) * (pour["total_weight"] as int):
			_apply(fight, pour["keep_plan"] as Dictionary)
			fight.pour()
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
## A pour discards nothing and rerolls every leftover (at most POUR_DICE).
## Returns {"total_score", "total_weight", "discard", "keep_plan"}: the
## expected score is total_score / total_weight, compared without dividing.
func _reroll_option(fight: Fight, plan: Dictionary, pour: bool = false) -> Dictionary:
	var used: Dictionary = {}
	for place: Variant in plan["places"] as Array:
		used[(place as Array)[0]] = true
	var leftovers: Array[Fight.Die] = []
	for d: Fight.Die in fight.hand:
		if d.is_free() and not d.locked and not used.has(d.id):
			leftovers.append(d)
	if leftovers.size() < (1 if pour else 2) or (pour and leftovers.size() > POUR_DICE):
		return {}
	var discard: Fight.Die = null
	if not pour:
		discard = leftovers[0]
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
	if pour:
		kept.table.pours_left -= 1
	else:
		kept.hand[discard.id].discarded = true
		kept.rerolls_left -= 1

	var total_weight: int = 0
	var total_score: int = 0
	var faces: Array[Array] = []
	for d: Fight.Die in rerolled:
		faces.append(d.faces)
	for outcome: Array in _outcomes(faces):
		var trial: Fight = kept.planning_copy()
		var values: Array = outcome[0]
		for i: int in rerolled.size():
			trial.hand[rerolled[i].id].value = values[i] as int
		trial.table.apply_lock()
		var weight: int = outcome[1]
		total_weight += weight
		total_score += weight * (best_plan(trial, true)["score"] as int)
	return {"total_score": total_score, "total_weight": total_weight, "discard": -1 if pour else discard.id,
		"keep_plan": keep_plan}


func _apply(fight: Fight, plan: Dictionary) -> void:
	var nudge_id: int = plan.get("nudge", -1)
	if nudge_id >= 0:
		fight.nudge(nudge_id)
	for place: Variant in plan["places"] as Array:
		fight.place((place as Array)[0] as int, (place as Array)[1] as String)


## Every result of rerolling dice with these faces (one list per die), as
## [values, how many ordered rolls give it]. When every die has the same
## faces, results are multisets assigned to the dice in ascending order,
## which keeps three dice at 56 cases instead of 216. Dice with different
## faces (KP-3) are enumerated one ordered roll at a time.
static func _outcomes(faces: Array[Array]) -> Array[Array]:
	var out: Array[Array] = []
	var same: bool = true
	for f: Array in faces:
		if f != faces[0]:
			same = false
	if same and not faces.is_empty():
		var first: Array[int] = []
		first.assign(faces[0])
		_multisets(first, faces.size(), 0, [], out)
	else:
		_products(faces, 0, [], out)
	return out


static func _products(faces: Array[Array], index: int, picked: Array, out: Array[Array]) -> void:
	if index == faces.size():
		out.append([picked.duplicate(), 1])
		return
	for v: Variant in faces[index]:
		picked.append(v)
		_products(faces, index + 1, picked, out)
		picked.pop_back()


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
