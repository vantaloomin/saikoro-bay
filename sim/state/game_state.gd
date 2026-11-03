class_name GameState
extends RefCounted
## The campaign's saved progress: which half the player is in, how many
## delves they've started, and what they own.
##
## Saved only at half changes (between town and delve), never mid-delve in
## the slice. Every amount is an integer. Methods that change state return
## false and change nothing when the move isn't allowed, so a double click
## or a repeated signal can't apply it twice.

enum Phase { TOWN, DELVE }

## Key for this state inside the save payload.
const PAYLOAD_KEY: String = "game"

var phase: Phase = Phase.TOWN
## Fixed for the whole campaign. Each delve's seed is derived from it, so a
## whole playthrough can be replayed from one number.
var campaign_seed: int = 0
## Delves started so far. Also numbers the current delve while in one.
var delve_count: int = 0
## Times the current delve number was abandoned and retried. The retry has
## the same map but fresh rolls (DelveRun.run_seed). Back to 0 on a real
## outcome.
var delve_attempt: int = 0

var _resources: Dictionary[String, int] = {}
## Villagers living in town and landmarks rebuilt, in the order they came.
var _villagers: Array[String] = []
var _landmarks: Array[String] = []
## How the last delve ended, for the town to show on arrival:
## {"delve": n, "outcome": Haul outcome, "kept": Haul.to_dict()}, or {}.
var last_delve: Dictionary = {}
## Twists the player has met, so each gets its one-line banner only once
## per campaign (dice-fight-rules section 9). Sorted, for a stable save.
var _seen_twists: Array[String] = []
## The town's layout, homes and this visit's actions (save version 3).
var town: Town = Town.new()


func _init(seed_value: int = 0) -> void:
	campaign_seed = seed_value


# --- Delve flow ---------------------------------------------------------------

## Goes below the tide ("Go down", TC-7). In the same state change, up to
## keep_max unused actions are kept for the next visit and the rest are
## lost (TC-3), and the actions held now are noted for an abandoned delve.
## Returns false if already in a delve.
func start_delve(data: GameData) -> bool:
	if phase != Phase.TOWN:
		return false
	delve_count += 1
	phase = Phase.DELVE
	town.held_at_go_down = town.actions_left
	town.kept = mini(_town_row(data)["keep_max"] as int, town.actions_left)
	town.actions_left = 0
	return true


## Banks a delve and comes back up, in one step (delve-map spec 8a, rule
## 1): surfacing, clearing the vault, washing up and an abandoned delve all
## end here. `haul` is everything the delve carried; the outcome decides
## what's kept (Haul.kept). Villagers and landmarks already in town are
## never added twice. The whole arrival happens here, in this one state
## change: rescued villagers move into any free home (and PR 3's budget).
## Returns false, changing nothing, if not in a delve or the outcome is
## unknown.
func finish_delve(data: GameData, outcome: String, haul: Haul) -> bool:
	if phase != Phase.DELVE or not Haul.OUTCOMES.has(outcome):
		return false
	var kept: Haul = haul.kept(outcome)
	for id: String in kept.resources:
		add_resource(id, kept.resources[id])
	for villager: String in kept.villagers:
		if not _villagers.has(villager):
			_villagers.append(villager)
	if not kept.landmark.is_empty() and not _landmarks.has(kept.landmark):
		_landmarks.append(kept.landmark)
	last_delve = {"delve": delve_count, "outcome": outcome, "kept": kept.to_dict()}
	phase = Phase.TOWN
	if outcome == Haul.ABANDONED and not town.needs_budget:
		_undo_go_down()
	else:
		_set_budget(data)
		delve_attempt = 0
	settle_villagers(data)
	return true


## An abandoned delve counts as never having happened for time (Imogen's
## town review, option 1, pending Vanta): the actions held at "Go down"
## come back, and the next delve reuses this delve's number, so its seed
## and map. The haul is still lost. Quitting and reloading gains nothing.
func _undo_go_down() -> void:
	town.actions_left = town.held_at_go_down
	town.kept = mini(town.kept, town.actions_left)
	town.held_at_go_down = 0
	delve_count -= 1
	delve_attempt += 1


## The visit's budget (TC-1): base_actions plus the kept action, if any.
## `kept` then counts how many of actions_left came from the last visit;
## spending takes fresh actions first, so it's spent last.
func _set_budget(data: GameData) -> void:
	var town_row: Dictionary = _town_row(data)
	town.kept = mini(town.kept, town_row["keep_max"] as int)
	town.actions_left = (town_row["base_actions"] as int) + town.kept
	town.held_at_go_down = 0
	town.needs_budget = false


## Arrival for a town with no budget yet: a new campaign, or a save from
## before the town existed. Returns true if it set one. Coming up from a
## delve sets the budget inside finish_delve instead, so a visit gets
## exactly one.
func arrive(data: GameData) -> bool:
	if phase != Phase.TOWN or not town.needs_budget:
		return false
	_set_budget(data)
	settle_villagers(data)
	return true


## The "Go down" button's words, which say what's lost because controller
## and touch have no hover (spec section 1): "Go down · keep 1, 2 are lost".
func go_down_label(data: GameData) -> String:
	var keep: int = mini(_town_row(data)["keep_max"] as int, town.actions_left)
	var lost: int = town.actions_left - keep
	if keep == 0:
		return "Go down"
	if lost == 0:
		return "Go down · keep %d" % keep
	return "Go down · keep %d, %d %s lost" % [keep, lost, "is" if lost == 1 else "are"]


static func _town_row(data: GameData) -> Dictionary:
	return data.row("town", data.ids("town")[0])


## The seed for delve number `n` (1 for the first). Uses SHA-256 so it
## doesn't depend on the engine's random generator or integer overflow.
func delve_seed(n: int) -> int:
	var digest: String = ("saikoro-bay:delve:%d:%d" % [campaign_seed, n]).sha256_text()
	# 15 hex digits = 60 bits: always a positive int64.
	return digest.substr(0, 15).hex_to_int()


## The seed for the delve in progress (or the last one started).
func current_delve_seed() -> int:
	return delve_seed(delve_count)


# --- Town ------------------------------------------------------------------------

func villagers() -> Array[String]:
	return _villagers.duplicate()


func landmarks() -> Array[String]:
	return _landmarks.duplicate()


## Villagers still below the tide, in data order: the order they're rescued in.
func villagers_left(data: GameData) -> Array[String]:
	var out: Array[String] = []
	for id: String in data.ids("villagers"):
		if not _villagers.has(id):
			out.append(id)
	return out


func landmarks_left(data: GameData) -> Array[String]:
	var out: Array[String] = []
	for id: String in data.ids("landmarks"):
		if not _landmarks.has(id):
			out.append(id)
	return out


## The perks the next delve brings: one per villager in town, from
## data/villagers.json, sourced to that villager for the board's badges.
func delve_perks(data: GameData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _villagers:
		if data.has_row("villagers", id):
			out.append({"perk": data.row("villagers", id)["perk"], "source": id})
	return out


# --- Building (specs/town.md section 3) --------------------------------------------

static func town_map(data: GameData) -> TownMap:
	return TownMap.from_row(data.row("town", data.ids("town")[0]))


## Landmarks won in Koban's vault and not placed yet, in the order won:
## the tray's "Won · waiting for a spot".
func landmarks_waiting() -> Array[String]:
	return _landmarks.filter(func(id: String) -> bool: return town.count(id) == 0)


## Why `building_id` can't be built right now, or [] if it can (the spot
## aside). Each entry is {"kind": Town.Refusal, "text": String}, in the order
## a card lists them: the unlock (a padlock), the cap, every resource short,
## then actions. The card shows all of them; the tray shows NO_ACTIONS once.
func build_refusals(data: GameData, building_id: String) -> Array[Dictionary]:
	if not data.has_row("buildings", building_id):
		return [_refusal(Town.Refusal.NOT_YET, "Not a building")]
	var row: Dictionary = data.row("buildings", building_id)
	var out: Array[Dictionary] = []
	var locked: String = _locked_reason(data, row)
	if not locked.is_empty():
		out.append(_refusal(Town.Refusal.NOT_YET, locked))
	var cap: int = row["max_count"]
	if town.count(building_id) >= cap:
		var text: String = "You've built all %d" % cap if cap > 1 else "Already built"
		out.append(_refusal(Town.Refusal.ALL_BUILT, "Already placed" if row["kind"] == "landmark" else text))
	var cost: Dictionary = TownMap.parse_cost(row["cost"] as Array)
	for id: String in cost:
		var have: int = resource(id)
		if have < (cost[id] as int):
			var resource_row: Dictionary = data.row("resources", id)
			var text: String = "Needs %d more %s (you have %d)" % [(cost[id] as int) - have, resource_row.get("name", id), have]
			if not str(resource_row.get("found", "")).is_empty():
				text += " · " + str(resource_row["found"])
			out.append(_refusal(Town.Refusal.SHORT, text))
	if town.actions_left < (row["actions"] as int):
		out.append(_refusal(Town.Refusal.NO_ACTIONS, "No actions left"))
	return out


## Builds `building_id` with its top-left corner at `cell`: checks the
## unlock, the cap, the resources, the actions and the spot, then spends
## and places, all in this one call (Imogen's single spend path). Returns
## [] when built (the new building is town.placed.back()), or every reason
## it wasn't, having changed nothing.
func build(data: GameData, building_id: String, cell: Vector2i) -> Array[Dictionary]:
	var refusals: Array[Dictionary] = build_refusals(data, building_id)
	if refusals.is_empty():
		var spot: String = town.spot_problem(data, town_map(data), building_id, cell)
		if not spot.is_empty():
			refusals.append(_refusal(Town.Refusal.SPOT, spot))
	if not refusals.is_empty():
		return refusals
	var row: Dictionary = data.row("buildings", building_id)
	var cost: Dictionary = TownMap.parse_cost(row["cost"] as Array)
	for id: String in cost:
		spend_resource(id, cost[id])
	town.actions_left -= row["actions"] as int
	town.kept = mini(town.kept, town.actions_left)
	town.place(building_id, cell)
	if row["kind"] == "home":
		settle_villagers(data)
	return refusals


## Moves a placed building for free. Returns "" when it moved, or why not.
func move_building(data: GameData, uid: int, cell: Vector2i) -> String:
	return town.move(data, town_map(data), uid, cell)


# --- Homes and wishes (specs/town.md section 5) ---------------------------------------

## Moves villagers who have nowhere to live into free homes: first rescued
## into the first home built. Returns who moved in, for the walk there.
## Changes nothing when everyone is housed or there's no free home.
func settle_villagers(data: GameData) -> Array[String]:
	var moved: Array[String] = []
	for villager: String in _villagers:
		if town.homes.has(villager):
			continue
		for building: Dictionary in town.placed:
			if data.row("buildings", building["building"]).get("kind", "") == "home" \
					and town.resident(building["uid"]).is_empty():
				town.homes[villager] = building["uid"]
				moved.append(villager)
				break
	return moved


## Moves `villager` into home `uid` for free. Whoever lived there swaps
## into the villager's old home, or waits at the dock if the villager had
## none. One call: it moves both or neither. Returns "" when done, or why not.
func swap_home(data: GameData, villager: String, uid: int) -> String:
	if not _villagers.has(villager):
		return "Not in town"
	var target: Dictionary = town.entry(uid)
	if target.is_empty() or data.row("buildings", target["building"]).get("kind", "") != "home":
		return "Not a home"
	if town.homes.get(villager, 0) == uid:
		return "Already lives here"
	var other: String = town.resident(uid)
	if not other.is_empty():
		if town.homes.has(villager):
			town.homes[other] = town.homes[villager]
		else:
			town.homes.erase(other)
	town.homes[villager] = uid
	return ""


func mood(data: GameData, villager: String) -> Town.Mood:
	if not town.homes.has(villager):
		return Town.Mood.HOMELESS
	return Town.Mood.HAPPY if town.wish_met(data, town_map(data), villager) else Town.Mood.UNHAPPY


## Villagers in town with nowhere to live, in rescue order.
func homeless() -> Array[String]:
	return _villagers.filter(func(villager: String) -> bool: return not town.homes.has(villager))


## The HUD line for villagers with nowhere to live, or "" when all are housed.
func homeless_line(data: GameData) -> String:
	var names: Array[String] = []
	for villager: String in homeless():
		names.append(str(data.row("villagers", villager).get("role", villager)))
	match names.size():
		0:
			return ""
		1:
			return "The %s has nowhere to live" % names[0]
		2:
			return "The %s and the %s have nowhere to live" % names
	return "%d villagers have nowhere to live" % names.size()


## Unlock rules only ever open (spec section 4): placed buildings and
## villagers in town only grow, and nothing is demolished.
func _locked_reason(data: GameData, row: Dictionary) -> String:
	match row["unlock"]:
		"buildings_placed":
			var need: int = row["unlock_count"]
			if town.placed.size() < need:
				return "Needs %d buildings placed (you have %d)" % [need, town.placed.size()]
		"villager_in_town":
			var villager: String = row["unlock_villager"]
			if not _villagers.has(villager):
				return "The %s needs to live in town first" % data.row("villagers", villager).get("role", villager)
		"won":
			if not _landmarks.has(row["id"]):
				return "Win it in Koban's vault"
	return ""


static func _refusal(kind: Town.Refusal, text: String) -> Dictionary:
	return {"kind": kind, "text": text}


## What a loaded state gets wrong against this build's data (the town's
## layout and actions), or nothing. Game.load_or_new locks saving on any.
func town_problems(data: GameData) -> PackedStringArray:
	var out: PackedStringArray = town.problems(data, _villagers)
	if phase == Phase.TOWN and town.kept > town.actions_left:
		out.append("more actions kept than left")
	if phase == Phase.DELVE and town.actions_left != 0:
		out.append("actions left during a delve")
	for building: Dictionary in town.placed:
		if data.has_row("landmarks", building["building"]) and not _landmarks.has(building["building"]):
			out.append("landmark \"%s\" placed but never won" % building["building"])
	return out


# --- Resources ----------------------------------------------------------------

func resource(id: String) -> int:
	return _resources.get(id, 0)


func resources() -> Dictionary[String, int]:
	return _resources.duplicate()


## Adds a positive amount. Returns false for zero or negative amounts.
func add_resource(id: String, amount: int) -> bool:
	if amount <= 0 or id.is_empty():
		return false
	_resources[id] = resource(id) + amount
	return true


## Spends `amount` if the player has it all. Never goes below zero.
func spend_resource(id: String, amount: int) -> bool:
	if amount <= 0 or resource(id) < amount:
		return false
	_resources[id] = resource(id) - amount
	if _resources[id] == 0:
		_resources.erase(id)
	return true


# --- Twists --------------------------------------------------------------

func has_seen_twist(twist: String) -> bool:
	return _seen_twists.has(twist)


## Records the first meeting with `twist`. Returns true only that first
## time, so the caller shows the banner once. "none" and "" are not twists.
func meet_twist(twist: String) -> bool:
	if twist.is_empty() or twist == "none" or has_seen_twist(twist):
		return false
	_seen_twists.append(twist)
	_seen_twists.sort()
	return true


# --- Save ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	var resource_data: Dictionary = {}
	for id: String in _resources:
		resource_data[id] = _resources[id]
	return {
		"phase": Phase.keys()[phase],
		"campaign_seed": str(campaign_seed),
		"delve_count": delve_count,
		"delve_attempt": delve_attempt,
		"resources": resource_data,
		"seen_twists": _seen_twists.duplicate(),
		"villagers": _villagers.duplicate(),
		"landmarks": _landmarks.duplicate(),
		"last_delve": last_delve.duplicate(true),
		"town": town.to_dict(),
	}


## Save version 1 -> 2: adds villagers, landmarks and the last delve's
## result, all empty, since no delve could bank any before version 2.
static func migrate_to_v2(payload: Dictionary) -> Dictionary:
	if not payload.get(PAYLOAD_KEY) is Dictionary:
		return payload
	var game: Dictionary = payload[PAYLOAD_KEY]
	game["villagers"] = []
	game["landmarks"] = []
	game["last_delve"] = {}
	return payload


## Save version 2 -> 3: adds the town. It starts empty with its budget
## still to set (Imogen's town review): landmarks a v2 save already won
## stay won and wait in the tray unplaced, and rescued villagers wait at the
## dock until there's a Cottage.
static func migrate_to_v3(payload: Dictionary) -> Dictionary:
	if not payload.get(PAYLOAD_KEY) is Dictionary:
		return payload
	(payload[PAYLOAD_KEY] as Dictionary)["town"] = Town.new().to_dict()
	(payload[PAYLOAD_KEY] as Dictionary)["delve_attempt"] = 0
	return payload


## Builds a state from to_dict() output (after a JSON round trip).
## Returns null if anything is missing, negative or not a whole number.
## "seen_twists" is optional, so saves from before it existed still load.
## "villagers", "landmarks" and "last_delve" are required: version 2 saves
## always have them, and older saves get them from migrate_to_v2().
## "town" and "delve_attempt" are required too (version 3, or
## migrate_to_v3()). Checks against the data, like whether buildings fit
## the map, are in town_problems().
static func from_dict(data: Dictionary) -> GameState:
	var phase_name: Variant = data.get("phase")
	if not (phase_name is String and Phase.has(phase_name)):
		return null
	var seed_value: Variant = data.get("campaign_seed")
	var count: Variant = data.get("delve_count")
	var attempt: Variant = data.get("delve_attempt")
	if not SaveCodec.is_int_like(attempt) or SaveCodec.to_int_or(attempt, -1) < 0:
		return null
	var resource_data: Variant = data.get("resources", {})
	if not SaveCodec.is_int_like(seed_value) or not seed_value is String:
		return null
	if not SaveCodec.is_int_like(count) or SaveCodec.to_int_or(count, -1) < 0:
		return null
	if not resource_data is Dictionary:
		return null
	var twist_data: Variant = data.get("seen_twists", [])
	if not twist_data is Array:
		return null
	var villager_data: Variant = data.get("villagers")
	var landmark_data: Variant = data.get("landmarks")
	var last_data: Variant = data.get("last_delve")
	if not _is_id_list(villager_data) or not _is_id_list(landmark_data):
		return null
	var last: Variant = _read_last_delve(last_data)
	if last == null:
		return null
	var town_state: Town = Town.from_dict(data.get("town"))
	if town_state == null:
		return null

	var state: GameState = GameState.new(SaveCodec.to_int_or(seed_value, 0))
	state.phase = Phase[phase_name as String] as Phase
	state.delve_count = SaveCodec.to_int_or(count, 0)
	state.delve_attempt = SaveCodec.to_int_or(attempt, 0)
	if state.phase == Phase.DELVE and state.delve_count < 1:
		return null
	for id: Variant in resource_data as Dictionary:
		var amount: Variant = (resource_data as Dictionary)[id]
		if not id is String or not SaveCodec.is_int_like(amount):
			return null
		var value: int = SaveCodec.to_int_or(amount, -1)
		if value < 0:
			return null
		if value > 0:
			state._resources[id as String] = value
	# Replayed through meet_twist on purpose: duplicates, "" and "none" are
	# dropped quietly, and the list comes back sorted.
	for twist: Variant in twist_data as Array:
		if not twist is String:
			return null
		state.meet_twist(twist as String)
	for id: Variant in villager_data as Array:
		if not state._villagers.has(id as String):
			state._villagers.append(id as String)
	for id: Variant in landmark_data as Array:
		if not state._landmarks.has(id as String):
			state._landmarks.append(id as String)
	state.last_delve = last
	state.town = town_state
	return state


## The saved last_delve with whole numbers as ints, {} for none, or null
## if it's malformed.
static func _read_last_delve(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if data.is_empty():
		return {}
	var kept_data: Variant = data.get("kept")
	if not SaveCodec.is_int_like(data.get("delve")) or not Haul.OUTCOMES.has(str(data.get("outcome", ""))) \
			or not kept_data is Dictionary:
		return null
	var kept: Dictionary = kept_data
	var resource_data: Variant = kept.get("resources")
	if not resource_data is Dictionary or not _is_id_list(kept.get("villagers")) or not kept.get("landmark") is String:
		return null
	var resources_out: Dictionary = {}
	for id: Variant in resource_data as Dictionary:
		var amount: int = SaveCodec.to_int_or((resource_data as Dictionary)[id], -1)
		if not id is String or amount < 0:
			return null
		resources_out[id] = amount
	return {
		"delve": SaveCodec.to_int_or(data["delve"], 0),
		"outcome": str(data["outcome"]),
		"kept": {"resources": resources_out, "villagers": (kept["villagers"] as Array).duplicate(), "landmark": kept["landmark"]},
	}


static func _is_id_list(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value as Array:
		if not item is String or (item as String).is_empty():
			return false
	return true
