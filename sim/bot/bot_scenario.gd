class_name BotScenario
extends RefCounted
## One thing the bot can play many times: a fight, a delve, a whole loop.
##
## Subclasses override play(). It gets fresh seeded streams for each seed
## and returns an Outcome. It must use only `rng` for randomness, so the
## same seed always plays out the same way.


class Outcome:
	extends RefCounted
	var won: bool = false
	## Turns taken (a fight) or rooms cleared (a delve).
	var turns: int = 0
	## How far it got (depth reached, floor, room index).
	var depth: int = 0
	## Anything else worth counting, by name. Whole numbers only.
	var counters: Dictionary[String, int] = {}


## Short name used in reports.
func name() -> String:
	return "scenario"


func play(_rng: RngStreams) -> Outcome:
	push_error("BotScenario.play() must be overridden")
	return Outcome.new()
