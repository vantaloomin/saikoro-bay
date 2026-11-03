class_name BoardSounds
extends Node
## Placeholder dice sounds (plan section 7, M1): roll, land, place, take
## back and invalid drop. They're synthesized at startup, so there are no
## audio files to replace later: the real SFX swap in as AudioStreams under
## the same cue names.
##
## Every cue is short and quiet. A wooden "tock" family for the dice, and a
## low two-note buzz for a refusal, so a refusal sounds different from a
## move even with the screen off.

const RATE: int = 22050
const CUES: Array[String] = ["roll", "land", "place", "take_back", "invalid"]

## Cue name -> AudioStreamWAV. Built once, shared by every board.
static var _streams: Dictionary[String, AudioStreamWAV] = {}

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
## Cue names played, oldest first, so tests can check what a move sounded like.
var played: Array[String] = []


func _ready() -> void:
	if _streams.is_empty():
		_build_streams()
	for i: int in 4:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = -8.0
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)


func play(cue: String) -> void:
	if not _streams.has(cue):
		push_error("BoardSounds: unknown cue \"%s\"" % cue)
		return
	played.append(cue)
	if played.size() > 32:
		played.pop_front()
	if _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[cue]
	player.play()


static func stream(cue: String) -> AudioStreamWAV:
	if _streams.is_empty():
		_build_streams()
	return _streams.get(cue)


static func _build_streams() -> void:
	# A fixed seed: placeholder noise is the same on every run. This is
	# cosmetic and never touches the game's RNG streams.
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = 7
	var roll: PackedFloat32Array = PackedFloat32Array()
	for i: int in 7:
		roll.append_array(_tock(noise, 520.0 + 90.0 * (i % 3), 0.035, 0.35 + 0.08 * (i % 2)))
		roll.append_array(_silence(0.018 + 0.006 * (i % 3)))
	_streams["roll"] = _to_wav(roll)
	_streams["land"] = _to_wav(_tock(noise, 260.0, 0.09, 0.8))
	_streams["place"] = _to_wav(_tock(noise, 420.0, 0.06, 0.7))
	_streams["take_back"] = _to_wav(_tock(noise, 680.0, 0.045, 0.45))
	var buzz: PackedFloat32Array = _tone(150.0, 0.08, 0.45)
	buzz.append_array(_silence(0.02))
	buzz.append_array(_tone(110.0, 0.12, 0.45))
	_streams["invalid"] = _to_wav(buzz)


## A wooden knock: a damped sine with a little noise at the attack.
static func _tock(noise: RandomNumberGenerator, freq: float, seconds: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var count: int = int(RATE * seconds)
	for n: int in count:
		var t: float = float(n) / RATE
		var env: float = exp(-t * 60.0)
		var click: float = noise.randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.5
		out.append((sin(TAU * freq * t) * env + click) * gain)
	return out


## A soft square-ish tone, for the refusal buzz.
static func _tone(freq: float, seconds: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var count: int = int(RATE * seconds)
	for n: int in count:
		var t: float = float(n) / RATE
		var env: float = minf(1.0, t * 200.0) * minf(1.0, (seconds - t) * 80.0)
		out.append(clampf(sin(TAU * freq * t) * 2.5, -1.0, 1.0) * env * gain)
	return out


static func _silence(seconds: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(int(RATE * seconds))
	return out


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
