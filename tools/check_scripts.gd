extends SceneTree
## Loads every GDScript file outside addons/ so parse errors and
## warnings-as-errors fail CI, even in scripts no test touches yet.
##
## Run: godot --headless --path . -s res://tools/check_scripts.gd

const SKIP_DIRS: PackedStringArray = ["res://addons", "res://.godot"]


func _initialize() -> void:
	# Check on the first frame, once autoloads (Game, SceneFlow) are registered.
	process_frame.connect(_check_all, CONNECT_ONE_SHOT)


func _check_all() -> void:
	var files: PackedStringArray = []
	_collect("res://", files)
	var failed: int = 0
	for path: String in files:
		var script: Script = ResourceLoader.load(path) as Script
		if script == null or not script.can_instantiate():
			printerr("FAILED: ", path)
			failed += 1
	print("Checked %d scripts, %d failed." % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	if dir_path in SKIP_DIRS:
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))

