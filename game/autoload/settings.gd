extends Node
## Player settings that aren't part of a campaign save: content level, age
## confirmation and reduce motion. Stored in user://settings.cfg.
##
## Autoload "Settings". Adult content stays off until the player confirms
## their age (AC-1, in M5) and picks a level. A build exported with the
## "sfw" feature tag (the SFW export presets) caps the level at SFW no matter
## what the file says.

signal changed

const PATH: String = "user://settings.cfg"
const SFW_FEATURE: String = "sfw"

var age_confirmed: bool = false
var content_level: ContentLevel.Level = ContentLevel.Level.SFW
var reduce_motion: bool = false


func _ready() -> void:
	load_settings()


## The highest level this build may show.
func build_cap() -> ContentLevel.Level:
	if OS.has_feature(SFW_FEATURE):
		return ContentLevel.Level.SFW
	return ContentLevel.Level.FULL


## The level scenes should use right now.
func effective_content_level() -> ContentLevel.Level:
	if not age_confirmed:
		return ContentLevel.Level.SFW
	return ContentLevel.effective(content_level, build_cap())


func set_content_level(level: ContentLevel.Level) -> void:
	content_level = level
	save_settings()


func set_age_confirmed(confirmed: bool) -> void:
	age_confirmed = confirmed
	save_settings()


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	SceneFlow.reduce_motion = enabled
	save_settings()


func load_settings(path: String = PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) == OK:
		age_confirmed = config.get_value("content", "age_confirmed", false) == true
		content_level = ContentLevel.from_value(config.get_value("content", "level", 0))
		reduce_motion = config.get_value("accessibility", "reduce_motion", false) == true
	SceneFlow.reduce_motion = reduce_motion
	changed.emit()


func save_settings(path: String = PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "age_confirmed", age_confirmed)
	config.set_value("content", "level", int(content_level))
	config.set_value("accessibility", "reduce_motion", reduce_motion)
	var error: Error = config.save(path)
	changed.emit()
	return error
