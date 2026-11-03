class_name DateSession
extends RefCounted
## One date in progress: what the date's script may read, and the affection
## it has earned so far. The script never touches the save. Its points are
## kept only when the date ends, through GameState.finish_date, which spends
## the action and adds them in one step.
##
## A date script (dialogue/villagers/<id>.dialogue, title "date") reads
## these names and nothing else (DialogueCheck holds it to that):
##   spot             "cafe" or "hot_spring": where the date is
##   villager_happy   true when they like their home
##   affection        their affection, counting what this date has earned
##   dates_done       dates with them before this one (0 the first time)
## and changes only affection, upwards: "set affection += 1". Lowering it is
## ignored, and a date earns at most `max_gain` (the dates table). Once
## sealed (begin_date seals it), writes to the other names are ignored too,
## so a script can't change what the rest of the date reads (Imogen's PR 1
## audit).
##
## content_level is kept for the game, not for scripts: scripts under
## res://dialogue/ ship in the SFW build, so they may not branch on it
## (Imogen's audit, finding 3). Text above SFW lives under content/adult/.

## The title every date script starts at.
const TITLE: String = "date"
## The title played once, right after the date that reaches the scene's
## milestone: the villager's invitation into it. It reads no names.
const INVITE: String = "scene_invite"
## The names a date script may use, so a check can hold scripts to them.
const NAMES: Array[String] = ["spot", "villager_happy", "affection", "dates_done"]

var villager: String = ""
## The dates row this session plays.
var date_id: String = ""
var script_path: String = ""
## Affection before the date, and the most this date may add.
var start_affection: int = 0
var max_gain: int = 0
## Set once GameState.finish_date has kept the date, so it can't be kept twice.
var finished: bool = false
## What finish_date added in all (the date's points, finishing, the spot).
var kept: int = 0

var spot: String = "":
	set(value):
		if not _sealed:
			spot = value
var villager_happy: bool = false:
	set(value):
		if not _sealed:
			villager_happy = value
var dates_done: int = 0:
	set(value):
		if not _sealed:
			dates_done = value
## The level the game plays the date at. Not a script name; the game moves
## it through follow_content_level when the player changes the setting.
var content_level: int = ContentLevel.Level.SFW:
	set(value):
		if not _sealed:
			content_level = value

var _gained: int = 0
var _sealed: bool = false

## Read by the script as a number; "set affection += n" lands here. It only
## ever rises, and never past start + max_gain (affection never drops, PRD
## RD-6; Imogen's rule that affection only goes up).
var affection: int:
	get:
		return start_affection + _gained
	set(value):
		if finished:
			return
		_gained = clampi(value - start_affection, _gained, max_gain)


## Fixes what the script reads. After this only affection moves (upwards).
func seal() -> void:
	_sealed = true


## The player changed the content level mid-date (the pause menu): the
## game, not a script, moves it.
func follow_content_level(level: ContentLevel.Level) -> void:
	_sealed = false
	content_level = level
	_sealed = true


## Points this date has earned from its choices so far.
func gained() -> int:
	return _gained
