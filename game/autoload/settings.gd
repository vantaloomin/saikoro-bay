extends Node
## Player settings that aren't part of a campaign save: content level, the
## age gate's answer, reduce motion and the three volumes. Stored in
## user://settings.cfg.
##
## Autoload "Settings". Adult content stays off until the player says
## they're 18 or older at the age gate (AC-1) and picks a level (AC-2). A
## player who says they're under 18 stays at SFW and can't pick a level. A
## build exported with the "sfw" feature tag (the SFW export presets) caps
## the level at SFW no matter what the file says, and has no age gate.

signal changed


const PATH: String = "user://settings.cfg"
const SFW_FEATURE: String = "sfw"
## The audio buses (default_bus_layout.tres) the player can turn down,
## each from 0 (silent) to 1 (full).
const BUSES: Array[String] = ["Music", "SFX", "UI"]
const DEFAULT_VOLUMES: Dictionary[String, float] = {"Music": 0.8, "SFX": 1.0, "UI": 1.0}

## True in a build exported with the "sfw" feature tag. A var so tests can
## play a SFW build; turning it off can't add assets the build doesn't have.
## Where settings are kept; tests point it at a scratch file.
var file_path: String = PATH
var sfw_build: bool = OS.has_feature(SFW_FEATURE)
var age_answer: ContentLevel.AgeAnswer = ContentLevel.AgeAnswer.UNANSWERED
var content_level: ContentLevel.Level = ContentLevel.Level.SFW
var reduce_motion: bool = false
## The town's "Go down" hint fades for good after the first real hold.
var go_down_learned: bool = false
var volumes: Dictionary[String, float] = DEFAULT_VOLUMES.duplicate()


func _ready() -> void:
	load_settings()


## The highest level this build may show.
func build_cap() -> ContentLevel.Level:
	if sfw_build:
		return ContentLevel.Level.SFW
	return ContentLevel.Level.FULL


## The level scenes should use right now.
func effective_content_level() -> ContentLevel.Level:
	if age_answer != ContentLevel.AgeAnswer.ADULT:
		return ContentLevel.Level.SFW
	return ContentLevel.effective(content_level, build_cap())


## True until the player answers the age gate, in a build that has adult
## content. Boot shows the gate before anything else while it's true.
func needs_age_gate() -> bool:
	return build_cap() > ContentLevel.Level.SFW and age_answer == ContentLevel.AgeAnswer.UNANSWERED


## Whether the player may pick a level above SFW.
func can_choose_level() -> bool:
	return build_cap() > ContentLevel.Level.SFW and age_answer == ContentLevel.AgeAnswer.ADULT


## Why the level is fixed at SFW, for the pickers to say, or "" if it isn't.
func level_locked_reason() -> String:
	if build_cap() == ContentLevel.Level.SFW:
		return "This edition has no adult content."
	if age_answer == ContentLevel.AgeAnswer.UNDER_18:
		return "Adult content is off because you said you're under 18."
	if age_answer == ContentLevel.AgeAnswer.UNANSWERED:
		return "Adult content is off. The age question comes back next time you start the game."
	return ""


## Saves the age gate's answer and, for an adult, the level they picked.
## Under 18 always means SFW.
func answer_age_gate(answer: ContentLevel.AgeAnswer, level: ContentLevel.Level = ContentLevel.Level.SFW) -> void:
	age_answer = answer
	content_level = level if answer == ContentLevel.AgeAnswer.ADULT else ContentLevel.Level.SFW
	save_settings()


## Whether the pause menu offers to ask the age question again: only for
## a player locked out by an "under 18" answer (Mara's #56 review).
func can_ask_age_again() -> bool:
	return build_cap() > ContentLevel.Level.SFW and age_answer == ContentLevel.AgeAnswer.UNDER_18


## Clears the age answer so the gate shows at the next launch: the way
## back for an adult who misclicked "under 18". The level stays SFW until
## the gate is answered again; nothing changes in this session.
func ask_age_again() -> void:
	if not can_ask_age_again():
		return
	age_answer = ContentLevel.AgeAnswer.UNANSWERED
	content_level = ContentLevel.Level.SFW
	save_settings()


## Picks the content level (AC-2). Returns false, changing nothing, if the
## player can't pick levels above SFW and asked for one.
func set_content_level(level: ContentLevel.Level) -> bool:
	if level > ContentLevel.Level.SFW and not can_choose_level():
		return false
	content_level = level
	save_settings()
	return true


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	SceneFlow.reduce_motion = enabled
	save_settings()


func set_volume(bus: String, volume: float) -> void:
	if not BUSES.has(bus):
		push_error("Settings: unknown bus \"%s\"" % bus)
		return
	volumes[bus] = clampf(volume, 0.0, 1.0)
	apply_volumes()
	save_settings()


## Sets each bus's level from `volumes`; 0 mutes it.
func apply_volumes() -> void:
	for bus: String in BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var volume: float = volumes.get(bus, 1.0)
		AudioServer.set_bus_mute(index, volume <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))


func set_go_down_learned() -> void:
	if go_down_learned:
		return
	go_down_learned = true
	save_settings()


func load_settings(path: String = "") -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path if not path.is_empty() else file_path) == OK:
		age_answer = _age_answer_from(config)
		content_level = ContentLevel.from_value(config.get_value("content", "level", 0))
		reduce_motion = config.get_value("accessibility", "reduce_motion", false) == true
		go_down_learned = config.get_value("tutorial", "go_down_learned", false) == true
		for bus: String in BUSES:
			var value: Variant = config.get_value("audio", bus.to_lower(), DEFAULT_VOLUMES[bus])
			volumes[bus] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) else DEFAULT_VOLUMES[bus]
	SceneFlow.reduce_motion = reduce_motion
	apply_volumes()
	changed.emit()


func save_settings(path: String = "") -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "age", int(age_answer))
	config.set_value("content", "level", int(content_level))
	config.set_value("accessibility", "reduce_motion", reduce_motion)
	config.set_value("tutorial", "go_down_learned", go_down_learned)
	for bus: String in BUSES:
		config.set_value("audio", bus.to_lower(), volumes[bus])
	var error: Error = config.save(path if not path.is_empty() else file_path)
	changed.emit()
	return error


## The saved answer; an unknown value asks again. Files from before the
## gate only had "age_confirmed", which nothing could set to true.
static func _age_answer_from(config: ConfigFile) -> ContentLevel.AgeAnswer:
	if not config.has_section_key("content", "age"):
		return ContentLevel.AgeAnswer.ADULT if config.get_value("content", "age_confirmed", false) == true else ContentLevel.AgeAnswer.UNANSWERED
	var number: int = SaveCodec.to_int_or(config.get_value("content", "age"), ContentLevel.AgeAnswer.UNANSWERED)
	if number < ContentLevel.AgeAnswer.UNANSWERED or number > ContentLevel.AgeAnswer.UNDER_18:
		return ContentLevel.AgeAnswer.UNANSWERED
	return number as ContentLevel.AgeAnswer
