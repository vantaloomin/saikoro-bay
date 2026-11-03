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


func _init(seed_value: int = 0) -> void:
	campaign_seed = seed_value


# --- Delve flow ---------------------------------------------------------------

## Goes below the tide. Returns false if already in a delve.
func start_delve() -> bool:
	if phase != Phase.TOWN:
		return false
	delve_count += 1
	phase = Phase.DELVE
	return true


## Banks a delve and comes back up, in one step (delve-map spec 8a, rule
## 1): surfacing, clearing the vault, washing up and an abandoned delve all
## end here. `haul` is everything the delve carried; the outcome decides
## what's kept (Haul.kept). Villagers and landmarks already in town are
## never added twice. Returns false, changing nothing, if not in a delve or
## the outcome is unknown.
func finish_delve(outcome: String, haul: Haul) -> bool:
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
	return true


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
		"resources": resource_data,
		"seen_twists": _seen_twists.duplicate(),
		"villagers": _villagers.duplicate(),
		"landmarks": _landmarks.duplicate(),
		"last_delve": last_delve.duplicate(true),
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


## Builds a state from to_dict() output (after a JSON round trip).
## Returns null if anything is missing, negative or not a whole number.
## "seen_twists" is optional, so saves from before it existed still load.
## "villagers", "landmarks" and "last_delve" are required: version 2 saves
## always have them, and older saves get them from migrate_to_v2().
static func from_dict(data: Dictionary) -> GameState:
	var phase_name: Variant = data.get("phase")
	if not (phase_name is String and Phase.has(phase_name)):
		return null
	var seed_value: Variant = data.get("campaign_seed")
	var count: Variant = data.get("delve_count")
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

	var state: GameState = GameState.new(SaveCodec.to_int_or(seed_value, 0))
	state.phase = Phase[phase_name as String] as Phase
	state.delve_count = SaveCodec.to_int_or(count, 0)
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
