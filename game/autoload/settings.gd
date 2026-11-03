extends Node
## Player settings that aren't part of a campaign save: content level, age
## confirmation, reduce motion and the three volumes. Stored in
## user://settings.cfg.
##
## Autoload "Settings". Adult content stays off until the player confirms
## their age (AC-1, in M5) and picks a level. A build exported with the
## "sfw" feature tag (the SFW export presets) caps the level at SFW no matter
## what the file says.

signal changed

const PATH: String = "user://settings.cfg"
const SFW_FEATURE: String = "sfw"
## The audio buses (default_bus_layout.tres) the player can turn down,
## each from 0 (silent) to 1 (full).
const BUSES: Array[String] = ["Music", "SFX", "UI"]
const DEFAULT_VOLUMES: Dictionary[String, float] = {"Music": 0.8, "SFX": 1.0, "UI": 1.0}

var age_confirmed: bool = false
var content_level: ContentLevel.Level = ContentLevel.Level.SFW
var reduce_motion: bool = false
## The town's "Go down" hint fades for good after the first real hold.
var go_down_learned: bool = false
var volumes: Dictionary[String, float] = DEFAULT_VOLUMES.duplicate()


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


func load_settings(path: String = PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) == OK:
		age_confirmed = config.get_value("content", "age_confirmed", false) == true
		content_level = ContentLevel.from_value(config.get_value("content", "level", 0))
		reduce_motion = config.get_value("accessibility", "reduce_motion", false) == true
		go_down_learned = config.get_value("tutorial", "go_down_learned", false) == true
		for bus: String in BUSES:
			var value: Variant = config.get_value("audio", bus.to_lower(), DEFAULT_VOLUMES[bus])
			volumes[bus] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) else DEFAULT_VOLUMES[bus]
	SceneFlow.reduce_motion = reduce_motion
	apply_volumes()
	changed.emit()


func save_settings(path: String = PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "age_confirmed", age_confirmed)
	config.set_value("content", "level", int(content_level))
	config.set_value("accessibility", "reduce_motion", reduce_motion)
	config.set_value("tutorial", "go_down_learned", go_down_learned)
	for bus: String in BUSES:
		config.set_value("audio", bus.to_lower(), volumes[bus])
	var error: Error = config.save(path)
	changed.emit()
	return error
