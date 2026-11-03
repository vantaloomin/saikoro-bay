extends GutTest
## The delve bot (specs/delve-map.md section 7): its path and landing
## rules, that it only sees what the player sees, and the whole-map
## scenario the balance band runs.

const VILLAGERS: Array[String] = ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _run(seed_value: int) -> DelveRun:
	var run: DelveRun = DelveRun.create(data, seed_value, Kit.fresh(data), VILLAGERS, LANDMARKS, 0)
	assert_not_null(run)
	return run


## Sets the first row's room types (and makes every first-row room lead to
## the same rooms below, so only the first row decides).
func _first_row(run: DelveRun, types: Array[String]) -> void:
	for c: int in types.size():
		run.map.room(0, 0, c).type = types[c]


func _wide_run() -> DelveRun:
	for s: int in range(1, 200):
		var run: DelveRun = _run(s)
		if run.map.width(0, 0) == 3:
			return run
	fail_test("no map with a three-room first row")
	return null


func test_it_takes_a_treasure_over_a_fight() -> void:
	var run: DelveRun = _wide_run()
	_first_row(run, [DelveMap.FIGHT, DelveMap.TREASURE, DelveMap.FIGHT] as Array[String])
	assert_eq(DelveBot.new().choose_room(RunView.new(run)), 1)


func test_it_heads_for_a_rest_when_hurt() -> void:
	var run: DelveRun = _wide_run()
	_first_row(run, [DelveMap.TREASURE, DelveMap.FIGHT, DelveMap.REST] as Array[String])
	assert_eq(DelveBot.new().choose_room(RunView.new(run)), 0, "healthy: treasure")
	run.hp = 10
	assert_eq(DelveBot.new().choose_room(RunView.new(run)), 2, "hurt: the rest")


func test_it_avoids_the_elite_unless_healthy() -> void:
	var run: DelveRun = _wide_run()
	_first_row(run, [DelveMap.ELITE, DelveMap.FIGHT, DelveMap.ELITE] as Array[String])
	run.hp = 20
	assert_eq(DelveBot.new().choose_room(RunView.new(run)), 1)
	run.hp = 30
	assert_ne(DelveBot.new().choose_room(RunView.new(run)), 1, "over 70%: the elite is fair game")


func test_landings_surface_when_low() -> void:
	for s: int in range(1, 80):
		var run: DelveRun = _run(s)
		var bot: DelveBot = DelveBot.new()
		for guard: int in 40:
			if run.step == DelveRun.Step.CHOOSE_ROOM:
				run.choose(bot.choose_room(RunView.new(run)))
			elif run.step == DelveRun.Step.IN_ROOM:
				if run.fight != null:
					GreedyBot.new().play_fight(run.fight)
				if run.room != null:
					RoomBot.new().play_room(run.room)
				run.finish_room()
			else:
				break
		if run.step != DelveRun.Step.LANDING:
			continue
		run.hp = 30
		assert_eq(bot.at_landing(RunView.new(run)), "deeper")
		run.hp = 8
		assert_eq(bot.at_landing(RunView.new(run)), "surface", "under 30%")
		run.hp = 14
		var next_row: Array = (RunView.new(run).peek()["rows"] as Array)[0]
		var safe: bool = next_row.has(DelveMap.REST) or next_row.has(DelveMap.TREASURE)
		assert_eq(bot.at_landing(RunView.new(run)), "deeper" if safe else "surface", "under half: only toward a rest or treasure")
		return
	fail_test("no seed reached a landing")


func test_hidden_rooms_never_change_its_choices() -> void:
	# Imogen's rule 4: shuffling what the player can't see changes nothing.
	for s: int in range(1, 41):
		var run: DelveRun = _run(s)
		var view: RunView = RunView.new(run)
		var before: int = DelveBot.new().choose_room(view)
		for rm: DelveMap.Room in run.map.all_rooms():
			if rm.floor_index > 0 or rm.row > run.row + run.reveal_rows:
				rm.type = DelveMap.REST if rm.type != DelveMap.REST else DelveMap.ELITE
		assert_eq(DelveBot.new().choose_room(view), before, "seed %d" % s)


func test_the_map_scenario_plays_whole_delves_the_same_way_twice() -> void:
	var scenario: MapDelveScenario = MapDelveScenario.new(data, GreedyBot.new())
	var report: BotHarness.Report = BotHarness.run(scenario, 1, 30, 3)
	assert_eq(report.nondeterministic_seeds, [] as Array[int])
	assert_eq(report.counters.get("stalemates", 0), 0)
	var ended: int = report.wins + report.counters.get("washed_up", 0)
	for floor_number: int in [1, 2]:
		ended += report.counters.get("surfaced_floor_%d" % floor_number, 0)
	assert_eq(ended, 30, "every delve ends: cleared, washed up or surfaced")
	assert_gt(report.counters.get("reached_vault", 0), 0)
	assert_gt(report.counters.get("rooms:treasure", 0), 0)


func test_a_delve_that_cant_go_on_counts_as_stuck() -> void:
	var scenario: MapDelveScenario = MapDelveScenario.new(data, GreedyBot.new())
	scenario.delve_bot = StuckBot.new()
	var outcome: BotScenario.Outcome = scenario.play(RngStreams.new(1))
	assert_eq(outcome.counters.get("stuck", 0), 1)
	assert_false(outcome.won)


class StuckBot:
	extends DelveBot

	func choose_room(_view: RunView) -> int:
		return -1
