extends GutTest
## SaveCodec: encoding, integrity checks and version handling.


func after_each() -> void:
	SaveCodec.MIGRATIONS.clear()


func test_round_trip() -> void:
	var payload: Dictionary = {"game": {"delve_count": 3, "name": "Bay"}, "list": [1, 2, 3]}
	var result: SaveCodec.DecodeResult = SaveCodec.decode(SaveCodec.encode(payload))
	assert_true(result.is_ok())
	assert_eq(result.version, SaveCodec.CURRENT_VERSION)
	var game: Dictionary = result.payload["game"]
	assert_eq(SaveCodec.read_int(game, "delve_count"), 3)
	assert_eq(game["name"], "Bay")


func test_seq_round_trips() -> void:
	assert_eq(SaveCodec.decode(SaveCodec.encode({}, 41)).seq, 41)
	assert_eq(SaveCodec.decode(SaveCodec.encode({})).seq, 0)


func test_empty_text() -> void:
	assert_eq(SaveCodec.decode("").status, SaveCodec.Status.EMPTY)
	assert_eq(SaveCodec.decode("  \n ").status, SaveCodec.Status.EMPTY)


func test_not_our_file() -> void:
	assert_eq(SaveCodec.decode("hello\nworld").status, SaveCodec.Status.BAD_HEADER)
	assert_eq(SaveCodec.decode('{"format":"other","version":1}\n{}').status, SaveCodec.Status.BAD_HEADER)
	assert_eq(SaveCodec.decode('{"format":"saikoro-bay-save"}').status, SaveCodec.Status.BAD_HEADER)


func test_truncated_payload_is_caught() -> void:
	var text: String = SaveCodec.encode({"a": 1, "b": "a longer value to cut"})
	var cut: String = text.substr(0, text.length() - 8)
	assert_eq(SaveCodec.decode(cut).status, SaveCodec.Status.BAD_CHECKSUM)


func test_edited_payload_is_caught() -> void:
	var text: String = SaveCodec.encode({"coins": 10})
	var edited: String = text.replace('"coins":10', '"coins":99')
	assert_ne(edited, text, "the edit applied")
	assert_eq(SaveCodec.decode(edited).status, SaveCodec.Status.BAD_CHECKSUM)


func test_edited_sequence_number_is_caught() -> void:
	var text: String = SaveCodec.encode({"coins": 10}, 3)
	var edited: String = text.replace('"seq":3', '"seq":9')
	assert_ne(edited, text, "the edit applied")
	assert_eq(SaveCodec.decode(edited).status, SaveCodec.Status.BAD_CHECKSUM)


func test_newer_version_is_refused() -> void:
	var body: String = JSON.stringify({}, "", true, true)
	var header: String = JSON.stringify({
		"format": SaveCodec.FORMAT,
		"version": SaveCodec.CURRENT_VERSION + 1,
		"sha256": body.sha256_text(),
	})
	var result: SaveCodec.DecodeResult = SaveCodec.decode(header + "\n" + body + "\n")
	assert_eq(result.status, SaveCodec.Status.TOO_NEW)
	assert_eq(result.version, SaveCodec.CURRENT_VERSION + 1)
	assert_eq(result.payload, {})


func test_bad_version_values() -> void:
	for version: Variant in [0, -1, 1.5, "one", null]:
		var header: String = JSON.stringify({"format": SaveCodec.FORMAT, "version": version, "sha256": ""})
		assert_eq(SaveCodec.decode(header + "\n{}").status, SaveCodec.Status.BAD_VERSION, str(version))


func test_older_version_without_migration_is_refused() -> void:
	var v1_text: String = SaveCodec.encode({"coins": 5})
	var result: SaveCodec.DecodeResult = SaveCodec.decode(v1_text, 2)
	assert_eq(result.status, SaveCodec.Status.BAD_VERSION, "no v1 -> v2 migration registered")


func test_migrations_run_in_order() -> void:
	SaveCodec.MIGRATIONS[2] = func(p: Dictionary) -> Dictionary:
		p["coins_v2"] = SaveCodec.read_int(p, "coins") * 10
		return p
	SaveCodec.MIGRATIONS[3] = func(p: Dictionary) -> Dictionary:
		p["coins_v3"] = SaveCodec.read_int(p, "coins_v2") + 1
		return p
	var result: SaveCodec.DecodeResult = SaveCodec.decode(SaveCodec.encode({"coins": 5}), 3)
	assert_true(result.is_ok())
	assert_eq(result.version, 3)
	assert_eq(SaveCodec.read_int(result.payload, "coins_v3"), 51)


func test_migration_must_return_a_dictionary() -> void:
	SaveCodec.MIGRATIONS[2] = func(_p: Dictionary) -> Variant:
		return null
	var result: SaveCodec.DecodeResult = SaveCodec.decode(SaveCodec.encode({"coins": 5}), 2)
	assert_eq(result.status, SaveCodec.Status.BAD_VERSION)


func test_payload_must_be_an_object() -> void:
	var body: String = "[1, 2, 3]"
	var header: String = JSON.stringify({"format": SaveCodec.FORMAT, "version": 1, "sha256": SaveCodec.digest(1, 0, body)})
	assert_eq(SaveCodec.decode(header + "\n" + body + "\n").status, SaveCodec.Status.BAD_PAYLOAD)


func test_read_int_rules() -> void:
	var data: Dictionary = JSON.parse_string('{"a": 3, "b": 1.5, "c": "12", "d": "x", "e": true, "f": -4}')
	assert_eq(SaveCodec.read_int(data, "a", -1), 3)
	assert_eq(SaveCodec.read_int(data, "b", -1), -1, "fractions are rejected")
	assert_eq(SaveCodec.read_int(data, "c", -1), 12)
	assert_eq(SaveCodec.read_int(data, "d", -1), -1)
	assert_eq(SaveCodec.read_int(data, "e", -1), -1, "booleans are not numbers")
	assert_eq(SaveCodec.read_int(data, "f", 0), -4)
	assert_eq(SaveCodec.read_int(data, "missing", 7), 7)
	assert_true(SaveCodec.is_int_like(3.0))
	assert_false(SaveCodec.is_int_like(3.5))
	assert_false(SaveCodec.is_int_like(1e300), "beyond exact double range")
