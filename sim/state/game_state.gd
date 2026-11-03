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


## Comes back up. Returns false if not in a delve.
func end_delve() -> bool:
	if phase != Phase.DELVE:
		return false
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
	}


## Builds a state from to_dict() output (after a JSON round trip).
## Returns null if anything is missing, negative or not a whole number.
## "seen_twists" is optional, so saves from before it existed still load.
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
	for twist: Variant in twist_data as Array:
		if not twist is String:
			return null
		state.meet_twist(twist as String)
	return state
