extends GutTest
## Every date script follows DialogueCheck's rules, and plays to its end
## down every response, at both spots, happy or not, first date or repeat.
## Every other script under res://dialogue/ follows the static rules too.

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


func _session(villager: String, spot: String, happy: bool, done: int) -> DateSession:
	var session: DateSession = DateSession.new()
	session.villager = villager
	session.spot = spot
	session.villager_happy = happy
	session.dates_done = done
	session.max_gain = GameState.date_row(data, villager)["max_gain"]
	session.seal()
	return session


func _problems(text: String) -> String:
	return "\n".join(DialogueCheck.static_problems(_resource(text), DateSession.NAMES, _speakers()))


## Every .dialogue file under `dir`, however deep.
func _dialogue_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "dialogue":
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_dialogue_files(dir.path_join(sub)))
	return out


func test_every_script_under_dialogue_follows_the_static_rules() -> void:
	var files: Array[String] = _dialogue_files("res://dialogue")
	assert_gt(files.size(), 0, "found the scripts")
	for path: String in files:
		var resource: DialogueResource = load(path)
		assert_eq(DialogueCheck.static_problems(resource, DateSession.NAMES, _speakers()), PackedStringArray(), path)


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
					var label: String = "%s at %s, happy %s, dates %d" % [villager, spot, happy, done]
					var make: Callable = _session.bind(villager, spot, happy, done)
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
	assert_string_contains(problems, "unknown speaker \"stranger\"")
	assert_string_contains(problems, "face \"smirk\"")
	assert_eq(problems.count("affection += n"), 2, "both = and -=")


func test_the_check_catches_using_and_random_lines() -> void:
	var resource: DialogueResource = _resource("using Game\n~ date\n% pearl_diver: one\n% pearl_diver: two\n=> END\n")
	assert_string_contains("\n".join(DialogueCheck.static_problems(resource, DateSession.NAMES, _speakers())), "using Game")
	assert_gt(DialogueCheck.random_lines(resource, DateSession.TITLE).size(), 0)


func test_the_walker_finds_a_dead_end() -> void:
	var resource: DialogueResource = _resource("~ date\npearl_diver: loop\n- Again\n\t=> date\n- Stop\n\t=> END\n")
	var walks: Array[DialogueCheck.Walk] = await DialogueCheck.walk_all(resource, DateSession.TITLE,
		_session.bind("pearl_diver", "cafe", true, 0), 20)
	assert_false(walks.all(func(walk: DialogueCheck.Walk) -> bool: return walk.ended), "always picking Again never ends")


# Imogen's PR 1 audit probes: each must be reported, with no engine error
# (GUT fails the test on one, so the check fails closed).
func test_the_check_allows_no_write_but_affection_up() -> void:
	var probes: Dictionary = {
		"set content_level = 2": "content_level",
		"set spot = \"x\"": "affection += n",
		"set villager_happy = false": "affection += n",
		"set dates_done = 0": "affection += n",
		"set affection += 1, dates_done = 0": "affection += n",
		"set affection += 1, spot = 0": "affection += n",
		"set spot = 0, affection += 1": "affection += n",
	}
	for probe: String in probes:
		var problems: String = _problems("~ date\npearl_diver: hi\n%s\n=> END\n" % probe)
		assert_string_contains(problems, probes[probe], probe)
	assert_string_contains(_problems("~ date\npearl_diver: hi [set content_level = 2]\n=> END\n"), "inline", "inline set")
	assert_string_contains(_problems("~ date\npearl_diver: hi [set spot = \"x\"]\n=> END\n"), "inline", "inline set")
	assert_string_contains(_problems("~ date\npearl_diver: hi\n- Sure [do! save()]\n\t=> END\n"), "inline", "inline do in a response")
	assert_string_contains(_problems("~ date\npearl_diver: hi [if content_level > 0]warm[/if]\n=> END\n"), "inline", "inline if")
	assert_string_contains(_problems("~ date\ndo Game.state.add_resource(1)\n=> END\n"), "\"Game\"", "do reaches Game")
	assert_eq(_problems("~ date\npearl_diver: hi {{spot}}\nset affection += 2\n=> END\n"), "", "reading a name and raising affection are fine")


func test_the_check_bans_content_level() -> void:
	var problems: String = _problems("~ date\nif content_level > 0\n\tpearl_diver: warm\nelse\n\tpearl_diver: mild\n=> END\n")
	assert_string_contains(problems, "content_level")
	assert_eq(_problems("~ date\nif dates_done == \"x\"\n\tpearl_diver: hm\n=> END\n"), "", "a mismatched compare is the walker's business, not a crash")


func test_a_sealed_session_ignores_writes_but_affection() -> void:
	var session: DateSession = _session("pearl_diver", "cafe", true, 1)
	session.spot = "hot_spring"
	session.villager_happy = false
	session.dates_done = 0
	session.content_level = ContentLevel.Level.FULL
	session.affection += 1
	assert_eq([session.spot, session.villager_happy, session.dates_done, session.content_level, session.affection],
		["cafe", true, 1, ContentLevel.Level.SFW, 1])
	session.follow_content_level(ContentLevel.Level.FULL)
	assert_eq(session.content_level, ContentLevel.Level.FULL, "the game can still follow the setting")
