extends Node
## The running campaign: its GameState, its save slot, and the two moves
## between halves.
##
## Autoload "Game". Saves happen only at half changes, before the transition
## starts: going down saves the delve as started (so reloading can't reroll
## a delve), and coming up saves the town. SceneFlow blocks saving while the
## transition runs.

signal save_failed(error: Error)
## A delve began (after the save, as the tide starts rising).
signal delve_started(number: int, seed_value: int)
## The player left delve `number` for town.
signal returned_to_town(number: int)

const TOWN_SCENE: String = "res://game/town/town.tscn"
const DELVE_SCENE: String = "res://game/delve/delve.tscn"
const DEFAULT_SAVE_PATH: String = "user://saves/slot_1.save"

## Villagers, perks, rooms... from data/*.json.
var data: GameData = GameData.load_dir()
var state: GameState = GameState.new()
var store: SaveStore:
	set(value):
		if store != null and store.deferred_write_finished.is_connected(_on_deferred_write_finished):
			store.deferred_write_finished.disconnect(_on_deferred_write_finished)
		store = value
		if store != null:
			store.deferred_write_finished.connect(_on_deferred_write_finished)
## True when the slot holds a save from a newer version. Nothing is saved
## then, so an old build can't overwrite newer progress.
var saving_locked: bool = false


func _init() -> void:
	store = SaveStore.new(DEFAULT_SAVE_PATH)


func _ready() -> void:
	for error: String in data.errors:
		push_error("Game data: " + error)
	SceneFlow.transition_started.connect(_on_transition_started)
	SceneFlow.transition_finished.connect(_on_transition_finished)


## Loads the slot, or starts a new campaign if it's empty or unreadable.
## Returns the scene the player should land in.
##
## A save still in the DELVE phase means the game closed mid-delve. For now
## that resumes at the start of the same delve (same seed). Once failure
## exists (M2), it will count as an abandoned delve that washes up in the
## barrel, so quitting can't be used to retry a bad delve.
func load_or_new() -> String:
	var result: SaveStore.ReadResult = store.read()
	saving_locked = result.status == SaveCodec.Status.TOO_NEW
	var loaded: GameState = null
	if result.is_ok():
		loaded = GameState.from_dict(result.payload.get(GameState.PAYLOAD_KEY, {}) as Dictionary)
	if loaded == null:
		if result.status != SaveCodec.Status.EMPTY:
			push_warning("Save slot unreadable (%s); starting a new campaign." % SaveCodec.Status.keys()[result.status])
		state = GameState.new(_new_campaign_seed())
	else:
		state = loaded
	return scene_for_phase()


func scene_for_phase() -> String:
	return DELVE_SCENE if state.phase == GameState.Phase.DELVE else TOWN_SCENE


## "Go down" (TC-7). Returns false if it's not allowed right now.
func go_down() -> bool:
	if SceneFlow.busy or not state.start_delve():
		return false
	save()
	delve_started.emit(state.delve_count, state.current_delve_seed())
	SceneFlow.change_half(DELVE_SCENE, TideTransition.Direction.DOWN)
	return true


## Leave the delve for town. Returns false if it's not allowed right now.
func come_up() -> bool:
	if SceneFlow.busy or not state.end_delve():
		return false
	save()
	returned_to_town.emit(state.delve_count)
	SceneFlow.change_half(TOWN_SCENE, TideTransition.Direction.UP)
	return true


## Writes the slot. Returns the store's error code. ERR_BUSY means the
## write is held until the transition ends, and then captures the state as
## it is at that point. That isn't a failure.
func save() -> Error:
	if saving_locked:
		return ERR_UNAUTHORIZED
	var error: Error = store.write_when_ready(_build_payload)
	if error != OK and error != ERR_BUSY:
		push_warning("Save failed: %s" % error_string(error))
		save_failed.emit(error)
	return error


func _build_payload() -> Dictionary:
	return {GameState.PAYLOAD_KEY: state.to_dict()}


func _on_transition_started(_direction: TideTransition.Direction) -> void:
	store.blocked = true


func _on_transition_finished(_direction: TideTransition.Direction) -> void:
	store.blocked = false


func _on_deferred_write_finished(error: Error) -> void:
	if error != OK:
		push_warning("Held save failed: %s" % error_string(error))
		save_failed.emit(error)


## A fresh campaign seed. This is the one place randomness comes from
## outside the seeded streams.
static func _new_campaign_seed() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return (rng.randi() << 32) | rng.randi()
