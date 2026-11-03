class_name RngStreams
extends RefCounted
## Seeded random numbers for the sim, split into independent streams.
##
## One seed per delve. Each stream gets its own generator, so drawing extra
## numbers in one place (say, a cosmetic sparkle) never shifts what the map or
## the dice do. Every stream's state can be saved and restored exactly, so a
## delve replays the same from any save point.
##
## Rules for sim code:
## - Never call the global randi()/randf()/randomize(); tools/lint_sim.py
##   fails CI on them.
## - Pick the stream by what the number is for, not by convenience.
## - Only integer helpers live here. The sim never needs random floats.
## - Ranges must fit in 32 bits: Godot's generator works in 32-bit ints and
##   would silently wrap. Bad input (a range too wide, an empty list) logs an
##   error and returns a safe value instead of relying on assert, which is
##   stripped from release builds.
##
## Each stream's seed is SHA-256 of the run seed and the stream's NAME, so
## streams can be added or reordered without changing existing ones. Renaming
## a stream does change its numbers (the golden test will catch it).

enum Stream {
	MAP,       ## Delve layout and room contents.
	ROLLS,     ## The player's dice rolls and rerolls.
	LOOT,      ## Treasure, haul and rewards.
	ENEMIES,   ## Enemy choice, intents and twists.
	COSMETIC,  ## Anything that only changes looks or barks. Never affects rules.
}

var run_seed: int:
	get:
		return _run_seed

const INT32_MIN: int = -2147483648
const INT32_MAX: int = 2147483647

var _run_seed: int = 0
var _streams: Array[RandomNumberGenerator] = []


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


## Resets every stream from a new run seed.
func reseed(seed_value: int) -> void:
	_run_seed = seed_value
	_streams.clear()
	for stream_name: String in Stream.keys():
		var stream: RandomNumberGenerator = RandomNumberGenerator.new()
		stream.seed = stream_seed(seed_value, stream_name)
		_streams.append(stream)


## The seed for one stream: the first 60 bits of SHA-256 of the run seed and
## the stream name. Engine-independent and positive.
static func stream_seed(seed_value: int, stream_name: String) -> int:
	var digest: String = ("saikoro-bay:stream:%d:%s" % [seed_value, stream_name]).sha256_text()
	return digest.substr(0, 15).hex_to_int()


## A whole number from `from` to `to`, both included.
## Both ends must fit in 32 bits and the span must stay under 2^31; anything
## else logs an error and returns `from` without drawing.
func range_int(stream: Stream, from: int, to: int) -> int:
	if from > to or from < INT32_MIN or to > INT32_MAX or to - from > INT32_MAX:
		push_error("RngStreams.range_int: bad range %d..%d" % [from, to])
		return from
	return _streams[stream].randi_range(from, to)


## One roll of a die with `sides` faces: 1 to `sides`.
func roll(stream: Stream, sides: int) -> int:
	if sides < 1:
		push_error("RngStreams.roll: a die needs at least one side, got %d" % sides)
		return 1
	return range_int(stream, 1, sides)


## An index into a list of `size` items: 0 to size - 1. An empty list logs
## an error and returns -1; callers must handle it.
func index(stream: Stream, size: int) -> int:
	if size < 1:
		push_error("RngStreams.index: empty list")
		return -1
	return range_int(stream, 0, size - 1)


## True with a chance of `numerator` in `denominator`, using integers only.
func chance(stream: Stream, numerator: int, denominator: int) -> bool:
	if denominator < 1 or numerator < 0:
		push_error("RngStreams.chance: bad odds %d in %d" % [numerator, denominator])
		return false
	return range_int(stream, 1, denominator) <= numerator


## One item from an array, or null (with an error) if it's empty.
func pick(stream: Stream, items: Array) -> Variant:
	var i: int = index(stream, items.size())
	return items[i] if i >= 0 else null


## Shuffles `items` in place (Fisher-Yates). Never use Array.shuffle() in the
## sim: it uses the global generator.
func shuffle(stream: Stream, items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = range_int(stream, 0, i)
		var held: Variant = items[i]
		items[i] = items[j]
		items[j] = held


## Index chosen with integer weights. Zero weights are never chosen.
## Negative weights, a zero total or a total of 2^31 or more log an error
## and return -1.
func weighted_index(stream: Stream, weights: PackedInt32Array) -> int:
	var total: int = 0
	for w: int in weights:
		if w < 0:
			push_error("RngStreams.weighted_index: negative weight %d" % w)
			return -1
		total += w
	if total <= 0 or total > INT32_MAX:
		push_error("RngStreams.weighted_index: total weight %d out of range" % total)
		return -1
	var roll_value: int = range_int(stream, 1, total)
	for i: int in weights.size():
		roll_value -= weights[i]
		if roll_value <= 0:
			return i
	return weights.size() - 1


## Saveable snapshot. 64-bit values are stored as strings because JSON
## numbers are doubles and would lose precision above 2^53.
func to_dict() -> Dictionary:
	var states: Array[String] = []
	for stream: RandomNumberGenerator in _streams:
		states.append(str(stream.state))
	return {
		"seed": str(_run_seed),
		"states": states,
	}


## Restores a snapshot from to_dict(). Returns false (and changes nothing)
## if the data is malformed or has the wrong number of streams.
func load_dict(data: Dictionary) -> bool:
	var seed_text: Variant = data.get("seed")
	var states: Variant = data.get("states")
	if not (seed_text is String and (seed_text as String).is_valid_int()):
		return false
	if not (states is Array and (states as Array).size() == Stream.size()):
		return false
	for state_text: Variant in states as Array:
		if not (state_text is String and (state_text as String).is_valid_int()):
			return false
	reseed((seed_text as String).to_int())
	var i: int = 0
	for state_text: Variant in states as Array:
		_streams[i].state = (state_text as String).to_int()
		i += 1
	return true
