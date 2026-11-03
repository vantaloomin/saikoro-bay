class_name FightBot
extends RefCounted
## Plays one turn of a Fight through the same moves the board uses.
##
## Bots never draw randomness themselves. They plan on Fight.planning_copy(),
## which has no dice streams, so they can't peek at a roll or move the real
## streams. Ties always break the same way (lowest die id, then card order),
## so a seed plays out identically every time.

## Scores a resolved turn: winning beats everything, losing is worst, and
## otherwise HP lost weighs a little more than damage dealt, because HP
## carries across the delve.
const WIN_SCORE: int = 1_000_000
const DEALT_WEIGHT: int = 100
const HP_WEIGHT: int = 130


## Short name for reports ("greedy", "planner").
func name() -> String:
	return "bot"


## Makes this turn's moves (not end_turn).
func play_turn(_fight: Fight) -> void:
	push_error("FightBot.play_turn() must be overridden")


## Plays the fight to the end. Returns the number of turns, or -1 if it hit
## `max_turns` (a stalemate the data should never allow).
func play_fight(fight: Fight, max_turns: int = 60) -> int:
	while fight.state == Fight.State.PLAYER_TURN:
		if fight.turn > max_turns:
			return -1
		play_turn(fight)
		fight.end_turn()
	return fight.turn


## How good `after` (a planning copy after end_turn) is compared to `before`.
static func score(before: Fight, after: Fight) -> int:
	if after.state == Fight.State.WON:
		return WIN_SCORE + after.player_hp * HP_WEIGHT
	if after.state == Fight.State.LOST:
		return -WIN_SCORE + (before.enemy_hp - after.enemy_hp)
	return (before.enemy_hp - after.enemy_hp) * DEALT_WEIGHT - (before.player_hp - after.player_hp) * HP_WEIGHT


static func make(bot_name: String) -> FightBot:
	match bot_name:
		"greedy":
			return GreedyBot.new()
		"planner":
			return PlannerBot.new()
	return null
