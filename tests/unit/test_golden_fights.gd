extends GutTest
## The fight rules still play every golden fight exactly as recorded
## (tests/golden/golden_fights.gd): same moves, events, end state and
## previews, both played live by the bots and replayed from the move log.

var data: GameData
var golden: Array = []


func before_all() -> void:
	data = GameData.load_dir()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GoldenFights.PATH))
	if parsed is Dictionary:
		golden = (parsed as Dictionary).get("fights", []) as Array


func test_the_fixtures_cover_every_case() -> void:
	assert_eq(golden.size(), GoldenFights.cases(data).size())
	assert_gt(golden.size(), 0)


func test_bots_play_every_golden_fight_the_same_way() -> void:
	var cases: Array[Dictionary] = GoldenFights.cases(data)
	var mismatches: PackedStringArray = []
	for i: int in mini(cases.size(), golden.size()):
		var expected: Dictionary = golden[i]
		var actual: Dictionary = GoldenFights.play(data, cases[i])
		for key: String in ["bot", "enemy", "perks", "seed", "moves", "events", "end", "previews"]:
			var want: Variant = int(expected.get(key)) if key == "seed" else expected.get(key)
			if str(actual.get(key)) != str(want):
				mismatches.append("%s %s %s seed %s: %s differs" % [expected["bot"], expected["enemy"], expected["perks"], expected["seed"], key])
				break
	assert_eq(mismatches.size(), 0, "\n".join(mismatches.slice(0, 10)))


func test_every_golden_move_log_replays_to_the_same_events() -> void:
	var failures: PackedStringArray = []
	for expected: Dictionary in golden:
		var perks: Array[Dictionary] = []
		perks.assign(GoldenFights.PERK_SETS[expected["perks"]])
		var rng: RngStreams = RngStreams.new(int(expected["seed"]))
		var fight: Fight = Fight.create(data, GoldenFights.LOADOUT, expected["enemy"], rng, perks)
		if not fight.apply_moves(_decode(str(expected["moves"]))):
			failures.append("seed %s: a move was refused" % expected["seed"])
			continue
		if GoldenFights.hash_of(fight.events) != expected["events"] or GoldenFights.hash_of(GoldenFights.end_state(fight, rng)) != expected["end"]:
			failures.append("%s %s seed %s: replay differs" % [expected["bot"], expected["enemy"], expected["seed"]])
	assert_eq(failures.size(), 0, "\n".join(failures.slice(0, 10)))


static func _decode(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part: String in text.split(" ", false):
		match part[0]:
			"p":
				var bits: PackedStringArray = part.substr(1).split(":")
				out.append({"move": "place", "die": bits[0].to_int(), "slot": bits[1]})
			"t":
				out.append({"move": "take_back", "die": part.substr(1).to_int()})
			"r":
				out.append({"move": "reroll", "die": part.substr(1).to_int()})
			"n":
				out.append({"move": "nudge", "die": part.substr(1).to_int()})
			"e":
				out.append({"move": "end_turn"})
	return out
