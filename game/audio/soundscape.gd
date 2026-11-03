extends Node
## The ambience beds and the stingers (M6, plan section 7).
##
## Autoload "Soundscape". Each half has a bed that loops under its music:
## waves, gulls and wind chimes in town; muffled water and the casino's
## murmur in the palace. The bed follows the current scene, fading out as
## the tide covers the screen and in once the new half is there, so the
## two never play over each other. Scenes without a bed (boot, menus) are
## quiet.
##
## Stingers are one-shots: the tide both ways (played here, from
## SceneFlow), Koban's vault opening and ending (from the vault board), and
## the barrel when a washed-up delve reaches town. The files are made by
## tools/make_ambience.py and tools/make_stingers.py.

const AMBIENCE_DIR: String = "res://content/sfw/ambience/"
const SFX_DIR: String = "res://content/sfw/sfx/"
## Scene path -> bed file, and how loud it sits under the music.
const BEDS: Dictionary[String, String] = {
	"res://game/town/town.tscn": "town_bed",
	"res://game/delve/delve.tscn": "palace_bed",
}
const BED_DB: Dictionary[String, float] = {"town_bed": -10.0, "palace_bed": -13.0}
const BED_FADE_IN: float = 1.5
const BED_FADE_OUT: float = 0.6
const SILENT_DB: float = -60.0
const STINGERS: Array[String] = [
	"tide_down", "tide_up", "koban_vault", "koban_wins", "koban_beaten", "barrel_1", "barrel_2", "barrel_3",
]
const STINGER_DB: float = -6.0
const TIDE_DB: float = -8.0
const BARREL_VARIANTS: int = 3

## The bed playing now ("" for none).
var bed: String = ""
## Stingers played, oldest first, so tests can check what an event sounded
## like (as BoardSounds.played does for the dice).
var played: Array[String] = []

var _bed_player: AudioStreamPlayer
## A few players in turn, so a stinger doesn't cut off the one before.
var _stinger_players: Array[AudioStreamPlayer] = []
var _next_stinger: int = 0
## The barrel waits for the town to be uncovered, so it lands as the
## notice board says "You washed up in a barrel". "" when none is due.
var _barrel_due: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in 3:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_stinger_players.append(player)
	SceneFlow.transition_started.connect(_on_transition_started)
	SceneFlow.transition_finished.connect(_on_transition_finished)
	Game.returned_to_town.connect(_on_returned_to_town)
	get_tree().scene_changed.connect(_on_scene_changed)


## Plays a one-shot on the SFX bus.
func stinger(cue: String) -> void:
	if not STINGERS.has(cue):
		push_error("Soundscape: unknown stinger \"%s\"" % cue)
		return
	played.append(cue)
	if played.size() > 32:
		played.pop_front()
	var player: AudioStreamPlayer = _stinger_players[_next_stinger]
	_next_stinger = (_next_stinger + 1) % _stinger_players.size()
	player.stream = load(SFX_DIR + cue + ".ogg") as AudioStream
	player.volume_db = TIDE_DB if cue.begins_with("tide_") else STINGER_DB
	player.play()


## Starts the bed `bed_name` (fading out the old one), or just fades out
## with "".
func play_bed(bed_name: String) -> void:
	if bed_name == bed:
		return
	_fade_out_bed()
	bed = bed_name
	if bed_name.is_empty():
		return
	_bed_player = AudioStreamPlayer.new()
	_bed_player.name = "Bed"
	# Loops by its import settings; tools/make_ambience.py makes it seamless.
	_bed_player.stream = load(AMBIENCE_DIR + bed_name + ".ogg") as AudioStream
	_bed_player.bus = &"SFX"
	_bed_player.volume_db = SILENT_DB
	add_child(_bed_player)
	_bed_player.play()
	create_tween().tween_property(_bed_player, "volume_db", BED_DB[bed_name], BED_FADE_IN)


## The barrel variant for a delve number: they take turns, so the gag
## changes each time it happens. Cosmetic; never touches the game's RNG.
static func barrel_for(delve_number: int) -> String:
	return "barrel_%d" % (posmod(delve_number, BARREL_VARIANTS) + 1)


func _fade_out_bed() -> void:
	if _bed_player == null:
		return
	var leaving: AudioStreamPlayer = _bed_player
	_bed_player = null
	bed = ""
	var tween: Tween = create_tween()
	tween.tween_property(leaving, "volume_db", SILENT_DB, BED_FADE_OUT)
	tween.tween_callback(leaving.queue_free)


func _on_transition_started(direction: TideTransition.Direction) -> void:
	stinger("tide_down" if direction == TideTransition.Direction.DOWN else "tide_up")
	_fade_out_bed()


func _on_scene_changed() -> void:
	var scene: Node = get_tree().current_scene
	play_bed(str(BEDS.get(scene.scene_file_path, "")) if scene != null else "")


func _on_returned_to_town(number: int) -> void:
	var outcome: String = str(Game.state.last_delve.get("outcome", "")) if Game.state != null else ""
	_barrel_due = barrel_for(number) if outcome == Haul.WASHED_UP else ""


func _on_transition_finished(direction: TideTransition.Direction) -> void:
	if direction == TideTransition.Direction.UP and not _barrel_due.is_empty():
		stinger(_barrel_due)
	_barrel_due = ""
