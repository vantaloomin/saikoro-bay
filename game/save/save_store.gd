class_name SaveStore
extends RefCounted
## One save slot on disk, written atomically with a backup.
##
## Files, next to each other:
##   <path>      the save
##   <path>.tmp  a write in progress
##   <path>.bak  the previous good save
##
## A write goes: encode -> write .tmp -> flush and close -> read .tmp back and
## verify -> move the current save to .bak -> move .tmp to the save. A crash
## at any step leaves at least one good file, and read() finds it: the save
## first, then a verified .tmp (crash between the last two moves), then .bak.
##
## Writes are refused while `blocked` is set (scene flow sets it during the
## tide transition, so a save never captures half of each world), and when
## the slot holds a save from a newer game version, so an old build can't
## destroy newer progress.
##
## Limitation: Godot's FileAccess.flush() doesn't fsync. A power cut right
## after a write can still lose that write, but the verify step plus .bak
## mean it can't leave the slot with no readable save.

enum Source { NONE, MAIN, TEMP, BACKUP }

## Set by scene flow while a transition runs.
var blocked: bool = false

var path: String:
	get:
		return _path

var _path: String


class ReadResult:
	extends RefCounted
	var status: SaveCodec.Status = SaveCodec.Status.EMPTY
	var source: Source = Source.NONE
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


## Writes `payload`. Returns OK, or:
## ERR_BUSY (blocked), ERR_UNAUTHORIZED (slot holds a newer save),
## ERR_FILE_CANT_WRITE, ERR_FILE_CORRUPT (verify failed), ERR_FILE_CANT_OPEN.
func write(payload: Dictionary) -> Error:
	if blocked:
		return ERR_BUSY
	var current: SaveCodec.DecodeResult = _decode_file(_path)
	if current.status == SaveCodec.Status.TOO_NEW:
		return ERR_UNAUTHORIZED

	var dir_error: Error = DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if dir_error != OK:
		return dir_error

	var text: String = SaveCodec.encode(payload)
	var file: FileAccess = FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		return ERR_FILE_CANT_OPEN
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove(temp_path())
		return ERR_FILE_CANT_WRITE

	if not _decode_file(temp_path()).is_ok():
		_remove(temp_path())
		return ERR_FILE_CORRUPT

	if FileAccess.file_exists(_path):
		if current.is_ok():
			# The current save is good: it becomes the backup.
			_remove(backup_path())
			var to_backup: Error = DirAccess.rename_absolute(_path, backup_path())
			if to_backup != OK:
				return to_backup
		else:
			# The current save is damaged; keep the older good backup instead.
			_remove(_path)

	return DirAccess.rename_absolute(temp_path(), _path)


## Reads the best good copy: the save, then a verified .tmp, then .bak.
## If the save is from a newer version, returns TOO_NEW and no payload.
func read() -> ReadResult:
	var result: ReadResult = ReadResult.new()
	var main: SaveCodec.DecodeResult = _decode_file(_path)
	if main.status == SaveCodec.Status.TOO_NEW:
		result.status = main.status
		return result
	var candidates: Array[Array] = [
		[main, Source.MAIN],
		[_decode_file(temp_path()), Source.TEMP],
		[_decode_file(backup_path()), Source.BACKUP],
	]
	for candidate: Array in candidates:
		var decoded: SaveCodec.DecodeResult = candidate[0]
		if decoded.is_ok():
			result.status = SaveCodec.Status.OK
			result.source = candidate[1] as Source
			result.payload = decoded.payload
			return result
	# Nothing usable; report why the main file failed.
	result.status = main.status
	return result


## Deletes the slot and its temp and backup files.
func erase() -> void:
	_remove(_path)
	_remove(temp_path())
	_remove(backup_path())


static func _decode_file(file_path: String) -> SaveCodec.DecodeResult:
	if not FileAccess.file_exists(file_path):
		return SaveCodec.decode("")
	return SaveCodec.decode(FileAccess.get_file_as_string(file_path))


static func _remove(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
