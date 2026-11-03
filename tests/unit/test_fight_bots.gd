extends GutTest
## The balance bots: they play only legal moves, never touch the dice
## streams while planning, and play the same seed the same way every time.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _fight(enemy: String, seed_value: int, perks: Array[Dictionary] = []) -> Fight:
	return Fight.create(data, "fresh", enemy, RngStreams.new(seed_value), perks)


func test_bots_by_name() -> void:
	assert_eq(FightBot.make("greedy").name(), "greedy")
	assert_eq(FightBot.make("planner").name(), "planner")
	assert_null(FightBot.make("nope"))


func test_bots_finish_fights_with_legal_moves_only() -> void:
	for bot_name: String in ["greedy", "planner"]:
		for enemy: String in data.ids("enemies"):
			for seed_value: int in 5:
				var fight: Fight = _fight(enemy, seed_value, [{"perk": "nudge", "source": "pearl_diver"}])
				var turns: int = FightBot.make(bot_name).play_fight(fight)
				assert_gt(turns, 0, "%s vs %s seed %d ends" % [bot_name, enemy, seed_value])
				# Every move the bot made replays on a fresh fight, so all were legal.
				var replay: Fight = _fight(enemy, seed_value, [{"perk": "nudge", "source": "pearl_diver"}])
				assert_true(replay.apply_moves(fight.moves))
				assert_eq(replay.state, fight.state)


func test_planning_never_moves_the_dice_streams() -> void:
	var fight: Fight = _fight("hermit_croupier", 3, [{"perk": "nudge", "source": "pearl_diver"}])
	var before: Dictionary = fight._rng.to_dict()
	var events: int = fight.events.size()
	PlannerBot.new().best_plan(fight, true)
	assert_eq(fight._rng.to_dict(), before)
	assert_eq(fight.events.size(), events, "planning doesn't touch the real fight")
	assert_true(fight.moves.is_empty())


func test_planner_finds_the_lethal_turn() -> void:
	var fight: Fight = _fight("card_shark", 1)
	fight.enemy_hp = 8
	for i: int in 4:
		fight.hand[i].value = [1, 5, 2, 3][i]
	PlannerBot.new().play_turn(fight)
	fight.end_turn()
	assert_eq(fight.state, Fight.State.WON, "High Roller on the 5 wins outright")


func test_reroll_outcomes_cover_every_roll() -> void:
	var faces: Array[int] = [1, 2, 3, 4, 5, 6]
	for count: int in [1, 2, 3]:
		var outcomes: Array[Array] = PlannerBot._outcomes(faces, count)
		var total: int = 0
		for outcome: Array in outcomes:
			total += outcome[1] as int
		assert_eq(total, int(pow(6, count)), "%d dice" % count)
	assert_eq(PlannerBot._outcomes(faces, 3).size(), 56)


func test_scenarios_are_deterministic_and_count_per_enemy() -> void:
	var scenario: DelveScenario = DelveScenario.new(data, GreedyBot.new(), 3)
	var report: BotHarness.Report = BotHarness.run(scenario, 1, 40, 5)
	assert_eq(report.nondeterministic_seeds, [] as Array[int])
	var fights: int = 0
	for enemy: String in data.ids("enemies"):
		fights += report.counters.get("fights:" + enemy, 0)
	assert_between(fights, 40, 120)
	assert_eq(report.counters.get("stalemates", 0), 0)


func test_planner_is_at_least_as_good_as_greedy() -> void:
	var greedy: BotHarness.Report = BotHarness.run(DelveScenario.new(data, GreedyBot.new()), 1, 60, 0)
	var planner: BotHarness.Report = BotHarness.run(DelveScenario.new(data, PlannerBot.new()), 1, 60, 0)
	assert_gt(planner.wins, greedy.wins)
