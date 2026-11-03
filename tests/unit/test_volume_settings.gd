extends GutTest
## The three volumes (Mara's #45 review): each bus can be turned down or
## muted from the pause menu, and the levels survive a restart.

const PATH: String = "user://test_volume_settings.cfg"

var _saved: Dictionary[String, float]


func before_each() -> void:
	_saved = Settings.volumes.duplicate()


func after_each() -> void:
	Settings.volumes = _saved
	Settings.apply_volumes()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_a_volume_sets_its_bus() -> void:
	Settings.volumes["Music"] = 0.5
	Settings.apply_volumes()
	var music: int = AudioServer.get_bus_index("Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(music), linear_to_db(0.5), 0.01)
	assert_false(AudioServer.is_bus_mute(music))
	Settings.volumes["Music"] = 0.0
	Settings.apply_volumes()
	assert_true(AudioServer.is_bus_mute(music), "all the way down is silent")


func test_volumes_survive_a_restart() -> void:
	Settings.volumes = {"Music": 0.25, "SFX": 0.6, "UI": 1.0}
	Settings.save_settings(PATH)
	Settings.volumes = Settings.DEFAULT_VOLUMES.duplicate()
	Settings.load_settings(PATH)
	assert_eq(Settings.volumes["Music"], 0.25)
	assert_eq(Settings.volumes["SFX"], 0.6)


func test_a_bad_volume_in_the_file_falls_back() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music", "loud")
	config.set_value("audio", "sfx", 7.0)
	config.save(PATH)
	Settings.load_settings(PATH)
	assert_eq(Settings.volumes["Music"], Settings.DEFAULT_VOLUMES["Music"])
	assert_eq(Settings.volumes["SFX"], 1.0, "clamped to full")
