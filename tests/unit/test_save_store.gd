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


func test_blocked_write_is_held_until_unblocked() -> void:
	store.write({"coins": 1})
	store.blocked = true
	assert_eq(store.write({"coins": 2}), ERR_BUSY)
	assert_true(store.has_pending_write())
	assert_eq(_coins_in(store.path), 1, "nothing written while blocked")
	watch_signals(store)
	store.blocked = false
	assert_signal_emitted_with_parameters(store, "deferred_write_finished", [OK])
	assert_false(store.has_pending_write())
	assert_eq(_coins_in(store.path), 2)


func test_only_the_latest_held_write_runs() -> void:
	store.blocked = true
	store.write({"coins": 1})
	store.write({"coins": 2})
	store.blocked = false
	assert_eq(_coins_in(store.path), 2)
	assert_eq(_seq_in(store.path), 1, "one write, not two")


func test_seq_goes_up_with_each_write() -> void:
	for i: int in 3:
		store.write({"coins": i})
	assert_eq(_seq_in(store.path), 3)
	assert_eq(_seq_in(store.backup_path()), 2)
	assert_eq(store.read().seq, 3)


func test_newest_copy_wins_wherever_it_is() -> void:
	# A failed move (say, a locked file on Windows) leaves the newest save in
	# .tmp next to an older main file: read() must serve the .tmp.
	store.write({"coins": 1})
	_write_raw(store.temp_path(), SaveCodec.encode({"coins": 2}, 5))
	var result: SaveStore.ReadResult = store.read()
	assert_eq(result.source, SaveStore.Source.TEMP)
	assert_eq(SaveCodec.read_int(result.payload, "coins"), 2)


func test_newer_temp_is_promoted_before_the_next_write() -> void:
	store.write({"coins": 1})
	_write_raw(store.temp_path(), SaveCodec.encode({"coins": 2}, 5))
	assert_eq(store.write({"coins": 3}), OK)
	assert_eq(_coins_in(store.path), 3)
	assert_eq(_seq_in(store.path), 6, "numbered after the highest copy")
	assert_eq(_coins_in(store.backup_path()), 2, "the promoted .tmp became the backup")


func test_stale_temp_is_ignored_and_replaced() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2})
	_write_raw(store.temp_path(), SaveCodec.encode({"coins": 99}, 1))
	assert_eq(SaveCodec.read_int(store.read().payload, "coins"), 2)
	assert_eq(store.write({"coins": 3}), OK)
	assert_eq(_coins_in(store.path), 3)
	assert_eq(_coins_in(store.backup_path()), 2)


func test_newer_save_is_never_overwritten() -> void:
	var newer: String = _newer_version_text()
	DirAccess.make_dir_recursive_absolute(DIR)
	_write_raw(store.path, newer)
	assert_eq(store.read().status, SaveCodec.Status.TOO_NEW)
	assert_eq(store.write({"coins": 1}), ERR_UNAUTHORIZED)
	assert_eq(FileAccess.get_file_as_string(store.path), newer, "file untouched")


func test_newer_copy_in_temp_or_backup_also_locks_the_slot() -> void:
	# A newer build crashed between its moves: no main file, newer copies in
	# .tmp and .bak. An older build must not treat the slot as empty.
	var newer: String = _newer_version_text()
	DirAccess.make_dir_recursive_absolute(DIR)
	_write_raw(store.temp_path(), newer)
	_write_raw(store.backup_path(), newer)
	assert_eq(store.read().status, SaveCodec.Status.TOO_NEW)
	assert_eq(store.write({"coins": 1}), ERR_UNAUTHORIZED)
	assert_eq(FileAccess.get_file_as_string(store.temp_path()), newer)
	assert_eq(FileAccess.get_file_as_string(store.backup_path()), newer)
	assert_false(FileAccess.file_exists(store.path))


func test_erase_removes_everything() -> void:
	store.write({"coins": 1})
	store.write({"coins": 2})
	store.erase()
	assert_false(store.exists())


func _coins_in(file_path: String) -> int:
	var decoded: SaveCodec.DecodeResult = SaveCodec.decode(FileAccess.get_file_as_string(file_path))
	return SaveCodec.read_int(decoded.payload, "coins", -1)


func _seq_in(file_path: String) -> int:
	return SaveCodec.decode(FileAccess.get_file_as_string(file_path)).seq


func _newer_version_text() -> String:
	var body: String = "{}"
	return JSON.stringify({
		"format": SaveCodec.FORMAT,
		"version": SaveCodec.CURRENT_VERSION + 1,
		"seq": 1,
		"sha256": body.sha256_text(),
	}) + "\n" + body + "\n"


func _write_raw(file_path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
