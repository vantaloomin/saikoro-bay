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

## The age gate's answer (AC-1), kept in Settings so the gate shows once
## per machine. Only ADULT may pick a level above SFW.
enum AgeAnswer { UNANSWERED, ADULT, UNDER_18 }

const NAMES: Dictionary[Level, String] = {
	Level.SFW: "Safe for work",
	Level.SUGGESTIVE: "Suggestive",
	Level.FULL: "Full",
}

## What each level shows, in one line, for the pickers and the scene notice.
const DESCRIPTIONS: Dictionary[Level, String] = {
	Level.SFW: "Swimsuits, towels and careful framing. No nudity.",
	Level.SUGGESTIVE: "Partial undress. No nudity.",
	Level.FULL: "Topless and bare-rear nudity. Never sex.",
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


## The level a scene actually plays at (AC-5): the highest of the scene's
## `available` levels that `effective` allows. Every scene has a SFW
## version (AC-3), so SFW is the floor even if `available` leaves it out.
static func shown_level(effective: Level, available: Array[Level]) -> Level:
	var shown: Level = Level.SFW
	for level: Level in available:
		if level <= effective and level > shown:
			shown = level
	return shown


## The scene notice's line (AC-5): "This scene plays at Suggestive." When
## the scene tops out below the player's level, it says so, so a lower
## level doesn't read as the setting not working.
static func notice_line(shown: Level, effective: Level) -> String:
	var line: String = "This scene plays at %s." % NAMES[shown]
	if shown < effective:
		line += " That's the most it shows."
	return line
