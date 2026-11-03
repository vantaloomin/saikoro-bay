extends GutTest
## BotHarness: totals, determinism checks and the report.


class AlwaysWin:
	extends BotScenario

	func name() -> String:
		return "always_win"

	func play(rng: RngStreams) -> BotScenario.Outcome:
		var outcome: BotScenario.Outcome = BotScenario.Outcome.new()
		outcome.won = true
		outcome.turns = rng.range_int(RngStreams.Stream.ROLLS, 2, 4)
		outcome.depth = 3
		outcome.counters["coins"] = 2
		return outcome


## Breaks the rules on purpose: keeps state between plays.
class Leaky:
	extends BotScenario
	var calls: int = 0

	func play(_rng: RngStreams) -> BotScenario.Outcome:
		calls += 1
		var outcome: BotScenario.Outcome = BotScenario.Outcome.new()
		outcome.turns = calls
		return outcome


func test_totals() -> void:
	var report: BotHarness.Report = BotHarness.run(AlwaysWin.new(), 1, 50)
	assert_eq(report.runs, 50)
	assert_eq(report.wins, 50)
	assert_eq(report.win_rate_bp(), 10000)
	assert_between(report.min_turns, 2, 4)
	assert_between(report.max_turns, report.min_turns, 4)
	assert_eq(report.depth_counts, {3: 50} as Dictionary[int, int])
	assert_eq(report.counters["coins"], 100)
	assert_eq(report.nondeterministic_seeds, [] as Array[int])


func test_same_seeds_same_report() -> void:
	var a: Dictionary = BotHarness.run(CoinDelveScenario.new(), 1, 500).to_dict()
	var b: Dictionary = BotHarness.run(CoinDelveScenario.new(), 1, 500).to_dict()
	assert_eq(a, b)


func test_scenario_that_keeps_state_is_caught() -> void:
	var report: BotHarness.Report = BotHarness.run(Leaky.new(), 1, 10, 5)
	assert_eq(report.nondeterministic_seeds, [1, 6] as Array[int])


func test_report_formats_rates_without_floats() -> void:
	var report: BotHarness.Report = BotHarness.Report.new()
	report.runs = 3
	report.wins = 1
	report.total_turns = 10
	assert_eq(report.to_dict()["win_rate_percent"], "33.33")
	assert_eq(report.to_dict()["average_turns"], "3.33")
