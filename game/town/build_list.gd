class_name BuildList
extends RefCounted
## The words for building (M3 PR 5b): the build list's rows, a building's
## card before it's placed, and what things cost, all read from the sim's
## refusals so the screen never re-derives a rule (specs/town.md section 3).
##
## Costs read "1 shell + 4 driftwood" (two-halves: actions are shells, not
## a count). Landmarks are free and wait at the top of the list once won.
## "No actions left" is said once, on the tray, never on a card.

const FREE: String = "Free"
const WAITING: String = "Won · waiting for a spot"
const ALL_BUILT: String = "All built"


## What building `building_id` costs, in shells and resources: "1 shell + 4
## driftwood", "1 shell + 3 driftwood + 1 pearl", or "Free".
static func cost_text(data: GameData, building_id: String) -> String:
	var row: Dictionary = data.row("buildings", building_id)
	var parts: PackedStringArray = []
	var actions: int = row["actions"]
	if actions > 0:
		parts.append("%d shell%s" % [actions, "" if actions == 1 else "s"])
	var cost: Dictionary = TownMap.parse_cost(row["cost"] as Array)
	for id: String in cost:
		parts.append("%d %s" % [cost[id], GameState.amount_name(data, id, cost[id])])
	return FREE if parts.is_empty() else " + ".join(parts)


## The build list's rows, in order: landmarks waiting for a spot first, then
## every other building in data order. Each row is {"id", "name", "cost",
## "status", "locked", "done"}: `locked` gets a padlock and is dimmed (an
## unlock rule), `done` is dimmed (all of them built), and `status` says why.
static func entries(data: GameData, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in state.landmarks_waiting():
		out.append({"id": id, "name": _name(data, id), "cost": FREE, "status": WAITING, "locked": false, "done": false})
	for id: String in data.ids("buildings"):
		if data.row("buildings", id)["kind"] == "landmark":
			continue
		var status: String = ""
		var locked: bool = false
		var done: bool = false
		for refusal: Dictionary in state.build_refusals(data, id):
			if refusal["kind"] == Town.Refusal.NOT_YET:
				locked = true
				status = refusal["text"]
			elif refusal["kind"] == Town.Refusal.ALL_BUILT and not locked:
				done = true
				status = ALL_BUILT
		out.append({"id": id, "name": _name(data, id), "cost": cost_text(data, id), "status": status,
			"locked": locked, "done": done})
	return out


## A building's card before it's placed: {"title", "lines", "can_place"}.
## The lines are what it does, what it costs, then every reason it can't be
## built yet but "No actions left" (that one's on the tray).
static func card_for(data: GameData, state: GameState, building_id: String) -> Dictionary:
	var row: Dictionary = data.row("buildings", building_id)
	var lines: PackedStringArray = [str(row.get("text", ""))]
	var refusals: Array[Dictionary] = state.build_refusals(data, building_id)
	if row["kind"] == "landmark":
		lines.append("Won in Koban's vault · free to place")
	else:
		lines.append("Costs " + cost_text(data, building_id))
	for refusal: Dictionary in refusals:
		if refusal["kind"] != Town.Refusal.NO_ACTIONS:
			lines.append(refusal["text"])
	return {"title": _name(data, building_id), "lines": lines, "can_place": refusals.is_empty()}


static func _name(data: GameData, id: String) -> String:
	return str(data.row("buildings", id).get("name", id))
