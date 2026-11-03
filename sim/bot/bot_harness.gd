class_name BotHarness
extends RefCounted
## Plays a BotScenario across many seeds and sums up the results.
##
## This is how balance gets numbers before there's any art: the plan's target
## is a 40-60% clear rate to the vault on a fresh kit, and a bot that wins
## everything means delves are too easy. tools/run_bot.gd runs it headless
## from the command line and CI.


class Report:
	extends RefCounted
	var scenario: String = ""
	var runs: int = 0
	var wins: int = 0
	var total_turns: int = 0
	var min_turns: int = 0
	var max_turns: int = 0
	var depth_counts: Dictionary[int, int] = {}
	var counters: Dictionary[String, int] = {}
	## Seeds whose outcome differed when replayed. Must stay empty.
	var nondeterministic_seeds: Array[int] = []

	## Win rate in basis points (0-10000), to stay in integers.
	func win_rate_bp() -> int:
		return 0 if runs == 0 else wins * 10000 / runs

	func average_turns_x100() -> int:
		return 0 if runs == 0 else total_turns * 100 / runs

	func to_dict() -> Dictionary:
		var depths: Dictionary = {}
		for depth: int in depth_counts:
			depths[str(depth)] = depth_counts[depth]
		return {
			"scenario": scenario,
			"runs": runs,
			"wins": wins,
			"win_rate_percent": "%d.%02d" % [win_rate_bp() / 100, win_rate_bp() % 100],
			"average_turns": "%d.%02d" % [average_turns_x100() / 100, average_turns_x100() % 100],
			"min_turns": min_turns,
			"max_turns": max_turns,
			"depths": depths,
			"counters": counters,
			"nondeterministic_seeds": nondeterministic_seeds,
		}


## Plays `scenario` once per seed in [first_seed, first_seed + count).
## Every `replay_every`th seed is played twice to prove determinism (0 = never).
static func run(scenario: BotScenario, first_seed: int, count: int, replay_every: int = 100) -> Report:
	var report: Report = Report.new()
	report.scenario = scenario.name()
	for i: int in count:
		var seed_value: int = first_seed + i
		var outcome: BotScenario.Outcome = scenario.play(RngStreams.new(seed_value))
		if replay_every > 0 and i % replay_every == 0:
			var again: BotScenario.Outcome = scenario.play(RngStreams.new(seed_value))
			if not _same(outcome, again):
				report.nondeterministic_seeds.append(seed_value)
		_add(report, outcome)
	return report


static func _add(report: Report, outcome: BotScenario.Outcome) -> void:
	if report.runs == 0:
		report.min_turns = outcome.turns
		report.max_turns = outcome.turns
	report.runs += 1
	if outcome.won:
		report.wins += 1
	report.total_turns += outcome.turns
	report.min_turns = mini(report.min_turns, outcome.turns)
	report.max_turns = maxi(report.max_turns, outcome.turns)
	report.depth_counts[outcome.depth] = report.depth_counts.get(outcome.depth, 0) + 1
	for key: String in outcome.counters:
		report.counters[key] = report.counters.get(key, 0) + outcome.counters[key]


static func _same(a: BotScenario.Outcome, b: BotScenario.Outcome) -> bool:
	return a.won == b.won and a.turns == b.turns and a.depth == b.depth and a.counters == b.counters
