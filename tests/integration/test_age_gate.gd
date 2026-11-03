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


func test_the_gate_warns_before_it_asks_with_nothing_focused() -> void:
	var gate: AgeGate = _gate()
	assert_eq(gate.step, AgeGate.Step.WARNING)
	var warnings: Node = gate.find_child("Warnings", true, false)
	assert_eq(warnings.get_child_count(), AgeGate.WARNINGS.size())
	assert_null(get_viewport().gui_get_focus_owner(), "mashing A can't answer unread")
	var adult: Button = gate.find_child("Adult", true, false) as Button
	assert_true(adult.is_in_group(SceneFlow.FOCUS_GROUP), "the first press focuses the 18+ button")
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


func test_under_18_plays_sfw_and_the_answer_sticks() -> void:
	var gate: AgeGate = _gate()
	watch_signals(gate)
	_press_named(gate, "Under18")
	assert_eq(gate.step, AgeGate.Step.UNDER_18)
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNDER_18, "saved the moment it's pressed")
	var page: Node = gate.find_child("Under18Page", true, false)
	assert_null(page.find_child("Back", true, false), "no one-press retry")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	gate._unhandled_input(esc)
	assert_eq(gate.step, AgeGate.Step.UNDER_18, "Back doesn't leave it either")
	assert_true((page.find_child("Start", true, false) as Button).has_focus())
	_press_named(page, "Start")
	assert_signal_emitted(gate, "finished")
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW)


func test_back_returns_to_the_question() -> void:
	var gate: AgeGate = _gate()
	_press_named(gate, "Adult")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	gate._unhandled_input(esc)
	assert_eq(gate.step, AgeGate.Step.WARNING)
	_press_named(gate, "Adult")
	_press_named(gate.find_child("LevelPage", true, false), "Back")
	assert_eq(gate.step, AgeGate.Step.WARNING)
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED)


func test_the_pause_menu_changes_the_level_at_any_time() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.SFW)
	var menu: PauseMenu = PauseMenu.new()
	add_child_autofree(menu)
	menu.open()
	var row: Button = menu.find_child("ContentRow", true, false) as Button
	assert_eq(row.text, PauseMenu.content_row_text(ContentLevel.Level.SFW), "one row on the main page")
	var picker: ContentPicker = menu.find_child("Picker", true, false) as ContentPicker
	assert_false(picker.is_visible_in_tree(), "the rows have their own page")
	row.pressed.emit()
	assert_true(menu.is_content_page_open())
	assert_true(picker.row(ContentLevel.Level.SFW).has_focus())
	picker.row(ContentLevel.Level.SUGGESTIVE).pressed.emit()
	assert_eq(Settings.content_level, ContentLevel.Level.SUGGESTIVE, "saved as soon as it's picked")
	menu.cancel()
	assert_false(menu.is_content_page_open(), "Back returns to the main page")
	assert_true(menu.visible, "without closing the menu")
	assert_true(row.has_focus())
	assert_eq(row.text, "Adult content · Suggestive  >")
	Settings.set_content_level(ContentLevel.Level.FULL)
	assert_eq(picker.level, ContentLevel.Level.FULL, "follows a change made elsewhere")
	menu.cancel()
	assert_false(menu.visible)


func test_an_adult_who_misclicked_can_ask_again_next_launch() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18)
	var menu: PauseMenu = PauseMenu.new()
	add_child_autofree(menu)
	menu.open()
	menu.open_content_page()
	var picker: ContentPicker = menu.find_child("Picker", true, false) as ContentPicker
	assert_true(picker.is_locked())
	assert_string_contains((picker.find_child("Locked", false, false) as Label).text, "under 18")
	var ask: Button = menu.find_child("AskAgain", true, false) as Button
	assert_true(ask.is_visible_in_tree())
	ask.pressed.emit()
	var confirm: Control = menu.find_child("Confirm", true, false) as Control
	assert_true(confirm.visible, "behind a confirm")
	assert_true((confirm.find_child("No", true, false) as Button).has_focus(), "Cancel is the safe default")
	menu.cancel()
	assert_false(confirm.visible, "Back cancels it")
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNDER_18)
	ask.pressed.emit()
	_press_named(confirm, "Yes")
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNANSWERED)
	assert_eq(Settings.effective_content_level(), ContentLevel.Level.SFW, "nothing changes this session")
	assert_true(Settings.needs_age_gate(), "the gate shows next launch")
	assert_false(ask.visible)
	assert_string_contains((picker.find_child("Locked", false, false) as Label).text, "next time you start")


func test_adults_and_sfw_builds_get_no_ask_again() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT)
	assert_false(Settings.can_ask_age_again())
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18)
	Settings.sfw_build = true
	assert_false(Settings.can_ask_age_again())
	Settings.ask_age_again()
	assert_eq(Settings.age_answer, ContentLevel.AgeAnswer.UNDER_18, "refused")


func test_the_pause_menu_says_why_the_level_is_locked() -> void:
	Settings.sfw_build = true
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.FULL)
	var menu: PauseMenu = PauseMenu.new()
	add_child_autofree(menu)
	menu.open()
	assert_eq((menu.find_child("ContentRow", true, false) as Button).text, PauseMenu.content_row_text(ContentLevel.Level.SFW))
	menu.open_content_page()
	var picker: ContentPicker = menu.find_child("Picker", true, false) as ContentPicker
	assert_true(picker.is_locked())
	assert_false(picker.row(ContentLevel.Level.FULL).visible)
	assert_string_contains((picker.find_child("Locked", false, false) as Label).text, "This edition has no adult content")
	assert_true((menu.find_child("Back", true, false) as Button).has_focus())


func test_the_scene_notice_names_the_level_before_the_scene() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.FULL)
	var notice: SceneNotice = SceneNotice.new()
	add_child_autofree(notice)
	watch_signals(notice)
	var levels: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.SUGGESTIVE]
	notice.open_for(levels)
	assert_true(notice.is_waiting(), "above SFW it waits for Play")
	assert_true((notice.find_child("Play", true, false) as Button).has_focus())
	var line: Label = notice.find_child("Line", true, false) as Label
	var cap: Label = notice.find_child("Cap", true, false) as Label
	assert_eq(line.text, "This scene: Suggestive")
	assert_eq(cap.text, "Your setting is Full. This scene goes no further than Suggestive.")
	_press_named(notice, "Change")
	var picker: ContentPicker = notice.find_child("Picker", true, false) as ContentPicker
	assert_true(picker.visible)
	assert_true((notice.find_child("Hint", true, false) as Label).visible, "says it's for every scene")
	picker.row(ContentLevel.Level.SUGGESTIVE).pressed.emit()
	assert_false(cap.visible, "the lines follow the change")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	notice._unhandled_input(esc)
	assert_false(picker.visible, "B returns to the notice")
	assert_true(notice.is_waiting())
	Settings.set_content_level(ContentLevel.Level.FULL)
	assert_true(cap.visible, "and to a change made elsewhere")
	_press_named(notice, "Play")
	assert_signal_emitted_with_parameters(notice, "play_pressed", [ContentLevel.Level.SUGGESTIVE])
	assert_false(notice.visible)


func test_at_sfw_the_notice_is_a_banner_and_the_scene_starts() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.ADULT, ContentLevel.Level.SFW)
	var notice: SceneNotice = SceneNotice.new()
	add_child_autofree(notice)
	watch_signals(notice)
	var levels: Array[ContentLevel.Level] = [ContentLevel.Level.SFW, ContentLevel.Level.FULL]
	notice.open_for(levels)
	assert_false(notice.is_waiting(), "nothing to choose at SFW")
	var banner: Control = notice.find_child("Banner", true, false) as Control
	assert_true(banner.visible)
	assert_eq((banner.find_child("Line", true, false) as Label).text, "This scene: Safe for work")
	await wait_physics_frames(2)
	assert_signal_emitted_with_parameters(notice, "play_pressed", [ContentLevel.Level.SFW])
	await wait_seconds(SceneNotice.BANNER_SECONDS + SceneNotice.BANNER_FADE_SECONDS + 0.2)
	assert_false(notice.visible, "the banner fades on its own")


func _press_named(root: Node, button_name: String) -> void:
	var button: Button = root.find_child(button_name, true, false) as Button
	assert_not_null(button, "%s exists" % button_name)
	if button == null:
		return
	assert_true(button.is_visible_in_tree(), "%s shows" % button_name)
	button.pressed.emit()
