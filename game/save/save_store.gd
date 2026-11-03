class_name SaveStore
extends RefCounted
## One save slot on disk, written atomically with a backup.
##
## Files, next to each other:
##   <path>      the save
##   <path>.tmp  a write in progress
##   <path>.bak  the previous good save
##
## Every write carries a sequence number one higher than any copy in the
## slot. read() returns the good copy with the highest number, wherever it
## sits, so a crash or a failed move at any step serves the newest complete
## save rather than whichever file happens to be named "the save".
##
## A write goes: promote a newer .tmp left from last time -> encode -> write
## .tmp -> flush and close -> read .tmp back and verify -> move the save to
## .bak -> move .tmp to the save. Moves are retried, because on Windows a
## virus scanner or cloud sync can hold a file for a moment. A failed write
## never deletes the newest good copy.
##
## While `blocked` (scene flow sets it during the tide transition, so a save
## never captures half of each world), write() refuses. write_when_ready()
## instead holds a payload *builder* and calls it when the block clears, so
## the save captures the settled state, not the state at request time. Nothing is ever written to a slot holding a
## copy from a newer game version, so an old build can't destroy newer
## progress.
##
## Limitation: Godot's FileAccess.flush() doesn't fsync. A power cut right
## after a write can still lose that write, but the verify step plus .bak
## mean it can't leave the slot with no readable save.

## Emitted after a held write_when_ready() runs, with its result.
signal deferred_write_finished(error: Error)

enum Source { NONE, MAIN, TEMP, BACKUP }

const RENAME_ATTEMPTS: int = 3
const RENAME_RETRY_MSEC: int = 50

## Set by scene flow while a transition runs. Clearing it runs any held
## write_when_ready() builder.
var blocked: bool = false:
	set(value):
		blocked = value
		if not blocked and _pending.is_valid():
			var build: Callable = _pending
			_pending = Callable()
			deferred_write_finished.emit(write(build.call() as Dictionary))

var path: String:
	get:
		return _path

var _path: String
var _pending: Callable = Callable()


class ReadResult:
	extends RefCounted
	var status: SaveCodec.Status = SaveCodec.Status.EMPTY
	var source: Source = Source.NONE
	var seq: int = 0
	var payload: Dictionary = {}

	func is_ok() -> bool:
		return status == SaveCodec.Status.OK


func _init(save_path: String) -> void:
	_path = save_path


func temp_path() -> String:
	return _path + ".tmp"


func backup_path() -> String:
	return _path + ".bak"


func exists() -> bool:
	return FileAccess.file_exists(_path) or FileAccess.file_exists(temp_path()) \
		or FileAccess.file_exists(backup_path())


## Runs a held write_when_ready() builder now, leaving `blocked` as it is
## (for the window closing mid-transition). Returns its write's result, or
## OK if nothing was held.
func flush() -> Error:
	if not _pending.is_valid():
		return OK
	var build: Callable = _pending
	_pending = Callable()
	var was_blocked: bool = blocked
	blocked = false
	var error: Error = write(build.call() as Dictionary)
	blocked = was_blocked
	return error


## True while a write_when_ready() builder is waiting for the block to clear.
func has_pending_write() -> bool:
	return _pending.is_valid()


## Writes the payload `build` returns: now if not blocked, otherwise when
## `blocked` clears (only the latest request is kept). Returns write()'s
## result, or ERR_BUSY if it was held; the held result arrives through
## deferred_write_finished.
func write_when_ready(build: Callable) -> Error:
	if blocked:
		_pending = build
		return ERR_BUSY
	return write(build.call() as Dictionary)


## Writes `payload` now. Returns OK, or:
## ERR_BUSY (blocked; nothing is written or held, see write_when_ready()),
## ERR_UNAUTHORIZED (the slot holds a newer-version copy),
## ERR_FILE_CANT_OPEN / ERR_FILE_CANT_WRITE / ERR_FILE_CORRUPT (verify failed),
## or a move error after retries (the new save is then kept in .tmp, and
## read() still returns it).
func write(payload: Dictionary) -> Error:
	if blocked:
		return ERR_BUSY

	var copies: Dictionary[Source, SaveCodec.DecodeResult] = _decode_all()
	if _any_too_new(copies):
		return ERR_UNAUTHORIZED

	# A .tmp newer than the save is left from a crash or a failed move. Make
	# it the save first, so writing the new .tmp can't destroy it.
	if _temp_beats_main(copies):
		var promote_error: Error = _replace_main(copies[Source.MAIN])
		if promote_error != OK:
			return promote_error
		copies = _decode_all()

	var dir_error: Error = DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if dir_error != OK:
		return dir_error

	var next_seq: int = _highest_seq(copies) + 1
	var file: FileAccess = FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		return ERR_FILE_CANT_OPEN
	file.store_string(SaveCodec.encode(payload, next_seq))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove(temp_path())
		return ERR_FILE_CANT_WRITE

	var written: SaveCodec.DecodeResult = _decode_file(temp_path())
	if not written.is_ok() or written.seq != next_seq:
		_remove(temp_path())
		return ERR_FILE_CORRUPT

	return _replace_main(copies[Source.MAIN])


## Reads the good copy with the highest sequence number. If any copy is from
## a newer game version, returns TOO_NEW and no payload.
func read() -> ReadResult:
	var result: ReadResult = ReadResult.new()
	var copies: Dictionary[Source, SaveCodec.DecodeResult] = _decode_all()
	if _any_too_new(copies):
		result.status = SaveCodec.Status.TOO_NEW
		return result
	# On equal numbers, prefer the save, then .tmp, then .bak.
	for source: Source in [Source.MAIN, Source.TEMP, Source.BACKUP]:
		var decoded: SaveCodec.DecodeResult = copies[source]
		if decoded.is_ok() and (not result.is_ok() or decoded.seq > result.seq):
			result.status = SaveCodec.Status.OK
			result.source = source
			result.seq = decoded.seq
			result.payload = decoded.payload
	if not result.is_ok():
		# Nothing usable; report why the save itself failed.
		result.status = copies[Source.MAIN].status
	return result


## Deletes the slot and its temp and backup files, and drops a held write.
func erase() -> void:
	_pending = Callable()
	_remove(_path)
	_remove(temp_path())
	_remove(backup_path())


## Moves the current save aside (to .bak if it's good, deleted if it's
## damaged) and moves .tmp into its place.
func _replace_main(main: SaveCodec.DecodeResult) -> Error:
	if FileAccess.file_exists(_path):
		if main.is_ok():
			_remove(backup_path())
			var to_backup: Error = _rename_with_retry(_path, backup_path())
			if to_backup != OK:
				return to_backup
		else:
			# A damaged save never becomes the backup.
			_remove(_path)
	return _rename_with_retry(temp_path(), _path)


func _decode_all() -> Dictionary[Source, SaveCodec.DecodeResult]:
	var copies: Dictionary[Source, SaveCodec.DecodeResult] = {}
	copies[Source.MAIN] = _decode_file(_path)
	copies[Source.TEMP] = _decode_file(temp_path())
	copies[Source.BACKUP] = _decode_file(backup_path())
	return copies


static func _any_too_new(copies: Dictionary[Source, SaveCodec.DecodeResult]) -> bool:
	for source: Source in copies:
		if copies[source].status == SaveCodec.Status.TOO_NEW:
			return true
	return false


static func _temp_beats_main(copies: Dictionary[Source, SaveCodec.DecodeResult]) -> bool:
	var temp: SaveCodec.DecodeResult = copies[Source.TEMP]
	var main: SaveCodec.DecodeResult = copies[Source.MAIN]
	return temp.is_ok() and (not main.is_ok() or temp.seq > main.seq)


static func _highest_seq(copies: Dictionary[Source, SaveCodec.DecodeResult]) -> int:
	var highest: int = 0
	for source: Source in copies:
		if copies[source].is_ok():
			highest = maxi(highest, copies[source].seq)
	return highest


static func _decode_file(file_path: String) -> SaveCodec.DecodeResult:
	if not FileAccess.file_exists(file_path):
		return SaveCodec.decode("")
	return SaveCodec.decode(FileAccess.get_file_as_string(file_path))


static func _rename_with_retry(from: String, to: String) -> Error:
	var error: Error = FAILED
	for attempt: int in RENAME_ATTEMPTS:
		if attempt > 0:
			OS.delay_msec(RENAME_RETRY_MSEC)
		error = DirAccess.rename_absolute(from, to)
		if error == OK:
			return OK
	return error


static func _remove(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
