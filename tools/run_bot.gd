extends SceneTree
## Runs a bot scenario headless and prints a JSON report.
##
##   godot --headless --path . -s res://tools/run_bot.gd -- [options]
##
## Options:
##   --scenario=NAME   coin_delve (more arrive with M1)
##   --seeds=N         how many seeds to play (default 10000)
##   --first-seed=S    first seed (default 1)
##   --out=PATH        also write the JSON report to PATH
##   --min-win=P --max-win=P   fail (exit 1) if the win rate in percent is outside
##
## Exits 1 if any seed played differently on replay.

const SCENARIOS: Dictionary[String, GDScript] = {
	"coin_delve": preload("res://sim/bot/scenarios/coin_delve_scenario.gd"),
}


func _initialize() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var scenario_name: String = str(args.get("scenario", "coin_delve"))
	if not SCENARIOS.has(scenario_name):
		printerr("Unknown scenario \"%s\". Known: %s" % [scenario_name, ", ".join(SCENARIOS.keys())])
		quit(2)
		return
	var scenario: BotScenario = SCENARIOS[scenario_name].new() as BotScenario
	var seeds: int = str(args.get("seeds", "10000")).to_int()
	var first_seed: int = str(args.get("first-seed", "1")).to_int()

	var started: int = Time.get_ticks_msec()
	var report: BotHarness.Report = BotHarness.run(scenario, first_seed, seeds)
	var data: Dictionary = report.to_dict()
	data["seconds"] = "%.2f" % ((Time.get_ticks_msec() - started) / 1000.0)
	var text: String = JSON.stringify(data, "  ")
	print(text)
	if args.has("out"):
		var file: FileAccess = FileAccess.open(str(args["out"]), FileAccess.WRITE)
		if file != null:
			file.store_string(text + "\n")
			file.close()

	var failed: bool = not report.nondeterministic_seeds.is_empty()
	var rate_percent: int = report.win_rate_bp() / 100
	if args.has("min-win") and rate_percent < str(args["min-win"]).to_int():
		printerr("Win rate %d%% is below the minimum %s%%" % [rate_percent, args["min-win"]])
		failed = true
	if args.has("max-win") and rate_percent > str(args["max-win"]).to_int():
		printerr("Win rate %d%% is above the maximum %s%%" % [rate_percent, args["max-win"]])
		failed = true
	quit(1 if failed else 0)


static func _parse(raw: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in raw:
		if arg.begins_with("--") and "=" in arg:
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1]
	return parsed
