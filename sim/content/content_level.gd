class_name ContentLevel
extends RefCounted
## How much a scene may show (AC-2). Player-chosen, capped by the build.
##
## Every scene has a version for every level, so turning content down never
## breaks the story (AC-3). A SFW build caps everything at SFW and ships none
## of content/adult/ (AC-6).
##
## Placeholder names until the scene rules are written (the Steam tier
## decision before M6 sets where FULL stops).

enum Level {
	SFW,         ## Swimsuit, towel and framing variants. The default and the demo.
	SUGGESTIVE,  ## Partial undress, nothing explicit.
	FULL,        ## The game's maximum: topless and bare-rear nudity, no sex (PRD).
}

const NAMES: Dictionary[Level, String] = {
	Level.SFW: "Safe for work",
	Level.SUGGESTIVE: "Suggestive",
	Level.FULL: "Full",
}


## The level that actually plays: the player's choice, never above the
## build's cap.
static func effective(chosen: Level, build_cap: Level) -> Level:
	return mini(chosen, build_cap) as Level


## Whether something tagged `required` may show at `level`.
static func allows(level: Level, required: Level) -> bool:
	return level >= required


## Parses a saved or data value; anything unknown falls back to SFW.
static func from_value(value: Variant) -> Level:
	var number: int = SaveCodec.to_int_or(value, Level.SFW)
	if number < Level.SFW or number > Level.FULL:
		return Level.SFW
	return number as Level
