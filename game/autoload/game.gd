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
## load_or_new has the campaign (or the test town) in place.
signal campaign_loaded

const TOWN_SCENE: String = "res://game/town/town.tscn"
const DELVE_SCENE: String = "res://game/delve/delve.tscn"
const DEFAULT_SAVE_PATH: String = "user://saves/slot_1.save"

## Villagers, perks, rooms... from data/*.json.
var data: GameData = GameData.load_dir()
var state: GameState = GameState.new()
## The delve in progress, built when you go down, or null in town.
var run: DelveRun
var store: SaveStore:
	set(value):
		if store != null and store.deferred_write_finished.is_connected(_on_deferred_write_finished):
			store.deferred_write_finished.disconnect(_on_deferred_write_finished)
		store = value
		if store != null:
			store.deferred_write_finished.connect(_on_deferred_write_finished)
## True when the slot holds a save this build can't load: one from a newer
## version, or one that decodes but doesn't load. Nothing is saved then,
## so this build can't overwrite progress it can't read.
var saving_locked: bool = false
## Why saving is off or the last save failed, for the town to show, or "".
var save_problem: String = ""
## True while playing the M3 exit check's test town (FakeTown), so the
## notice board and the playtest log can say so.
var fake_town: bool = false


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
## A save still in the DELVE phase means the game closed mid-delve. That's
## an abandoned delve (Imogen's #6 audit): it washes up in the barrel with
## nothing kept, it's saved at once, and the town shows it. So quitting
## can't be used to retry a bad delve.
func load_or_new(test_town: bool = FakeTown.requested()) -> String:
	fake_town = test_town
	if test_town:
		var scene: String = _start_fake_town()
		campaign_loaded.emit()
		return scene
	var result: SaveStore.ReadResult = store.read()
	saving_locked = result.status == SaveCodec.Status.TOO_NEW
	save_problem = "Saving is off: your save is from a newer version of the game." if saving_locked else ""
	var loaded: GameState = null
	if result.is_ok():
		loaded = GameState.from_dict(result.payload.get(GameState.PAYLOAD_KEY, {}) as Dictionary)
		if loaded != null and not loaded.town_problems(data).is_empty():
			push_error("Saved town doesn't match this build's data: " + ", ".join(loaded.town_problems(data)))
			loaded = null
		if loaded == null:
			# It passed its checksum but doesn't load: a bug, not a damaged
			# file. Keep every copy and save nothing, so the campaign survives
			# for a build that can read it.
			push_error("Save slot decodes but doesn't load; saving is off and the files are kept.")
			_keep_unloadable_copies()
			saving_locked = true
			save_problem = "Saving is off: this build can't read your save. It's kept safe for a fixed build."
	if loaded == null:
		if result.status != SaveCodec.Status.EMPTY:
			push_warning("Save slot unreadable (%s); starting a new campaign." % SaveCodec.Status.keys()[result.status])
		state = GameState.new(_new_campaign_seed())
		state.arrive(data)
	else:
		# Load order (Imogen): the codec has migrated already, then an
		# abandoned delve is converted, then arrival. One budget, never two.
		state = loaded
		if state.phase == GameState.Phase.DELVE:
			state.finish_delve(data, Haul.ABANDONED, Haul.new())
			save()
		elif state.arrive(data):
			save()
	campaign_loaded.emit()
	return scene_for_phase()


## The M3 exit check's town (FakeTown): its own slot, fresh every launch.
func _start_fake_town() -> String:
	store = SaveStore.new(FakeTown.SAVE_PATH)
	saving_locked = false
	state = FakeTown.build(data)
	if state == null:
		push_error("FakeTown: a sim move refused; starting a plain new campaign.")
		state = GameState.new(_new_campaign_seed())
		state.arrive(data)
	save()
	return scene_for_phase()


func scene_for_phase() -> String:
	return DELVE_SCENE if state.phase == GameState.Phase.DELVE else TOWN_SCENE


## Copies every file of the slot aside as <name>.unloadable-<time>, so even
## a later save can't rotate them away. A file already copied (same bytes)
## isn't copied again, so relaunching doesn't pile up copies.
func _keep_unloadable_copies() -> void:
	var stamp: String = str(int(Time.get_unix_time_from_system()))
	for file_path: String in [store.path, store.temp_path(), store.backup_path()]:
		if not FileAccess.file_exists(file_path) or _already_kept(file_path):
			continue
		var error: Error = DirAccess.copy_absolute(file_path, "%s.unloadable-%s" % [file_path, stamp])
		if error != OK:
			push_warning("Couldn't keep a copy of %s: %s" % [file_path, error_string(error)])


static func _already_kept(file_path: String) -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	var prefix: String = file_path.get_file() + ".unloadable-"
	for name: String in DirAccess.get_files_at(file_path.get_base_dir()):
		if name.begins_with(prefix) and FileAccess.get_file_as_bytes(file_path.get_base_dir().path_join(name)) == bytes:
			return true
	return false


## Builds in town and saves at once, as after every costed action. Returns
## [] when built, or the sim's reasons it wasn't (GameState.build).
func build(building_id: String, cell: Vector2i) -> Array[Dictionary]:
	if state.phase != GameState.Phase.TOWN:
		return [{"kind": Town.Refusal.SPOT, "text": "Not in town"}]
	var refusals: Array[Dictionary] = state.build(data, building_id, cell)
	if refusals.is_empty():
		save()
	return refusals


## Moves a building for free, and saves, so a move is never lost to a quit.
## Returns "" when it moved, or why not.
func move_building(uid: int, cell: Vector2i) -> String:
	if state.phase != GameState.Phase.TOWN:
		return "Not in town"
	var problem: String = state.move_building(data, uid, cell)
	if problem.is_empty():
		save()
	return problem


## Moves a villager into another home for free (whoever lived there swaps
## back), and saves. Returns "" when done, or why not.
func swap_home(villager: String, uid: int) -> String:
	if state.phase != GameState.Phase.TOWN:
		return "Not in town"
	var problem: String = state.swap_home(data, villager, uid)
	if problem.is_empty():
		save()
	return problem


## Starts a date (M5): a session for the date screen's script, or null if
## the sim refuses. Nothing is spent or saved until finish_date.
func begin_date(villager: String, spot: String) -> DateSession:
	if SceneFlow.busy:
		return null
	return state.begin_date(data, villager, spot, Settings.effective_content_level())


## Ends a date through the one sim call (it spends the action and keeps the
## affection together) and saves at once, as after every costed action.
## Returns [] when kept, or the sim's reasons it wasn't.
func finish_date(session: DateSession) -> Array[Dictionary]:
	var refusals: Array[Dictionary] = state.finish_date(data, session)
	if refusals.is_empty():
		save()
	return refusals


## "Go down" (TC-7). Returns false if it's not allowed right now.
func go_down() -> bool:
	if SceneFlow.busy:
		return false
	# Built once, from the town as it stands, and never saved (Imogen's
	# bridge review): a reload rebuilds the delve, and the log keeps the kit.
	var kit: Kit = Kit.build(data, state)
	if kit == null or not state.start_delve(data):
		return false
	run = DelveRun.create(data, state.current_delve_seed(), kit,
		state.villagers_left(data), state.landmarks_left(data), state.delve_attempt)
	save()
	delve_started.emit(state.delve_count, state.current_delve_seed())
	SceneFlow.change_half(DELVE_SCENE, TideTransition.Direction.DOWN)
	return true


## Leaves the delve for town once the run is over, banking its haul by how
## it ended (surfaced at a landing, cleared the vault, or washed up): the
## outcome comes from the run, never the caller. The save is written before
## the tide starts moving, so quitting during the animation can't reload as
## an abandoned delve. Returns false if it's not allowed right now.
func come_up() -> bool:
	if SceneFlow.busy or run == null or not run.is_over():
		return false
	if not state.finish_delve(data, run.outcome(), run.haul):
		return false
	run = null
	var error: Error = save()
	if error != OK and error != ERR_BUSY and not saving_locked:
		save_problem = "Your delve was banked, but saving failed. Keep the game open and try again."
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
	if error == OK:
		save_problem = ""
	elif error != ERR_BUSY:
		push_warning("Save failed: %s" % error_string(error))
		save_failed.emit(error)
	return error


func _build_payload() -> Dictionary:
	return {GameState.PAYLOAD_KEY: state.to_dict()}


## A save held during a transition is written before the window closes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and store != null and store.has_pending_write():
		store.flush()


func _on_transition_started(_direction: TideTransition.Direction) -> void:
	store.blocked = true


func _on_transition_finished(_direction: TideTransition.Direction) -> void:
	store.blocked = false


func _on_deferred_write_finished(error: Error) -> void:
	if error == OK and not saving_locked:
		save_problem = ""
	if error != OK:
		push_warning("Held save failed: %s" % error_string(error))
		save_failed.emit(error)


## A fresh campaign seed. This is the one place randomness comes from
## outside the seeded streams.
static func _new_campaign_seed() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return (rng.randi() << 32) | rng.randi()
