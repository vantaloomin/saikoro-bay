extends GutTest
## RngStreams: the golden sequence, stream independence and save/restore.

const SEED: int = 20261103


## Golden sequence. If this fails, the same seed no longer gives the same
## delve: saved delves, bug reports and balance numbers all stop matching.
## That happens if a Godot upgrade changes its generator, or if the stream
## derivation or a stream's name changes. Don't just update the numbers:
## decide whether old seeds need to keep working first.
func test_golden_sequence_per_stream() -> void:
	var expected: Dictionary[RngStreams.Stream, Array] = {
		RngStreams.Stream.MAP: [4, 6, 6, 6, 6, 2, 3, 4, 3, 6],
		RngStreams.Stream.ROLLS: [1, 4, 2, 1, 5, 1, 4, 3, 3, 6],
		RngStreams.Stream.LOOT: [2, 6, 3, 5, 2, 2, 6, 6, 5, 4],
		RngStreams.Stream.ENEMIES: [2, 6, 2, 3, 4, 3, 6, 6, 2, 3],
		RngStreams.Stream.COSMETIC: [2, 4, 3, 6, 4, 1, 6, 4, 1, 6],
	}
	var rng: RngStreams = RngStreams.new(SEED)
	for stream: RngStreams.Stream in expected:
		assert_eq(_rolls(rng, stream, 10), expected[stream], RngStreams.Stream.keys()[stream])


func test_golden_wide_range() -> void:
	var rng: RngStreams = RngStreams.new(SEED)
	var values: Array[int] = []
	for _i: int in 5:
		values.append(rng.range_int(RngStreams.Stream.MAP, 0, 1000000))
	assert_eq(values, [33148, 84965, 818986, 214321, 474070])


func test_stream_seed_depends_on_name_not_order() -> void:
	assert_eq(RngStreams.stream_seed(SEED, "MAP"), RngStreams.stream_seed(SEED, "MAP"))
	assert_ne(RngStreams.stream_seed(SEED, "MAP"), RngStreams.stream_seed(SEED, "ROLLS"))
	assert_ne(RngStreams.stream_seed(SEED, "MAP"), RngStreams.stream_seed(SEED + 1, "MAP"))
	assert_gt(RngStreams.stream_seed(SEED, "MAP"), 0)


func test_ranges_beyond_32_bits_are_refused() -> void:
	var rng: RngStreams = RngStreams.new(SEED)
	var untouched: RngStreams = RngStreams.new(SEED)
	assert_eq(rng.range_int(RngStreams.Stream.LOOT, 3000000000, 3000000005), 3000000000)
	assert_push_error("bad range")
	assert_eq(rng.range_int(RngStreams.Stream.LOOT, 0, 10000000000), 0)
	assert_eq(rng.range_int(RngStreams.Stream.LOOT, -2147483648, 2147483647), -2147483648, "span too wide")
	assert_eq(rng.range_int(RngStreams.Stream.LOOT, 5, 4), 5, "reversed")
	assert_push_error_count(4)
	assert_eq(_rolls(rng, RngStreams.Stream.LOOT, 10), _rolls(untouched, RngStreams.Stream.LOOT, 10),
		"refused ranges don't consume draws")
	# The widest allowed ranges still work.
	assert_between(rng.range_int(RngStreams.Stream.LOOT, 0, 2147483647), 0, 2147483647)
	assert_between(rng.range_int(RngStreams.Stream.LOOT, -2147483648, -1), -2147483648, -1)


func test_bad_inputs_return_safe_values() -> void:
	var rng: RngStreams = RngStreams.new(SEED)
	assert_eq(rng.index(RngStreams.Stream.MAP, 0), -1)
	assert_null(rng.pick(RngStreams.Stream.MAP, []))
	assert_eq(rng.roll(RngStreams.Stream.ROLLS, 0), 1)
	assert_false(rng.chance(RngStreams.Stream.LOOT, 1, 0))
	assert_eq(rng.weighted_index(RngStreams.Stream.LOOT, PackedInt32Array([0, 0])), -1)
	assert_eq(rng.weighted_index(RngStreams.Stream.LOOT, PackedInt32Array([1, -1])), -1)
	assert_eq(rng.weighted_index(RngStreams.Stream.LOOT, PackedInt32Array([2147483647, 1])), -1, "total too big")
	assert_push_error_count(7)


func test_same_seed_same_numbers() -> void:
	var a: RngStreams = RngStreams.new(99)
	var b: RngStreams = RngStreams.new(99)
	assert_eq(_rolls(a, RngStreams.Stream.ROLLS, 50), _rolls(b, RngStreams.Stream.ROLLS, 50))


func test_different_seeds_differ() -> void:
	var a: RngStreams = RngStreams.new(1)
	var b: RngStreams = RngStreams.new(2)
	assert_ne(_rolls(a, RngStreams.Stream.MAP, 20), _rolls(b, RngStreams.Stream.MAP, 20))


func test_streams_are_independent() -> void:
	var quiet: RngStreams = RngStreams.new(SEED)
	var noisy: RngStreams = RngStreams.new(SEED)
	# Lots of cosmetic and roll draws on one copy must not move its map stream.
	_rolls(noisy, RngStreams.Stream.COSMETIC, 500)
	_rolls(noisy, RngStreams.Stream.ROLLS, 123)
	assert_eq(_rolls(noisy, RngStreams.Stream.MAP, 30), _rolls(quiet, RngStreams.Stream.MAP, 30))


func test_streams_differ_from_each_other() -> void:
	var rng: RngStreams = RngStreams.new(SEED)
	var seen: Dictionary = {}
	for stream: int in RngStreams.Stream.size():
		var copy: RngStreams = RngStreams.new(SEED)
		seen[str(_rolls(copy, stream as RngStreams.Stream, 20))] = true
	assert_eq(seen.size(), RngStreams.Stream.size(), "every stream has its own sequence")
	assert_not_null(rng)


func test_save_and_restore_through_json_continues_exactly() -> void:
	var original: RngStreams = RngStreams.new(SEED)
	_rolls(original, RngStreams.Stream.ROLLS, 17)
	_rolls(original, RngStreams.Stream.MAP, 3)
	# Through real JSON text, as a save file would.
	var text: String = JSON.stringify(original.to_dict())
	var parsed: Dictionary = JSON.parse_string(text)
	var restored: RngStreams = RngStreams.new()
	assert_true(restored.load_dict(parsed))
	assert_eq(restored.run_seed, SEED)
	for stream: int in RngStreams.Stream.size():
		var s: RngStreams.Stream = stream as RngStreams.Stream
		assert_eq(_rolls(restored, s, 25), _rolls(original, s, 25), RngStreams.Stream.keys()[stream])


func test_load_rejects_malformed_data() -> void:
	var rng: RngStreams = RngStreams.new(5)
	var before: Array[int] = _rolls(RngStreams.new(5), RngStreams.Stream.MAP, 5)
	assert_false(rng.load_dict({}))
	assert_false(rng.load_dict({"seed": "1", "states": ["1", "2"]}), "wrong stream count")
	assert_false(rng.load_dict({"seed": 1.0, "states": ["1", "2", "3", "4", "5"]}), "numeric seed")
	assert_false(rng.load_dict({"seed": "1", "states": ["1", "2", "x", "4", "5"]}), "bad state")
	assert_eq(_rolls(rng, RngStreams.Stream.MAP, 5), before, "a failed load changes nothing")


func test_roll_stays_in_range_and_hits_every_face() -> void:
	var rng: RngStreams = RngStreams.new(7)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for _i: int in 6000:
		var value: int = rng.roll(RngStreams.Stream.ROLLS, 6)
		assert_between(value, 1, 6)
		counts[value] += 1
	for face: int in range(1, 7):
		# Expected 1000 each; this only catches a broken mapping, not bias.
		assert_between(counts[face], 850, 1150, "face %d" % face)


func test_chance_edges() -> void:
	var rng: RngStreams = RngStreams.new(3)
	for _i: int in 200:
		assert_false(rng.chance(RngStreams.Stream.LOOT, 0, 10))
		assert_true(rng.chance(RngStreams.Stream.LOOT, 10, 10))


func test_weighted_index_skips_zero_weights() -> void:
	var rng: RngStreams = RngStreams.new(11)
	var weights: PackedInt32Array = [0, 3, 0, 1]
	for _i: int in 500:
		var picked: int = rng.weighted_index(RngStreams.Stream.LOOT, weights)
		assert_true(picked == 1 or picked == 3, "picked %d" % picked)


func test_shuffle_is_seeded_and_keeps_items() -> void:
	var a: Array = range(20)
	var b: Array = range(20)
	RngStreams.new(SEED).shuffle(RngStreams.Stream.MAP, a)
	RngStreams.new(SEED).shuffle(RngStreams.Stream.MAP, b)
	assert_eq(a, b)
	assert_ne(a, range(20), "it actually shuffled")
	var sorted: Array = a.duplicate()
	sorted.sort()
	assert_eq(sorted, range(20))


func _rolls(rng: RngStreams, stream: RngStreams.Stream, count: int) -> Array[int]:
	var values: Array[int] = []
	for _i: int in count:
		values.append(rng.roll(stream, 6))
	return values
