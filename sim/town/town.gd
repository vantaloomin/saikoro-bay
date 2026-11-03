class_name Town
extends RefCounted
## The town's saved layout and this visit's actions (specs/town.md sections
## 2 to 5): which buildings stand where, who lives in which home, and how
## many actions are left.
##
## Build, move and swap are each one call that checks and changes together,
## and screens read refusal reasons from here, never re-deriving them.
## Spending lives in GameState.build, because resources are kept there.
## Happiness and locked reasons are derived from the layout, never saved.
## Nothing here draws from an RNG.

## What a refusal is about, so a screen can show a padlock for NOT_YET, a
## gap for SHORT, and "No actions left" once on the tray.
enum Refusal { NOT_YET, ALL_BUILT, SHORT, NO_ACTIONS, SPOT }

## Standing buildings in build order: {"uid": int, "building": id, "x": int, "y": int}.
var placed: Array[Dictionary] = []
## The uid the next building gets. Uids are never reused.
var next_uid: int = 1
## Villager id -> uid of the home they live in. Villagers in town without
## an entry wait at the dock.
var homes: Dictionary[String, int] = {}
## Actions left this visit, kept one included.
var actions_left: int = 0
## How many of actions_left were kept from the last visit (drawn as a pearl).
var kept: int = 0
## The actions held at "Go down", for the abandoned-delve rule (PR 3).
var held_at_go_down: int = 0
## True until this visit's budget is set: a new campaign, or a save from
## before the town existed. Arrival sets it, once.
var needs_budget: bool = true


# --- Reading the layout ---------------------------------------------------------

func entry(uid: int) -> Dictionary:
	for building: Dictionary in placed:
		if building["uid"] == uid:
			return building
	return {}


## How many of `building_id` stand in town.
func count(building_id: String) -> int:
	return placed.filter(func(building: Dictionary) -> bool: return building["building"] == building_id).size()


static func footprint(data: GameData, building_id: String, cell: Vector2i) -> Rect2i:
	var row: Dictionary = data.row("buildings", building_id)
	return Rect2i(cell, Vector2i(row.get("width", 1), row.get("height", 1)))


static func rect_of(data: GameData, building: Dictionary) -> Rect2i:
	return footprint(data, building["building"], Vector2i(building["x"], building["y"]))


## The placed building covering `cell`, or {}.
func building_at(data: GameData, cell: Vector2i) -> Dictionary:
	for building: Dictionary in placed:
		if rect_of(data, building).has_point(cell):
			return building
	return {}


## Why `building_id` can't stand with its top-left corner at `cell`, or ""
## if it can. `lifted_uid` is a building being moved: its own cells count
## as free. The same text the carry ghost shows (spec section 2).
func spot_problem(data: GameData, map: TownMap, building_id: String, cell: Vector2i, lifted_uid: int = 0) -> String:
	if not map.in_bounds(cell):
		return "Off the map"
	match map.ground(cell):
		TownMap.Ground.SEA:
			return "In the sea"
		TownMap.Ground.PATH:
			return "On a path"
	var lot: Rect2i = map.lots[map.lot_index(cell)]
	var rect: Rect2i = footprint(data, building_id, cell)
	if not lot.encloses(rect):
		return "Too big for this lot" if rect.size.x > lot.size.x or rect.size.y > lot.size.y else "Runs off the lot"
	for building: Dictionary in placed:
		if building["uid"] != lifted_uid and rect_of(data, building).intersects(rect):
			return "Something's already here"
	return ""


# --- Changing the layout ----------------------------------------------------------

## Stands a building on a spot already checked by the caller. Returns its uid.
func place(building_id: String, cell: Vector2i) -> int:
	var uid: int = next_uid
	next_uid += 1
	placed.append({"uid": uid, "building": building_id, "x": cell.x, "y": cell.y})
	return uid


## Moves a placed building (free, TB-3). Checked with the building lifted,
## so it can shift onto its own old cells. Returns "" when it moved, or why
## not, changing nothing. Homes go with the building: whoever lives there
## still does, so a move can break a wish but never makes anyone homeless.
func move(data: GameData, map: TownMap, uid: int, cell: Vector2i) -> String:
	var building: Dictionary = entry(uid)
	if building.is_empty():
		return "Nothing to move"
	var problem: String = spot_problem(data, map, building["building"], cell, uid)
	if problem.is_empty():
		building["x"] = cell.x
		building["y"] = cell.y
	return problem


# --- Checking a loaded town against the data ------------------------------------------

## Everything a town read from a save gets wrong against this build's data,
## or nothing. A save with problems takes the #22 lock path: it's kept, not
## replaced. `villagers` are the ones in town.
func problems(data: GameData, villagers: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	var town_row: Dictionary = data.row("town", data.ids("town")[0]) if data.ids("town").size() == 1 else {}
	if town_row.is_empty():
		return PackedStringArray(["the data has no town"])
	var map: TownMap = TownMap.from_row(town_row)
	var keep_max: int = town_row["keep_max"]
	var most: int = (town_row["base_actions"] as int) + keep_max
	if actions_left > most or held_at_go_down > most or kept > keep_max or kept > actions_left:
		out.append("actions out of range")
	var counts: Dictionary[String, int] = {}
	var standing: Array[Dictionary] = []
	for building: Dictionary in placed:
		var id: String = building["building"]
		if not data.has_row("buildings", id):
			out.append("unknown building \"%s\"" % id)
			continue
		counts[id] = counts.get(id, 0) + 1
		if counts[id] > (data.row("buildings", id)["max_count"] as int):
			out.append("more than max_count of \"%s\"" % id)
		var others: Town = Town.new()
		others.placed = standing
		var problem: String = others.spot_problem(data, map, id, Vector2i(building["x"], building["y"]))
		if not problem.is_empty():
			out.append("building %d: %s" % [building["uid"], problem])
		standing.append(building)
	var lived_in: Dictionary[int, String] = {}
	for villager: String in homes:
		var home: Dictionary = entry(homes[villager])
		if not villagers.has(villager):
			out.append("\"%s\" has a home but isn't in town" % villager)
		if home.is_empty() or not data.has_row("buildings", home["building"]) \
				or data.row("buildings", home["building"])["kind"] != "home":
			out.append("\"%s\" lives in something that isn't a home" % villager)
		elif lived_in.has(homes[villager]):
			out.append("two villagers share home %d" % homes[villager])
		lived_in[homes[villager]] = villager
	return out


# --- Save ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var home_data: Dictionary = {}
	for villager: String in homes:
		home_data[villager] = homes[villager]
	return {
		"placed": placed.duplicate(true),
		"next_uid": next_uid,
		"homes": home_data,
		"actions_left": actions_left,
		"kept": kept,
		"held_at_go_down": held_at_go_down,
		"needs_budget": needs_budget,
	}


## Builds a town from to_dict() output (after a JSON round trip). Checks
## shapes only: whole numbers, no negatives, unique uids below next_uid,
## homes pointing at placed uids. `problems()` checks it against the data.
## Returns null if anything is off.
static func from_dict(value: Variant) -> Town:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	var placed_data: Variant = data.get("placed")
	var home_data: Variant = data.get("homes")
	if not placed_data is Array or not home_data is Dictionary or not data.get("needs_budget") is bool:
		return null
	var town: Town = Town.new()
	var numbers: Array[int] = []
	for key: String in ["next_uid", "actions_left", "kept", "held_at_go_down"]:
		if not SaveCodec.is_int_like(data.get(key)) or SaveCodec.to_int_or(data.get(key), -1) < 0:
			return null
		numbers.append(SaveCodec.to_int_or(data[key], 0))
	town.next_uid = numbers[0]
	town.actions_left = numbers[1]
	town.kept = numbers[2]
	town.held_at_go_down = numbers[3]
	town.needs_budget = data["needs_budget"]
	if town.next_uid < 1:
		return null
	for item: Variant in placed_data as Array:
		if not item is Dictionary:
			return null
		var building: Dictionary = item
		var id: Variant = building.get("building")
		if not id is String or (id as String).is_empty():
			return null
		var ints: Array[int] = []
		for key: String in ["uid", "x", "y"]:
			if not SaveCodec.is_int_like(building.get(key)) or SaveCodec.to_int_or(building.get(key), -1) < 0:
				return null
			ints.append(SaveCodec.to_int_or(building[key], 0))
		if ints[0] < 1 or ints[0] >= town.next_uid or not town.entry(ints[0]).is_empty():
			return null
		town.placed.append({"uid": ints[0], "building": id, "x": ints[1], "y": ints[2]})
	for villager: Variant in home_data as Dictionary:
		var uid: Variant = (home_data as Dictionary)[villager]
		if not villager is String or (villager as String).is_empty() or not SaveCodec.is_int_like(uid):
			return null
		if town.entry(SaveCodec.to_int_or(uid, 0)).is_empty():
			return null
		town.homes[villager as String] = SaveCodec.to_int_or(uid, 0)
	return town
