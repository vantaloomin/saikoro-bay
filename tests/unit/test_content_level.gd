extends GutTest
## ContentLevel and the Settings rules around it.


func test_build_cap_wins_over_the_player() -> void:
	assert_eq(ContentLevel.effective(ContentLevel.Level.FULL, ContentLevel.Level.SFW), ContentLevel.Level.SFW)
	assert_eq(ContentLevel.effective(ContentLevel.Level.SUGGESTIVE, ContentLevel.Level.FULL), ContentLevel.Level.SUGGESTIVE)


func test_allows() -> void:
	assert_true(ContentLevel.allows(ContentLevel.Level.FULL, ContentLevel.Level.SFW))
	assert_false(ContentLevel.allows(ContentLevel.Level.SFW, ContentLevel.Level.SUGGESTIVE))


func test_unknown_values_fall_back_to_sfw() -> void:
	assert_eq(ContentLevel.from_value(2), ContentLevel.Level.FULL)
	assert_eq(ContentLevel.from_value(7), ContentLevel.Level.SFW)
	assert_eq(ContentLevel.from_value(-1), ContentLevel.Level.SFW)
	assert_eq(ContentLevel.from_value("full"), ContentLevel.Level.SFW)


func test_settings_stay_sfw_until_age_is_confirmed() -> void:
	var saved_age: bool = Settings.age_confirmed
	var saved_level: ContentLevel.Level = Settings.content_level
	Settings.age_confirmed = false
	Settings.content_level = ContentLevel.Level.FULL
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW)
	Settings.age_confirmed = true
	assert_eq(Settings.effective_content_level(), ContentLevel.effective(ContentLevel.Level.FULL, Settings.build_cap()))
	Settings.age_confirmed = saved_age
	Settings.content_level = saved_level


func test_settings_round_trip() -> void:
	var path: String = "user://test_settings.cfg"
	var saved: Array = [Settings.age_confirmed, Settings.content_level, Settings.reduce_motion]
	Settings.age_confirmed = true
	Settings.content_level = ContentLevel.Level.SUGGESTIVE
	Settings.reduce_motion = true
	assert_eq(Settings.save_settings(path), OK)
	Settings.age_confirmed = false
	Settings.content_level = ContentLevel.Level.SFW
	Settings.reduce_motion = false
	Settings.load_settings(path)
	assert_true(Settings.age_confirmed)
	assert_eq(Settings.content_level, ContentLevel.Level.SUGGESTIVE)
	assert_true(SceneFlow.reduce_motion, "reduce motion reaches the transition")
	DirAccess.remove_absolute(path)
	Settings.age_confirmed = saved[0]
	Settings.content_level = saved[1]
	Settings.reduce_motion = saved[2]
	SceneFlow.reduce_motion = saved[2]
