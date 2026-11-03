extends SceneTree
## Runs a bot scenario headless and prints a JSON report.
##
##   godot --headless --path . -s res://tools/run_bot.gd -- [options]
##
## Options:
##   --scenario=NAME   map (default: a whole delve on a generated map),
##                     delve (the M1 stand-in: fights in a row) or fight
##   --bot=NAME        greedy (default, the floor) or planner (a strong player)
##   --enemy=ID        the enemy for --scenario=fight
##   --fights=N        fights in a delve (default 6)
##   --perks=a,b       perks the kit carries, e.g. nudge,brace
##   --rest-every=N --rest-heal=H   a rest healing H after every N fights won
##   --seeds=N         how many seeds to play (default 10000)
##   --first-seed=S    first seed (default 1)
##   --out=PATH        also write the JSON report to PATH
##   --min-win=P --max-win=P   fail (exit 1) if the win rate in percent is outside
##   --min-vault=P --max-vault=P   map only: fail if the share of delves that
##                     reach Koban's vault and then clear it is outside
##
## Exits 1 if any seed played differently on replay, a fight stalemated or a
## delve got stuck, 2 on bad options.


func _initialize() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var data: GameData = GameData.load_dir()
	if not data.is_valid():
		printerr("\n".join(data.errors))
		quit(2)
		return
	var bot: FightBot = FightBot.make(str(args.get("bot", "greedy")))
	if bot == null:
		printerr("Unknown bot \"%s\". Known: greedy, planner" % args.get("bot"))
		quit(2)
		return
	var perks: Array[Dictionary] = []
	for perk_id: String in str(args.get("perks", "")).split(",", false):
		if not data.has_row("perks", perk_id):
			printerr("Unknown perk \"%s\"" % perk_id)
			quit(2)
			return
		perks.append({"perk": perk_id, "source": _villager_for(data, perk_id)})

	var scenario: BotScenario = null
	match str(args.get("scenario", "map")):
		"map":
			scenario = MapDelveScenario.new(data, bot, perks)
		"delve":
			scenario = DelveScenario.new(data, bot, str(args.get("fights", "6")).to_int(), perks,
				str(args.get("rest-every", "0")).to_int(), str(args.get("rest-heal", "0")).to_int())
		"fight":
			var enemy: String = str(args.get("enemy", ""))
			if not data.has_row("enemies", enemy):
				printerr("--scenario=fight needs --enemy=ID. Known: %s" % ", ".join(data.ids("enemies")))
				quit(2)
				return
			scenario = FightScenario.new(data, bot, enemy, perks)
		_:
			printerr("Unknown scenario \"%s\". Known: map, delve, fight" % args.get("scenario"))
			quit(2)
			return
	var seeds: int = str(args.get("seeds", "10000")).to_int()
	var first_seed: int = str(args.get("first-seed", "1")).to_int()

	var started: int = Time.get_ticks_msec()
	var report: BotHarness.Report = BotHarness.run(scenario, first_seed, seeds)
	var summary: Dictionary = report.to_dict()
	summary["seconds"] = "%.2f" % ((Time.get_ticks_msec() - started) / 1000.0)
	var text: String = JSON.stringify(summary, "  ")
	print(text)
	if args.has("out"):
		var file: FileAccess = FileAccess.open(str(args["out"]), FileAccess.WRITE)
		if file != null:
			file.store_string(text + "\n")
			file.close()

	var failed: bool = not report.nondeterministic_seeds.is_empty()
	if report.counters.get("stalemates", 0) > 0:
		printerr("%d fights hit the turn cap" % report.counters["stalemates"])
		failed = true
	var rate_percent: int = report.win_rate_bp() / 100
	if args.has("min-win") and rate_percent < str(args["min-win"]).to_int():
		printerr("Win rate %d%% is below the minimum %s%%" % [rate_percent, args["min-win"]])
		failed = true
	if args.has("max-win") and rate_percent > str(args["max-win"]).to_int():
		printerr("Win rate %d%% is above the maximum %s%%" % [rate_percent, args["max-win"]])
		failed = true
	if report.counters.get("stuck", 0) > 0:
		printerr("%d delves got stuck" % report.counters["stuck"])
		failed = true
	if args.has("min-vault") or args.has("max-vault"):
		var reached: int = report.counters.get("reached_vault", 0)
		var vault_percent: int = 0 if reached == 0 else report.counters.get("cleared", 0) * 100 / reached
		print("Vault conversion: %d%% of %d delves that reached it" % [vault_percent, reached])
		if args.has("min-vault") and vault_percent < str(args["min-vault"]).to_int():
			printerr("Vault conversion %d%% is below the minimum %s%%" % [vault_percent, args["min-vault"]])
			failed = true
		if args.has("max-vault") and vault_percent > str(args["max-vault"]).to_int():
			printerr("Vault conversion %d%% is above the maximum %s%%" % [vault_percent, args["max-vault"]])
			failed = true
	quit(1 if failed else 0)


## Who gives `perk_id`: a villager or a shop.
static func _villager_for(data: GameData, perk_id: String) -> String:
	for table: String in ["villagers", "buildings"]:
		for id: String in data.ids(table):
			if data.row(table, id)["perk"] == perk_id:
				return id
	return ""


static func _parse(raw: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in raw:
		if arg.begins_with("--") and "=" in arg:
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1]
	return parsed
