extends SceneTree
## Property test for delve maps (specs/delve-map.md 8a): generates maps for
## many seeds and fails if any map breaks a rule, or if the fixed template
## is needed too often.
##
##   godot --headless --path . -s res://tools/check_maps.gd -- [--seeds=N]
##
## Prints how many maps needed a redraw or the template, plus a hash of the
## data, so a change in the numbers can be traced to a data change.


func _initialize() -> void:
	var seeds: int = 10000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = arg.substr(8).to_int()
	var data: GameData = GameData.load_dir()
	if not data.is_valid():
		printerr("\n".join(data.errors))
		quit(2)
		return
	var villagers: Array[String] = []
	villagers.assign(Array(data.ids("villagers")))
	var landmarks: Array[String] = []
	landmarks.assign(Array(data.ids("landmarks")))
	var none: Array[String] = []
	var bad: int = 0
	var redrawn: int = 0
	var templates: int = 0
	for s: int in range(1, seeds + 1):
		# Alternate full and empty pools so both paths are covered.
		var full: bool = s % 2 == 0
		var map: DelveMap = DelveMap.generate(data, s, villagers if full else none, landmarks if full else none)
		var errors: PackedStringArray = map.map_errors()
		if not errors.is_empty():
			bad += 1
			if bad <= 5:
				printerr("seed %d: %s" % [s, "; ".join(errors)])
		if map.attempt > 0:
			redrawn += 1
		elif map.attempt < 0:
			templates += 1
	print(JSON.stringify({
		"seeds": seeds, "invalid": bad, "redrawn": redrawn, "template": templates,
		"data_hash": _data_hash(),
	}, "  "))
	# The template is a safety net: more than 1 in 1,000 means the rules or
	# weights fight each other.
	quit(1 if bad > 0 or templates * 1000 > seeds else 0)


static func _data_hash() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for file: String in ["delve.json", "rooms.json", "villagers.json", "landmarks.json"]:
		ctx.update(FileAccess.get_file_as_bytes("res://data/" + file))
	return ctx.finish().hex_encode().substr(0, 12)
