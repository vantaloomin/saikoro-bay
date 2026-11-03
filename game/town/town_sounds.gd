class_name TownSounds
extends Node
## Placeholder town sounds (two-halves section 1: wood, paper, ceramic and
## wind chimes). Like BoardSounds they're synthesized at startup, so the
## real SFX swap in later as AudioStreams under the same cue names.
##
## - stamp: the hanko's confirm, a wooden "tok" with a chime over it.
## - refuse: a soft paper thump, for a spot or a stamp the town says no to.
## - paper: a sheet or a tab opening, a short rustle.
## - lift / set_down: picking a building up and setting it down for free.
## - chimes: a landmark opening, wind chimes.
## - hold: a soft tone under the "Go down" fill. It loops, and the hold
##   button sets its pitch and level from the fill, so it rises as the
##   fill does and falls away when the player lets go early.
##
## Every cue but the hold is short and quiet; the town is never loud.

const RATE: int = 22050
const CUES: Array[String] = ["stamp", "refuse", "paper", "lift", "set_down", "chimes"]
const HOLD: String = "hold"

## Cue name -> AudioStreamWAV. Built once, shared by every town screen.
static var _streams: Dictionary[String, AudioStreamWAV] = {}

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
## Cue names played, oldest first, so tests can check what a move sounded like.
var played: Array[String] = []


func _ready() -> void:
	for i: int in 4:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = -10.0
		add_child(player)
		_players.append(player)


func play(cue: String) -> void:
	if not CUES.has(cue):
		push_error("TownSounds: unknown cue \"%s\"" % cue)
		return
	played.append(cue)
	if played.size() > 32:
		played.pop_front()
	if _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream(cue)
	player.play()


static func stream(cue: String) -> AudioStreamWAV:
	if _streams.is_empty():
		_build_streams()
	return _streams.get(cue)


static func _build_streams() -> void:
	# A fixed seed: placeholder noise is the same on every run. Cosmetic,
	# and never touches the game's RNG streams.
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = 11
	var stamp: PackedFloat32Array = _knock(noise, 300.0, 0.08, 0.75)
	_mix(stamp, _chime([1568.0, 2349.0], 0.7, 0.22), int(RATE * 0.03))
	_streams["stamp"] = _to_wav(stamp)
	_streams["refuse"] = _to_wav(_thump(noise, 0.14, 0.6))
	_streams["paper"] = _to_wav(_rustle(noise, 0.12, 0.25))
	_streams["lift"] = _to_wav(_knock(noise, 520.0, 0.05, 0.4))
	_streams["set_down"] = _to_wav(_knock(noise, 240.0, 0.1, 0.65))
	var chimes: PackedFloat32Array = PackedFloat32Array()
	chimes.resize(int(RATE * 1.6))
	# A run up D major pentatonic, the town music's key.
	var notes: Array[float] = [1175.0, 1319.0, 1480.0, 1760.0, 1976.0]
	for i: int in notes.size():
		_mix(chimes, _chime([notes[i], notes[i] * 2.76], 1.0, 0.16), int(RATE * 0.09 * i))
	_streams["chimes"] = _to_wav(chimes)
	var hold: AudioStreamWAV = _to_wav(_swell())
	hold.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hold.loop_end = int(RATE * 0.5)
	_streams[HOLD] = hold


## Wood: a damped sine with a little noise at the attack.
static func _knock(noise: RandomNumberGenerator, freq: float, seconds: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for n: int in int(RATE * seconds):
		var t: float = float(n) / RATE
		var click: float = noise.randf_range(-1.0, 1.0) * exp(-t * 500.0) * 0.4
		out.append((sin(TAU * freq * t) * exp(-t * 45.0) + click) * gain)
	return out


## Metal or ceramic: a few inharmonic partials that ring and fade.
static func _chime(partials: Array[float], seconds: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for n: int in int(RATE * seconds):
		var t: float = float(n) / RATE
		var value: float = 0.0
		for i: int in partials.size():
			value += sin(TAU * partials[i] * t) * exp(-t * (4.0 + 3.0 * i)) / (i + 1)
		out.append(value * minf(1.0, t * 800.0) * gain)
	return out


## Paper landing on paper: low, soft noise with a quick fall.
static func _thump(noise: RandomNumberGenerator, seconds: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var low: float = 0.0
	for n: int in int(RATE * seconds):
		var t: float = float(n) / RATE
		low += (noise.randf_range(-1.0, 1.0) - low) * 0.08
		out.append((low * 3.0 + sin(TAU * 90.0 * t) * 0.5) * exp(-t * 30.0) * gain)
	return out


## A sheet turning: bright noise in a soft swell.
static func _rustle(noise: RandomNumberGenerator, seconds: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var last: float = 0.0
	for n: int in int(RATE * seconds):
		var t: float = float(n) / RATE
		var white: float = noise.randf_range(-1.0, 1.0)
		var bright: float = white - last
		last = white
		out.append(bright * sin(PI * t / seconds) * gain)
	return out


## Half a second of soft tone that loops with no seam: every partial runs
## a whole number of cycles, and the two close ones beat once a loop.
static func _swell() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for n: int in int(RATE * 0.5):
		var t: float = float(n) / RATE
		out.append(sin(TAU * 220.0 * t) * 0.22 + sin(TAU * 222.0 * t) * 0.18 + sin(TAU * 330.0 * t) * 0.1
			+ sin(TAU * 440.0 * t) * 0.05)
	return out


static func _mix(into: PackedFloat32Array, sound: PackedFloat32Array, at: int) -> void:
	if into.size() < at + sound.size():
		into.resize(at + sound.size())
	for i: int in sound.size():
		into[at + i] += sound[i]


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
