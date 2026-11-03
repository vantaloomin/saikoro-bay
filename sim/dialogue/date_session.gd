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
##   content_level    0 SFW, 1 Suggestive, 2 Full (ContentLevel.Level)
## and changes only affection, upwards: "set affection += 1". Lowering it is
## ignored, and a date earns at most `max_gain` (the dates table).

## The title every date script starts at.
const TITLE: String = "date"
## The title played once, right after the date that reaches the scene's
## milestone: the villager's invitation into it. It reads no names.
const INVITE: String = "scene_invite"
## The names a date script may use, so a check can hold scripts to them.
const NAMES: Array[String] = ["spot", "villager_happy", "affection", "dates_done", "content_level"]

var villager: String = ""
var spot: String = ""
var villager_happy: bool = false
var dates_done: int = 0
var content_level: int = ContentLevel.Level.SFW
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

var _gained: int = 0

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


## Points this date has earned from its choices so far.
func gained() -> int:
	return _gained
