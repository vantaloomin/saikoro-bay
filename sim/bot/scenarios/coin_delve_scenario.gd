class_name CoinDelveScenario
extends BotScenario
## Stand-in until M1 brings real fights: a delve of `rooms` rooms where each
## room is won on a roll of 3+ on a d6, with one reroll per delve. It only
## exists to prove the harness, the CLI and the report end to end.

var rooms: int = 10


func name() -> String:
	return "coin_delve"


func play(rng: RngStreams) -> BotScenario.Outcome:
	var outcome: BotScenario.Outcome = BotScenario.Outcome.new()
	var rerolls: int = 1
	for room: int in rooms:
		outcome.turns += 1
		var value: int = rng.roll(RngStreams.Stream.ROLLS, 6)
		if value < 3 and rerolls > 0:
			rerolls -= 1
			outcome.counters["rerolls_used"] = outcome.counters.get("rerolls_used", 0) + 1
			value = rng.roll(RngStreams.Stream.ROLLS, 6)
		if value < 3:
			outcome.depth = room
			return outcome
	outcome.depth = rooms
	outcome.won = true
	return outcome
