class_name Affection
extends RefCounted
## Affection milestones (PRD RD-5, RD-7), read from data/affection.json.
##
## Affection is a whole number per villager that only ever rises (RD-6:
## nothing decays while you're busy or delving). Milestones are points on
## that line, in rising order; reaching one is permanent. A milestone with
## unlock "scene" opens that villager's private scene.


## Milestone rows in rising order of points.
static func milestones(data: GameData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in data.ids("affection"):
		out.append(data.row("affection", id))
	return out


## The highest milestone reached at `points`, or {} below the first.
static func reached(data: GameData, points: int) -> Dictionary:
	var best: Dictionary = {}
	for milestone: Dictionary in milestones(data):
		if points >= (milestone["points"] as int):
			best = milestone
	return best


## The next milestone above `points`, or {} once every one is reached:
## what the villager card points to ("Close at 3 · unlocks their scene").
static func next(data: GameData, points: int) -> Dictionary:
	for milestone: Dictionary in milestones(data):
		if points < (milestone["points"] as int):
			return milestone
	return {}


## Whether `points` has reached a milestone that unlocks the scene.
static func scene_unlocked(data: GameData, points: int) -> bool:
	for milestone: Dictionary in milestones(data):
		if milestone["unlock"] == "scene" and points >= (milestone["points"] as int):
			return true
	return false


## The meter's end: the last milestone's points (the bar is full there).
static func top(data: GameData) -> int:
	var all: Array[Dictionary] = milestones(data)
	return 0 if all.is_empty() else all.back()["points"] as int
