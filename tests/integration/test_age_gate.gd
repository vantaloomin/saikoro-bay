extends GutTest
## The age gate (AC-1), the content level in the pause menu (AC-2) and the
## scene notice (AC-5), on the real Settings autoload with a scratch file.

const PATH: String = "user://test_age_gate.cfg"
const BOOT_SCENE: PackedScene = preload("res://game/boot/boot.tscn")

var _saved: Array


func before_each() -> void:
	_saved = [Settings.age_answer, Settings.content_level, Settings.sfw_build, Settings.file_path]
	Settings.file_path = PATH
	Settings.sfw_build = false
	Settings.age_answer = ContentLevel.AgeAnswer.UNANSWERED
	Settings.content_level = ContentLevel.Level.SFW


func after_each() -> void:
	Settings.age_answer = _saved[0]
	Settings.content_level = _saved[1]
	Settings.sfw_build = _saved[2]
	Settings.file_path = _saved[3]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _gate() -> AgeGate:
	var gate: AgeGate = AgeGate.new()
	add_child_autofree(gate)
	return gate


func test_boot_shows_the_gate_on_a_first_launch() -> void:
	var boot: Control = BOOT_SCENE.instantiate() as Control
	add_child_autofree(boot)
	assert_not_null(boot.get_node_or_null("AgeGate"), "the gate comes before the save loads")


func test_the_gate_warns_before_it_asks() -> void:
	var gate: AgeGate = _gate()
	assert_eq(gate.step, AgeGate.Step.WARNING)
	var warnings: Node = gate.find_child("Warnings", true, false)
	assert_eq(warnings.get_child_count(), AgeGate.WARNINGS.size())
	assert_true((gate.find_child("Adult", true, false) as Button).has_focus(), "a pad can answer at once")
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED)


func test_an_adult_picks_a_level_and_starts() -> void:
	var gate: AgeGate = _gate()
	watch_signals(gate)
	_press_named(gate, "Adult")
	assert_eq(gate.step, AgeGate.Step.LEVEL)
	var picker: ContentPicker = gate.find_child("Picker", true, false) as ContentPicker
	assert_eq(picker.level, ContentLevel.Level.SFW, "SFW is picked until you pick another")
	assert_true(picker.row(ContentLevel.Level.SFW).has_focus())
	picker.row(ContentLevel.Level.FULL).pressed.emit()
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED, "nothing is saved before Start")
	_press_named(gate.find_child("LevelPage", true, false), "Start")
	assert_signal_emitted(gate, "finished")
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.ADULT)
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.FULL)
	assert_false(Settings.needs_age_gate())


func test_under_18_plays_sfw() -> void:
	var gate: AgeGate = _gate()
	watch_signals(gate)
	_press_named(gate, "Under18")
	assert_eq(gate.step, AgeGate.Step.UNDER_18)
	_press_named(gate.find_child("Under18Page", true, false), "Start")
	assert_signal_emitted(gate, "finished")
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNDER_18)
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW)


func test_back_returns_to_the_question() -> void:
	var gate: AgeGate = _gate()
	_press_named(gate, "Adult")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	gate._unhandled_input(esc)
	assert_eq(gate.step, AgeGate.Step.WARNING)
	_press_named(gate, "Under18")
	_press_named(gate.find_child("Under18Page", true, false), "Back")
	assert_eq(gate.step, AgeGate.Step.WARNING)
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED)


func test_the_pause_menu_changes_the_level_at_any_time() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.SFW)
	var menu: PauseMenu = PauseMenu.new()
	add_child_autofree(menu)
	menu.open()
	var picker: ContentPicker = menu.find_child("Picker", true, false) as ContentPicker
	assert_false(picker.is_locked())
	picker.row(ContentLevel.Level.SUGGESTIVE).pressed.emit()
	assert_eq(Settings.content_level, ContentLevel.Level.SUGGESTIVE, "saved as soon as it's picked")
	Settings.set_content_level(ContentLevel.Level.FULL)
	assert_eq(picker.level, ContentLevel.Level.FULL, "follows a change made elsewhere")


func test_the_pause_menu_says_why_the_level_is_locked() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18)
	var menu: PauseMenu = PauseMenu.new()
	add_child_autofree(menu)
	menu.open()
	var picker: ContentPicker = menu.find_child("Picker", true, false) as ContentPicker
	assert_true(picker.is_locked())
	assert_false(picker.row(ContentLevel.Level.FULL).visible)
	assert_string_contains((picker.find_child("Locked", false, false) as Label).text, "under 18")


func test_the_scene_notice_names_the_level_before_the_scene() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.FULL)
	var notice: SceneNotice = SceneNotice.new()
	add_child_autofree(notice)
	watch_signals(notice)
	var levels: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.SUGGESTIVE]
	notice.open_for(levels)
	var line: Label = notice.find_child("Line", true, false) as Label
	assert_eq(line.text, "This scene plays at Suggestive. That's the most it shows.")
	_press_named(notice, "Change")
	var picker: ContentPicker = notice.find_child("Picker", true, false) as ContentPicker
	assert_true(picker.visible)
	picker.row(ContentLevel.Level.SFW).pressed.emit()
	assert_eq(Settings.content_level, ContentLevel.Level.SFW)
	assert_eq(line.text, "This scene plays at Safe for work.", "the line follows the change")
	_press_named(notice, "Play")
	assert_signal_emitted_with_parameters(notice, "play_pressed", [ContentLevel.Level.SFW])
	assert_false(notice.visible)


func test_the_scene_notice_has_nothing_to_change_under_18() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18)
	var notice: SceneNotice = SceneNotice.new()
	add_child_autofree(notice)
	var levels: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.FULL]
	notice.open_for(levels)
	assert_eq((notice.find_child("Line", true, false) as Label).text, "This scene plays at Safe for work.")
	assert_false((notice.find_child("Change", true, false) as Button).visible)


func _press_named(root: Node, button_name: String) -> void:
	var button: Button = root.find_child(button_name, true, false) as Button
	assert_not_null(button, "%s exists" % button_name)
	if button == null:
		return
	assert_true(button.is_visible_in_tree(), "%s shows" % button_name)
	button.pressed.emit()
