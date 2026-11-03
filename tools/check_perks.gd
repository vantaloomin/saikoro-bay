extends SceneTree
## KP-4, the plan's rule that every perk is a trade-off, never a flat
## increase (specs/bridge.md section 3; Imogen's bridge review). Plays whole
## delves on paired seeds with the plain kit and with each shop perk, alone
## and in pairs, and prints a JSON report.
##
##   godot --headless --path . -s res://tools/check_perks.gd -- [options]
##
## Options:
##   --bot=NAME      greedy (default) or planner
##   --seeds=N       delves per kit (default 500)
##   --first-seed=S  first seed (default 1)
##   --perks=a,b     perks to check (default: every shop's perk)
##   --out=PATH      also write the report to PATH
##
## Seeds are paired: seed S is the same map and the same rolls for every kit
## (per-die streams), so "lost" counts delves the plain kit cleared and this
## kit didn't, and "gained" the reverse. Paired delves drift apart once any
## choice changes, so even a pure gain loses some seeds; a kit is flagged
## "flat" by McNemar's test instead (Imogen's #50 audit): gained > lost,
## (|gained - lost| - 1)^2 / (gained + lost) over FLAT_CHI2 (p < 0.01), and
## clears up by more than FLAT_POINTS. The statistic is printed too.
## Every kit also reports the haul it banked, since Chum trades fights for
## treasure. Exits 1 if a delve got stuck or a fight stalemated, 2 on bad
## options.


## McNemar's chi-squared (1 degree of freedom) at p < 0.01.
const FLAT_CHI2: float = 6.63
## And the clear rate up by more than this many points.
const FLAT_POINTS: float = 3.0


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
	var perk_ids: Array[String] = []
	if args.has("perks"):
		for perk_id: String in str(args["perks"]).split(",", false):
			perk_ids.append(perk_id)
	else:
		for building: String in data.ids("buildings"):
			if not str(data.row("buildings", building)["perk"]).is_empty():
				perk_ids.append(str(data.row("buildings", building)["perk"]))
	for perk_id: String in perk_ids:
		if _source(data, perk_id).is_empty():
			printerr("No villager or shop gives \"%s\"" % perk_id)
			quit(2)
			return

	var kits: Array[Array] = [[]]
	for i: int in perk_ids.size():
		kits.append([perk_ids[i]])
	for i: int in perk_ids.size():
		for j: int in range(i + 1, perk_ids.size()):
			kits.append([perk_ids[i], perk_ids[j]])

	var seeds: int = str(args.get("seeds", "500")).to_int()
	var first_seed: int = str(args.get("first-seed", "1")).to_int()
	var started: int = Time.get_ticks_msec()
	var base: Array[BotScenario.Outcome] = []
	var rows: Array[Dictionary] = []
	var failed: bool = false
	for kit_perks: Array in kits:
		var perks: Array[Dictionary] = []
		for perk_id: Variant in kit_perks:
			perks.append({"perk": str(perk_id), "source": _source(data, str(perk_id))})
		var scenario: MapDelveScenario = MapDelveScenario.new(data, bot, perks)
		var outcomes: Array[BotScenario.Outcome] = []
		for i: int in seeds:
			outcomes.append(scenario.play(RngStreams.new(first_seed + i)))
		if kit_perks.is_empty():
			base = outcomes
		var row: Dictionary = _row(kit_perks, outcomes, base)
		failed = failed or int(row["stuck"]) > 0 or int(row["stalemates"]) > 0
		rows.append(row)
		print("%-26s cleared %5s%%  lost %4d  gained %4d  chi2 %6s  haul %s%s" % [
			"+".join(kit_perks) if not kit_perks.is_empty() else "(plain kit)", row["cleared_percent"], row["lost"],
			row["gained"], row["mcnemar_chi2"], row["kept_per_delve"], "  FLAT" if row["flat"] else ""])
	var report: Dictionary = {"bot": bot.name(), "seeds": seeds, "first_seed": first_seed, "kits": rows,
		"seconds": "%.1f" % ((Time.get_ticks_msec() - started) / 1000.0)}
	var text: String = JSON.stringify(report, "  ")
	if args.has("out"):
		var file: FileAccess = FileAccess.open(str(args["out"]), FileAccess.WRITE)
		if file != null:
			file.store_string(text + "\n")
			file.close()
	else:
		print(text)
	quit(1 if failed else 0)


static func _row(kit_perks: Array, outcomes: Array[BotScenario.Outcome], base: Array[BotScenario.Outcome]) -> Dictionary:
	var cleared: int = 0
	var lost: int = 0
	var gained: int = 0
	var stuck: int = 0
	var stalemates: int = 0
	var kept: Dictionary = {}
	for i: int in outcomes.size():
		var outcome: BotScenario.Outcome = outcomes[i]
		cleared += 1 if outcome.won else 0
		if base[i].won and not outcome.won:
			lost += 1
		elif outcome.won and not base[i].won:
			gained += 1
		stuck += outcome.counters.get("stuck", 0)
		stalemates += outcome.counters.get("stalemates", 0)
		for key: String in outcome.counters:
			if key.begins_with("kept:"):
				kept[key.substr(5)] = int(kept.get(key.substr(5), 0)) + outcome.counters[key]
	var per_delve: Dictionary = {}
	for id: String in kept:
		per_delve[id] = "%.2f" % (float(kept[id]) / maxi(1, outcomes.size()))
	var bp: int = cleared * 10000 / maxi(1, outcomes.size())
	var chi2: float = 0.0 if lost + gained == 0 else pow(absf(gained - lost) - 1.0, 2.0) / (gained + lost)
	var points: float = (gained - lost) * 100.0 / maxi(1, outcomes.size())
	return {
		"perks": kit_perks,
		"cleared_percent": "%d.%02d" % [bp / 100, bp % 100],
		"lost": lost,
		"gained": gained,
		"mcnemar_chi2": "%.2f" % chi2,
		"flat": not kit_perks.is_empty() and gained > lost and chi2 > FLAT_CHI2 and points > FLAT_POINTS,
		"kept_per_delve": per_delve,
		"stuck": stuck,
		"stalemates": stalemates,
	}


## Who gives `perk_id`: a villager or a shop.
static func _source(data: GameData, perk_id: String) -> String:
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
