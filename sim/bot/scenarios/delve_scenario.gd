class_name DelveScenario
extends BotScenario
## A stand-in delve until M2 brings the map: `fights` fights in a row,
## each enemy drawn from the ENEMIES stream, HP carried from fight to
## fight, no rests or treasure. Fights aren't independent, because HP
## carries, so this is the number the balance band watches.
##
## Outcome: won = cleared every fight, depth = fights won, turns = total
## turns. Counters per enemy: fights:<id>, wins:<id>, hp_lost:<id>.

var data: GameData
var bot: FightBot
var fights: int = 6
var loadout_id: String = "fresh"
var perks: Array[Dictionary] = []


func _init(game_data: GameData, fight_bot: FightBot, fight_count: int = 6, with_perks: Array[Dictionary] = []) -> void:
	data = game_data
	bot = fight_bot
	fights = fight_count
	perks = with_perks


func name() -> String:
	var perk_ids: PackedStringArray = []
	for entry: Dictionary in perks:
		perk_ids.append(str(entry.get("perk", "")))
	return "delve:%d:%s%s" % [fights, bot.name(), "" if perk_ids.is_empty() else ":" + "+".join(perk_ids)]


func play(rng: RngStreams) -> BotScenario.Outcome:
	var outcome: BotScenario.Outcome = BotScenario.Outcome.new()
	var enemies: Array = Array(data.ids("enemies"))
	var hp: int = -1
	for i: int in fights:
		var enemy_id: String = rng.pick(RngStreams.Stream.ENEMIES, enemies) as String
		var fight: Fight = Fight.create(data, loadout_id, enemy_id, rng, perks, hp)
		var turns: int = bot.play_fight(fight)
		outcome.turns += fight.turn
		_count(outcome, "fights:" + enemy_id, 1)
		_count(outcome, "hp_lost:" + enemy_id, maxi(0, fight.start_hp - fight.player_hp))
		if turns < 0:
			_count(outcome, "stalemates", 1)
		if fight.state != Fight.State.WON:
			return outcome
		_count(outcome, "wins:" + enemy_id, 1)
		outcome.depth += 1
		hp = fight.player_hp
	outcome.won = true
	return outcome


static func _count(outcome: BotScenario.Outcome, key: String, amount: int) -> void:
	outcome.counters[key] = outcome.counters.get(key, 0) + amount
