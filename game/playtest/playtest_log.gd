extends Node
## Local playtest log (no network). Writes one JSON object per line to
## user://playtest/<session>.jsonl so the M7 gate can be measured: time in
## town, whether each delve started without a prompt, take-backs, invalid
## drops and hover time.
##
## Autoload "PlaytestLog". Off unless the build has the "playtest" feature
## tag or the game is started with `-- --playtest`. When it's off, every
## call is a no-op.
##
## The observer presses F9 whenever they nudge the player (a hint, a
## question, pointing at the screen). The next delve_start then records
## prompted = true, which is how "started the next delve unprompted" is
## counted.

const DIR: String = "user://playtest"
const FEATURE: String = "playtest"
const ARG: String = "--playtest"
const PROMPT_ACTION: StringName = &"observer_prompt"

var enabled: bool = false
var path: String = ""

var _file: FileAccess
var _session_start_ms: int = 0
var _town_since_ms: int = -1
## When the tally opened, or -1: its time isn't town time (Imogen's #58 audit).
var _tally_since_ms: int = -1
var _prompted_this_visit: bool = false


func _ready() -> void:
	_ensure_prompt_action()
	if OS.has_feature(FEATURE) or ARG in OS.get_cmdline_user_args():
		start_after_load(DIR.path_join(Time.get_datetime_string_from_system(true).replace(":", "").replace("T", "-") + ".jsonl"))
	Game.delve_started.connect(_on_delve_started)
	Game.returned_to_town.connect(_on_returned_to_town)
	Game.tally_closed.connect(_on_tally_closed)


## Starts the log once Game has loaded the campaign, so session_start
## records the real campaign and not the empty one autoloads begin with
## (Imogen's #47 audit: autoloads are ready before boot loads the save).
func start_after_load(file_path: String) -> void:
	Game.campaign_loaded.connect(start.bind(file_path), CONNECT_ONE_SHOT)


## Opens a log file and records the session start. Tests pass their own path.
func start(file_path: String) -> Error:
	stop()
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	enabled = true
	path = file_path
	_session_start_ms = Time.get_ticks_msec()
	_prompted_this_visit = false
	log_event("session_start", {
		"version": str(ProjectSettings.get_setting("application/config/version")),
		"sfw_build": OS.has_feature("sfw"),
		"campaign_seed": str(Game.state.campaign_seed),
		"delve_count": Game.state.delve_count,
		# Exit-check sessions in the test town, to leave out of real numbers.
		"fake_town": Game.fake_town,
	})
	if Game.state.phase == GameState.Phase.TOWN:
		_town_since_ms = _session_start_ms
	return OK


func stop() -> void:
	if _file != null:
		log_event("session_end")
		_file.close()
	_file = null
	enabled = false


## Records an event. `fields` must be JSON-friendly.
func log_event(event: String, fields: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	var entry: Dictionary = {"t_ms": Time.get_ticks_msec() - _session_start_ms, "event": event}
	entry.merge(fields)
	_file.store_line(JSON.stringify(entry))
	_file.flush()


## Call when the observer gives any hint (F9 does this).
func mark_prompt() -> void:
	_prompted_this_visit = true
	log_event("observer_prompt")


func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed(PROMPT_ACTION):
		mark_prompt()
		get_viewport().set_input_as_handled()


func _on_delve_started(number: int, seed_value: int) -> void:
	var fields: Dictionary = {"delve": number, "seed": str(seed_value), "prompted": _prompted_this_visit}
	# Everything besides the seed that the map was drawn from, for replay.
	if Game.run != null:
		fields["map"] = Game.run.map.inputs()
		fields["attempt"] = Game.run.attempt
		# How the dice draw (RngStreams.ROLLER), so old logs still replay.
		fields["roller"] = RngStreams.ROLLER
		# A replay input: replays rebuild it with Kit.from_dict, never Kit.build.
		fields["kit"] = Game.run.kit.to_dict()
	if _town_since_ms >= 0:
		fields["time_in_town_ms"] = Time.get_ticks_msec() - _town_since_ms
	log_event("delve_start", fields)
	_town_since_ms = -1


func _on_returned_to_town(number: int) -> void:
	log_event("delve_end", {"delve": number, "outcome": str(Game.state.last_delve.get("outcome", ""))})
	_tally_since_ms = Time.get_ticks_msec()
	_prompted_this_visit = false


## Town time starts at the tally's Continue, not when the delve ends, so
## the M7 numbers don't count the tally as time in town.
func _on_tally_closed(number: int) -> void:
	var fields: Dictionary = {"delve": number}
	if _tally_since_ms >= 0:
		fields["tally_ms"] = Time.get_ticks_msec() - _tally_since_ms
	log_event("tally_closed", fields)
	_tally_since_ms = -1
	_town_since_ms = Time.get_ticks_msec()


func _exit_tree() -> void:
	stop()


static func _ensure_prompt_action() -> void:
	if InputMap.has_action(PROMPT_ACTION):
		return
	InputMap.add_action(PROMPT_ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F9
	InputMap.action_add_event(PROMPT_ACTION, key)
