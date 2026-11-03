extends GutTest
## Every date script follows DialogueCheck's rules, and plays to its end
## down every response, at both spots, happy or not, first date or repeat,
## at every content level.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _resource(text: String) -> DialogueResource:
	var result: DMCompilerResult = DMCompiler.compile_string(text, "res://test.dialogue")
	assert_eq(result.errors.size(), 0, "the test script compiles")
	var resource: DialogueResource = DialogueResource.new()
	resource.using_states = result.using_states
	resource.cues = result.cues
	resource.lines = result.lines
	return resource


func _speakers() -> Array[String]:
	var out: Array[String] = []
	out.assign(data.ids("villagers"))
	return out


func _session(villager: String, spot: String, happy: bool, done: int, level: int) -> DateSession:
	var session: DateSession = DateSession.new()
	session.villager = villager
	session.spot = spot
	session.villager_happy = happy
	session.dates_done = done
	session.content_level = level
	session.max_gain = GameState.date_row(data, villager)["max_gain"]
	return session


func test_every_date_script_follows_the_rules() -> void:
	for id: String in data.ids("dates"):
		var date: Dictionary = data.row("dates", id)
		var path: String = date["script"]
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		if not ResourceLoader.exists(path):
			continue
		var resource: DialogueResource = load(path)
		assert_true(resource.cues.has(DateSession.TITLE), "%s has a ~ %s" % [path, DateSession.TITLE])
		assert_true(resource.cues.has(DateSession.INVITE), "%s has a ~ %s" % [path, DateSession.INVITE])
		assert_eq(DialogueCheck.static_problems(resource, DateSession.NAMES, _speakers()), PackedStringArray(), path)
		assert_eq(DialogueCheck.random_lines(resource, DateSession.TITLE), PackedStringArray(), "%s: no random lines" % path)


func test_every_date_plays_to_its_end_every_way() -> void:
	for id: String in data.ids("dates"):
		var date: Dictionary = data.row("dates", id)
		var villager: String = date["villager"]
		var resource: DialogueResource = load(str(date["script"]))
		var best: int = 0
		for spot: String in data.ids("date_spots"):
			for happy: bool in [true, false]:
				for done: int in [0, 1]:
					for level: int in ContentLevel.Level.values():
						var label: String = "%s at %s, happy %s, dates %d, level %d" % [villager, spot, happy, done, level]
						var make: Callable = _session.bind(villager, spot, happy, done, level)
						var walks: Array[DialogueCheck.Walk] = await DialogueCheck.walk_all(resource, DateSession.TITLE, make)
						assert_gt(walks.size(), 1, "%s: more than one way through" % label)
						for walk: DialogueCheck.Walk in walks:
							assert_true(walk.ended, "%s, path %s: reaches the end" % [label, walk.path])
							assert_gt(walk.choices, 0, "%s: offers a choice" % label)
							assert_false(walk.speakers.any(func(s: String) -> bool: return not s.is_empty() and s != villager and s != "koban"),
								"%s: only %s (or Koban) speaks" % [label, villager])
							var kept: int = mini(walk.gained + (date["finish_gain"] as int)
								+ (data.row("date_spots", spot)["bonus"] as int), date["max_gain"] as int)
							best = maxi(best, kept)
		assert_true(Affection.scene_unlocked(data, best), "%s: a date that goes well reaches the scene milestone" % villager)


func test_the_check_catches_reaching_outside_the_date() -> void:
	var resource: DialogueResource = _resource("~ date\nif Game.state.phase == 0\n\tpearl_diver: hi\ndo save()\nset affection = 9\nset affection -= 1\nstranger: who?\npearl_diver: [#face=smirk] hm\n=> END\n")
	var problems: String = "\n".join(DialogueCheck.static_problems(resource, DateSession.NAMES, _speakers()))
	assert_string_contains(problems, "\"Game\"")
	assert_string_contains(problems, "save()")
	assert_string_contains(problems, "affection only goes up")
	assert_string_contains(problems, "unknown speaker \"stranger\"")
	assert_string_contains(problems, "face \"smirk\"")
	assert_eq(problems.count("affection only goes up"), 2, "both = and -=")


func test_the_check_catches_using_and_random_lines() -> void:
	var resource: DialogueResource = _resource("using Game\n~ date\n% pearl_diver: one\n% pearl_diver: two\n=> END\n")
	assert_string_contains("\n".join(DialogueCheck.static_problems(resource, DateSession.NAMES, _speakers())), "using Game")
	assert_gt(DialogueCheck.random_lines(resource, DateSession.TITLE).size(), 0)


func test_the_walker_finds_a_dead_end() -> void:
	var resource: DialogueResource = _resource("~ date\npearl_diver: loop\n- Again\n\t=> date\n- Stop\n\t=> END\n")
	var walks: Array[DialogueCheck.Walk] = await DialogueCheck.walk_all(resource, DateSession.TITLE,
		_session.bind("pearl_diver", "cafe", true, 0, 0), 20)
	assert_false(walks.all(func(walk: DialogueCheck.Walk) -> bool: return walk.ended), "always picking Again never ends")
