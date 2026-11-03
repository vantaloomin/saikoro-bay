extends GutTest
## SaveStore: atomic writes, backups and recovery from damaged files.

const DIR: String = "user://test_saves"
var store: SaveStore


func before_each() -> void:
	store = SaveStore.new(DIR.path_join("slot_test.save"))
	store.erase()


func after_each() -> void:
	store.erase()


func test_write_then_read() -> void:
	assert_eq(store.write({"coins": 3}), OK)
	var result: SaveStore.ReadResult = store.read()
	assert_true(result.is_ok())
	assert_eq(result.source, SaveStore.Source.MAIN)
	assert_eq(SaveCodec.read_int(result.payload, "coins"), 3)
	assert_false(FileAccess.file_exists(store.temp_path()), "no temp file left behind")


func test_reading_an_empty_slot() -> void:
	var result: SaveStore.ReadResult = store.read()
	assert_eq(result.status, SaveCodec.Status.EMPTY)
	assert_eq(result.source, SaveStore.Source.NONE)
	assert_false(store.exists())


func test_second_write_keeps_previous_as_backup() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2})
	assert_eq(_coins_in(store.path), 2)
	assert_eq(_coins_in(store.backup_path()), 1)


func test_corrupt_save_falls_back_to_backup() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2})
	_write_raw(store.path, "garbage")
	var result: SaveStore.ReadResult = store.read()
	assert_true(result.is_ok())
	assert_eq(result.source, SaveStore.Source.BACKUP)
	assert_eq(SaveCodec.read_int(result.payload, "coins"), 1)


func test_truncated_save_falls_back_to_backup() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2, "padding": "some extra text so the cut lands in the payload"})
	var text: String = FileAccess.get_file_as_string(store.path)
	_write_raw(store.path, text.substr(0, text.length() - 10))
	var result: SaveStore.ReadResult = store.read()
	assert_eq(result.source, SaveStore.Source.BACKUP)


func test_crash_between_moves_recovers_from_temp() -> void:
	# Simulate a crash after the old save moved to .bak but before .tmp moved
	# into place: no main file, a complete .tmp and an older .bak.
	store.write({"coins": 1})
	store.write({"coins": 2})
	DirAccess.rename_absolute(store.path, store.temp_path())
	var result: SaveStore.ReadResult = store.read()
	assert_true(result.is_ok())
	assert_eq(result.source, SaveStore.Source.TEMP)
	assert_eq(SaveCodec.read_int(result.payload, "coins"), 2, "the newest complete write wins")


func test_half_written_temp_is_ignored() -> void:
	store.write({"coins": 1})
	_write_raw(store.temp_path(), "{\"format\":\"saikoro-bay-save\"")
	var result: SaveStore.ReadResult = store.read()
	assert_eq(result.source, SaveStore.Source.MAIN)
	assert_eq(SaveCodec.read_int(result.payload, "coins"), 1)


func test_writing_over_a_corrupt_save_keeps_the_good_backup() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2})
	_write_raw(store.path, "garbage")
	assert_eq(store.write({"coins": 3}), OK)
	assert_eq(_coins_in(store.path), 3)
	assert_eq(_coins_in(store.backup_path()), 1, "garbage never becomes the backup")


func test_blocked_store_refuses_writes() -> void:
	store.write({"coins": 1})
	store.blocked = true
	assert_eq(store.write({"coins": 2}), ERR_BUSY)
	assert_eq(_coins_in(store.path), 1)
	store.blocked = false
	assert_eq(store.write({"coins": 2}), OK)


func test_newer_save_is_never_overwritten() -> void:
	var body: String = "{}"
	var newer: String = JSON.stringify({
		"format": SaveCodec.FORMAT,
		"version": SaveCodec.CURRENT_VERSION + 1,
		"sha256": body.sha256_text(),
	}) + "\n" + body + "\n"
	DirAccess.make_dir_recursive_absolute(DIR)
	_write_raw(store.path, newer)
	assert_eq(store.read().status, SaveCodec.Status.TOO_NEW)
	assert_eq(store.write({"coins": 1}), ERR_UNAUTHORIZED)
	assert_eq(FileAccess.get_file_as_string(store.path), newer, "file untouched")


func test_erase_removes_everything() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2})
	store.erase()
	assert_false(store.exists())


func _coins_in(file_path: String) -> int:
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(FileAccess.get_file_as_string(file_path))
	return SaveCodec.read_int(decoded.payload, "coins", -1)


func _write_raw(file_path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
