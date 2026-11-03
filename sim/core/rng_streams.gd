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
##
## Streams are derived from the run seed in enum order. Add new streams at
## the END of the enum, or every existing seed changes (the golden test in
## tests/unit/test_rng_streams.gd will catch it).

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

var _run_seed: int = 0
var _streams: Array[RandomNumberGenerator] = []


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


## Resets every stream from a new run seed.
func reseed(seed_value: int) -> void:
	_run_seed = seed_value
	_streams.clear()
	var master: RandomNumberGenerator = RandomNumberGenerator.new()
	master.seed = seed_value
	for _i: int in Stream.size():
		var stream: RandomNumberGenerator = RandomNumberGenerator.new()
		# Two 32-bit draws make one 64-bit stream seed.
		var high: int = master.randi()
		var low: int = master.randi()
		stream.seed = (high << 32) | low
		_streams.append(stream)


## A whole number from `from` to `to`, both included.
func range_int(stream: Stream, from: int, to: int) -> int:
	assert(from <= to, "range_int needs from <= to")
	return _streams[stream].randi_range(from, to)


## One roll of a die with `sides` faces: 1 to `sides`.
func roll(stream: Stream, sides: int) -> int:
	assert(sides >= 1, "a die needs at least one side")
	return range_int(stream, 1, sides)


## An index into a list of `size` items: 0 to size - 1.
func index(stream: Stream, size: int) -> int:
	assert(size >= 1, "index needs a non-empty list")
	return range_int(stream, 0, size - 1)


## True with a chance of `numerator` in `denominator`, using integers only.
func chance(stream: Stream, numerator: int, denominator: int) -> bool:
	assert(denominator >= 1 and numerator >= 0, "chance needs 0 <= n and d >= 1")
	return range_int(stream, 1, denominator) <= numerator


## One item from a non-empty array.
func pick(stream: Stream, items: Array) -> Variant:
	return items[index(stream, items.size())]


## Shuffles `items` in place (Fisher-Yates). Never use Array.shuffle() in the
## sim: it uses the global generator.
func shuffle(stream: Stream, items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = range_int(stream, 0, i)
		var held: Variant = items[i]
		items[i] = items[j]
		items[j] = held


## Index chosen with integer weights. Zero weights are never chosen.
func weighted_index(stream: Stream, weights: PackedInt32Array) -> int:
	var total: int = 0
	for w: int in weights:
		assert(w >= 0, "weights can't be negative")
		total += w
	assert(total > 0, "weighted_index needs a positive total weight")
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
