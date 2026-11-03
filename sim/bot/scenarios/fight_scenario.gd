class_name FightScenario
extends BotScenario
## One fight against one enemy on a fresh kit, played by a FightBot.
## Counters: hp_lost (summed over runs), stalemates (fights that hit the
## turn cap, which the data should never allow).

var data: GameData
var bot: FightBot
var enemy_id: String = ""
var loadout_id: String = "fresh"
var perks: Array[Dictionary] = []


func _init(game_data: GameData, fight_bot: FightBot, enemy: String, with_perks: Array[Dictionary] = []) -> void:
	data = game_data
	bot = fight_bot
	enemy_id = enemy
	perks = with_perks


func name() -> String:
	return "fight:%s:%s" % [enemy_id, bot.name()]


func play(rng: RngStreams) -> BotScenario.Outcome:
	var outcome: BotScenario.Outcome = BotScenario.Outcome.new()
	var fight: Fight = Fight.create(data, loadout_id, enemy_id, rng, perks)
	var turns: int = bot.play_fight(fight)
	outcome.won = fight.state == Fight.State.WON
	outcome.turns = turns if turns > 0 else fight.turn
	outcome.depth = 1 if outcome.won else 0
	outcome.counters["hp_lost"] = fight.start_hp - fight.player_hp
	if turns < 0:
		outcome.counters["stalemates"] = 1
	return outcome
