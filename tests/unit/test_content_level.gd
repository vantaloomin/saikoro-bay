extends GutTest
## ContentLevel and the Settings rules around it: the age gate's answer
## (AC-1), picking a level (AC-2) and the level a scene plays at (AC-5).

const PATH: String = "user://test_content_settings.cfg"

var _saved: Array


func before_each() -> void:
	_saved = [Settings.age_answer, Settings.content_level, Settings.reduce_motion, Settings.sfw_build, Settings.file_path]
	Settings.file_path = PATH
	Settings.sfw_build = false


func after_each() -> void:
	Settings.age_answer = _saved[0]
	Settings.content_level = _saved[1]
	Settings.reduce_motion = _saved[2]
	SceneFlow.reduce_motion = _saved[2]
	Settings.sfw_build = _saved[3]
	Settings.file_path = _saved[4]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


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


func test_every_level_has_a_name_and_a_description() -> void:
	for level: ContentLevel.Level in ContentLevel.Level.values():
		assert_true(ContentLevel.NAMES.has(level))
		assert_true(ContentLevel.DESCRIPTIONS.has(level))


func test_a_scene_plays_at_the_highest_version_the_level_allows() -> void:
	var all: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.SUGGESTIVE, ContentLevel.Level.FULL]
	var tops_at_suggestive: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.SUGGESTIVE]
	var skips_suggestive: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.FULL]
	var none: Array[ContentLevel.Level] = []
	assert_eq(ContentLevel.shown_level(ContentLevel.Level.FULL, all), ContentLevel.Level.FULL)
	assert_eq(ContentLevel.shown_level(ContentLevel.Level.SUGGESTIVE, all), ContentLevel.Level.SUGGESTIVE)
	assert_eq(ContentLevel.shown_level(ContentLevel.Level.FULL, tops_at_suggestive), ContentLevel.Level.SUGGESTIVE)
	assert_eq(ContentLevel.shown_level(ContentLevel.Level.SUGGESTIVE, skips_suggestive), ContentLevel.Level.SFW,
		"never above the player's level")
	assert_eq(ContentLevel.shown_level(ContentLevel.Level.FULL, none), ContentLevel.Level.SFW, "SFW is the floor")


func test_the_notice_says_when_a_scene_tops_out_below_your_level() -> void:
	assert_eq(ContentLevel.notice_line(ContentLevel.Level.SUGGESTIVE, ContentLevel.Level.SUGGESTIVE),
		"This scene plays at Suggestive.")
	assert_eq(ContentLevel.notice_line(ContentLevel.Level.SUGGESTIVE, ContentLevel.Level.FULL),
		"This scene plays at Suggestive. That's the most it shows.")


func test_settings_stay_sfw_until_the_player_says_they_are_an_adult() -> void:
	Settings.content_level = ContentLevel.Level.FULL
	for answer: ContentLevel.AgeAnswer in [ContentLevel.AgeAnswer.UNANSWERED, ContentLevel.AgeAnswer.UNDER_18]:
		Settings.age_answer = answer
		assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW)
		assert_false(Settings.can_choose_level())
		assert_ne(Settings.level_locked_reason(), "", "and the pickers say why")
	Settings.age_answer = ContentLevel.AgeAnswer.ADULT
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.FULL)
	assert_true(Settings.can_choose_level())
	assert_eq(Settings.level_locked_reason(), "")


func test_the_gate_shows_once_and_never_in_a_sfw_build() -> void:
	Settings.age_answer = ContentLevel.AgeAnswer.UNANSWERED
	assert_true(Settings.needs_age_gate())
	Settings.sfw_build = true
	assert_false(Settings.needs_age_gate(), "a SFW build has nothing to gate")
	Settings.sfw_build = false
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18)
	assert_false(Settings.needs_age_gate(), "either answer is final")
	Settings.age_answer = ContentLevel.AgeAnswer.UNANSWERED
	Settings.load_settings()
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNDER_18, "and saved")


func test_under_18_always_means_sfw() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18, ContentLevel.Level.FULL)
	assert_eq(Settings.content_level, ContentLevel.Level.SFW)
	assert_false(Settings.set_content_level(ContentLevel.Level.FULL), "the pause menu can't raise it")
	assert_eq(Settings.content_level, ContentLevel.Level.SFW)
	assert_true(Settings.set_content_level(ContentLevel.Level.SFW))


func test_a_sfw_build_caps_an_adult_at_sfw() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.FULL)
	Settings.sfw_build = true
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW)
	assert_false(Settings.can_choose_level())
	assert_eq(Settings.level_locked_reason(), "This edition has no adult content.")


func test_an_adult_can_change_level_at_any_time() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.SUGGESTIVE)
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SUGGESTIVE)
	assert_true(Settings.set_content_level(ContentLevel.Level.FULL))
	assert_true(Settings.set_content_level(ContentLevel.Level.SFW))
	Settings.content_level = ContentLevel.Level.FULL
	Settings.load_settings()
	assert_eq(Settings.content_level, ContentLevel.Level.SFW, "each change is saved")


func test_settings_round_trip() -> void:
	Settings.age_answer = ContentLevel.AgeAnswer.ADULT
	Settings.content_level = ContentLevel.Level.SUGGESTIVE
	Settings.reduce_motion = true
	assert_eq(Settings.save_settings(), OK)
	Settings.age_answer = ContentLevel.AgeAnswer.UNANSWERED
	Settings.content_level = ContentLevel.Level.SFW
	Settings.reduce_motion = false
	Settings.load_settings()
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.ADULT)
	assert_eq(Settings.content_level, ContentLevel.Level.SUGGESTIVE)
	assert_true(SceneFlow.reduce_motion, "reduce motion reaches the transition")


func test_a_bad_or_old_age_answer_asks_again() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "age", 9)
	config.save(PATH)
	Settings.age_answer = ContentLevel.AgeAnswer.ADULT
	Settings.load_settings()
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED)
	config = ConfigFile.new()
	config.set_value("content", "age_confirmed", false)
	config.set_value("content", "level", 2)
	config.save(PATH)
	Settings.load_settings()
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED, "files from before the gate ask")
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW)
