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
const BUILT: String = "Built"
const ALL_BUILT: String = "All %d built"


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


## The build list's rows, in order (Mara's #42 review): landmarks waiting
## for a spot, then what you can build now, then what's short on
## resources or actions, then what's locked, then what's all built. Each
## row is {"id", "name", "cost", "status", "can_place", "locked", "done"}:
## `locked` gets a padlock (an unlock rule), and `status` says why a row
## can't be built.
static func entries(data: GameData, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in state.landmarks_waiting():
		out.append({"id": id, "name": _name(data, id), "cost": FREE, "status": WAITING, "can_place": true,
			"locked": false, "done": false})
	var groups: Array[Array] = [[], [], [], []]
	for id: String in data.ids("buildings"):
		var row: Dictionary = data.row("buildings", id)
		if row["kind"] == "landmark":
			continue
		var refusals: Array[Dictionary] = state.build_refusals(data, id)
		var kinds: Array = refusals.map(func(refusal: Dictionary) -> Town.Refusal: return refusal["kind"])
		var entry: Dictionary = {"id": id, "name": _name(data, id), "cost": cost_text(data, id), "status": "",
			"can_place": refusals.is_empty(), "locked": kinds.has(Town.Refusal.NOT_YET), "done": false}
		if entry["locked"]:
			entry["status"] = refusals[kinds.find(Town.Refusal.NOT_YET)]["text"]
			groups[2].append(entry)
		elif kinds.has(Town.Refusal.ALL_BUILT):
			entry["done"] = true
			var cap: int = row["max_count"]
			entry["status"] = BUILT if cap == 1 else ALL_BUILT % cap
			groups[3].append(entry)
		else:
			groups[0 if entry["can_place"] else 1].append(entry)
	for group: Array in groups:
		for entry: Dictionary in group:
			out.append(entry)
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
