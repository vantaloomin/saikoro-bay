class_name MapDelveScenario
extends BotScenario
## A whole delve on a generated map (specs/delve-map.md section 7): the
## DelveBot picks the path and the landings from a RunView, `fight_bot`
## plays the fights, RoomBot the treasure, rest and rescue rooms, and
## VaultBot Koban's vault.
##
## Outcome: won = cleared the vault, depth = rooms played, turns = fight
## turns. Counters: stalemates (a fight hit the turn cap), reached_vault, cleared, washed_up, surfaced_floor_<n>,
## rooms:<type>, hp_lost:<type>, rescued, and haul:<outcome>:<resource>
## (what the haul held when the delve ended).
##
## The villager and landmark pools are a fresh campaign's (everyone still
## to rescue, every landmark still to win).

var data: GameData
var fight_bot: FightBot
var perks: Array[Dictionary] = []
var delve_bot: DelveBot = DelveBot.new()
var room_bot: RoomBot = RoomBot.new()
var vault_bot: VaultBot = VaultBot.new()


func _init(game_data: GameData, bot: FightBot, with_perks: Array[Dictionary] = []) -> void:
	data = game_data
	fight_bot = bot
	perks = with_perks


func name() -> String:
	var perk_ids: PackedStringArray = []
	for entry: Dictionary in perks:
		perk_ids.append(str(entry.get("perk", "")))
	return "map:%s%s" % [fight_bot.name(), "" if perk_ids.is_empty() else ":" + "+".join(perk_ids)]


func play(rng: RngStreams) -> BotScenario.Outcome:
	var outcome: BotScenario.Outcome = BotScenario.Outcome.new()
	# The delve's own streams come from its seed; take it from `rng` so each
	# harness seed is a different delve.
	var seed_value: int = rng.range_int(RngStreams.Stream.MAP, 1, 2_000_000_000)
	var villagers: Array[String] = []
	villagers.assign(data.ids("villagers"))
	var landmarks: Array[String] = []
	landmarks.assign(data.ids("landmarks"))
	var run: DelveRun = DelveRun.create(data, seed_value, perks, villagers, landmarks)
	var view: RunView = RunView.new(run)
	for guard: int in 100:
		match run.step:
			DelveRun.Step.CHOOSE_ROOM:
				run.choose(delve_bot.choose_room(view))
			DelveRun.Step.IN_ROOM:
				var type: String = run.room_type
				var hp_in: int = run.hp
				if run.fight != null:
					if fight_bot.play_fight(run.fight) < 0:
						_count(outcome, "stalemates", 1)
						break
					outcome.turns += run.fight.turn
				if run.room != null:
					room_bot.play_room(run.room)
					if run.room.succeeded:
						_count(outcome, "rescued", 1)
				run.finish_room()
				outcome.depth += 1
				_count(outcome, "rooms:" + type, 1)
				_count(outcome, "hp_lost:" + type, maxi(0, hp_in - run.hp))
			DelveRun.Step.LANDING:
				if delve_bot.at_landing(view) == "surface":
					run.surface()
					_count(outcome, "surfaced_floor_%d" % (run.floor_index + 1), 1)
				else:
					run.go_deeper()
			DelveRun.Step.VAULT:
				_count(outcome, "reached_vault", 1)
				vault_bot.play_vault(run.vault)
				run.finish_vault()
			_:
				break
	if run.step == DelveRun.Step.CLEARED:
		outcome.won = true
		_count(outcome, "cleared", 1)
	elif run.step == DelveRun.Step.WASHED_UP:
		_count(outcome, "washed_up", 1)
	for id: String in run.haul.resources:
		_count(outcome, "haul:%s:%s" % [run.outcome(), id], run.haul.resources[id])
	return outcome


static func _count(outcome: BotScenario.Outcome, key: String, amount: int) -> void:
	outcome.counters[key] = outcome.counters.get(key, 0) + amount
