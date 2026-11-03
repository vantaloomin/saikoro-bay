extends SceneTree
## Property test for delve maps (specs/delve-map.md 8a): generates maps for
## many seeds and fails if any map breaks a rule, or if the fixed template
## is needed too often.
##
##   godot --headless --path . -s res://tools/check_maps.gd -- [--seeds=N]
##
## Also checks the template itself against the current config, since its
## room plan is fixed but the rules come from data. Prints how many maps
## needed a redraw or the template, plus a hash of the data and the commit,
## so a change in the numbers can be traced to a data or a code change.


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
	var template_errors: PackedStringArray = DelveMap.template_errors(data.row("delve", "slice"), villagers, landmarks)
	for e: String in template_errors:
		printerr("template: " + e)
	# Every mix of full and empty pools, in turn: both full, no villagers
	# left, no landmarks left, both empty.
	var pools: Array = [[villagers, landmarks], [none, landmarks], [villagers, none], [none, none]]
	var bad: int = 0
	var redrawn: int = 0
	var templates: int = 0
	for s: int in range(1, seeds + 1):
		var pool: Array = pools[s % pools.size()]
		var map: DelveMap = DelveMap.generate(data, s, pool[0], pool[1])
		var errors: PackedStringArray = map.map_errors()
		if not errors.is_empty():
			bad += 1
			if bad <= 5:
				printerr("%s: %s" % [JSON.stringify(map.inputs()), "; ".join(errors)])
		if map.attempt > 0:
			redrawn += 1
		elif map.attempt < 0:
			templates += 1
	print(JSON.stringify({
		"seeds": seeds, "invalid": bad, "redrawn": redrawn, "template": templates,
		"template_valid": template_errors.is_empty(),
		"villagers": villagers, "landmarks": landmarks,
		"data_hash": _data_hash(), "commit": OS.get_environment("GITHUB_SHA"),
	}, "  "))
	# The template is a safety net: more than 1 in 1,000 means the rules or
	# weights fight each other.
	quit(1 if bad > 0 or templates * 1000 > seeds or not template_errors.is_empty() else 0)


static func _data_hash() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for file: String in ["delve.json", "rooms.json", "villagers.json", "landmarks.json", "resources.json"]:
		ctx.update(FileAccess.get_file_as_bytes("res://data/" + file))
	return ctx.finish().hex_encode().substr(0, 12)
