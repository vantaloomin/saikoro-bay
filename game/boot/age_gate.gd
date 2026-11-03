class_name AgeGate
extends Control
## The first screen of a build with adult content (AC-1): who the game is
## for, what's in it, and the age question. An adult then picks a content
## level (AC-2). A player under 18 is told adult content stays off and the
## whole game still plays at SFW (Vanta's call on #56).
##
## Nothing is focused when it opens, so mashing A or Enter through a first
## launch can't answer for you: the first press only focuses "I'm 18 or
## older" (SceneFlow's default focus, Mara's #56 review). "Under 18" is
## saved the moment it's pressed and its page has no Back, so it isn't a
## one-press retry; an adult who misclicked can ask again from the pause
## menu, which takes effect next launch. The adult answer is saved at
## "Start".
##
## Boot shows it while Settings.needs_age_gate(). SFW builds never do.

signal finished

enum Step { WARNING, LEVEL, UNDER_18 }

## Keep in step with the store pages' content descriptions (Nori: reviewers
## compare them) and the youngest stated age with the character sheets.
const AGES_LINE: String = "Every character is an adult, 27 or older. The game has:"
const WARNINGS: Array[String] = [
	"Flirting, dates and romance",
	"Swimsuits and towels, even with nudity off",
	"Optional nudity: topless and bare-rear, never sex",
	"Characters drinking alcohol and smoking a pipe",
	"Mild cartoon fights",
	"Casino-style dice games. No real money can be spent or won",
]

var step: Step = Step.WARNING
var _pages: Dictionary[Step, Control] = {}
var _picker: ContentPicker
var _adult: Button
var _start_adult: Button
var _start_under_18: Button


func _ready() -> void:
	theme = NeutralSkin.theme()
	# Made in code, so the offsets have to be set too, or it stays 0 by 0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel: PanelContainer = NeutralSkin.panel(720)
	center.add_child(panel)
	# One page shows at a time; the panel sizes to the visible one.
	_pages[Step.WARNING] = _warning_page()
	_pages[Step.LEVEL] = _level_page()
	_pages[Step.UNDER_18] = _under_18_page()
	for page: Control in _pages.values():
		panel.add_child(page)
	show_step(Step.WARNING)


func show_step(value: Step) -> void:
	step = value
	for key: Step in _pages:
		_pages[key].visible = key == value
	match value:
		Step.WARNING:
			var focused: Control = get_viewport().gui_get_focus_owner()
			if focused != null:
				focused.release_focus()
		Step.LEVEL:
			_picker.row(_picker.level).grab_focus()
		Step.UNDER_18:
			_start_under_18.grab_focus()


func _warning_page() -> Control:
	var page: VBoxContainer = _page("WarningPage")
	page.add_child(NeutralSkin.label("Saikoro Bay is for adults", 40))
	page.add_child(NeutralSkin.paragraph(AGES_LINE, 24))
	var list: VBoxContainer = VBoxContainer.new()
	list.name = "Warnings"
	list.add_theme_constant_override("separation", 6)
	for warning: String in WARNINGS:
		# A dot in its own column, so a wrapped line hangs under the words.
		var item: HBoxContainer = HBoxContainer.new()
		item.add_theme_constant_override("separation", 12)
		var dot: Label = NeutralSkin.label("•", 24)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		item.add_child(dot)
		item.add_child(NeutralSkin.paragraph(warning, 24))
		list.add_child(item)
	page.add_child(list)
	page.add_child(NeutralSkin.paragraph("Nudity stays off unless you turn it on.", 24, NeutralSkin.SOFT_INK))
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	_adult = NeutralSkin.button("I'm 18 or older")
	_adult.name = "Adult"
	_adult.add_to_group(&"default_focus")  # SceneFlow.FOCUS_GROUP
	_adult.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adult.pressed.connect(show_step.bind(Step.LEVEL))
	buttons.add_child(_adult)
	var under_18: Button = NeutralSkin.button("I'm under 18")
	under_18.name = "Under18"
	under_18.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under_18.pressed.connect(_on_under_18)
	buttons.add_child(under_18)
	page.add_child(buttons)
	return page


func _level_page() -> Control:
	var page: VBoxContainer = _page("LevelPage")
	page.add_child(NeutralSkin.label("Choose what scenes show", 40))
	_picker = ContentPicker.new()
	_picker.name = "Picker"
	_picker.set_level(ContentLevel.Level.SFW)
	page.add_child(_picker)
	page.add_child(NeutralSkin.paragraph("You can change this any time from the pause menu.", 22, NeutralSkin.SOFT_INK))
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	var back: Button = NeutralSkin.button("Back")
	back.name = "Back"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(show_step.bind(Step.WARNING))
	buttons.add_child(back)
	_start_adult = NeutralSkin.button("Start")
	_start_adult.name = "Start"
	_start_adult.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_adult.pressed.connect(func() -> void: _finish(ContentLevel.AgeAnswer.ADULT))
	buttons.add_child(_start_adult)
	page.add_child(buttons)
	return page


func _under_18_page() -> Control:
	var page: VBoxContainer = _page("Under18Page")
	page.add_child(NeutralSkin.label("Adult content stays off", 40))
	page.add_child(NeutralSkin.paragraph(
		"You can still play the whole game. Every scene plays its safe-for-work version.", 24))
	_start_under_18 = NeutralSkin.button("Start")
	_start_under_18.name = "Start"
	_start_under_18.pressed.connect(finished.emit)
	page.add_child(_start_under_18)
	return page


func _page(page_name: String) -> VBoxContainer:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = page_name
	page.add_theme_constant_override("separation", 20)
	return page


func _finish(answer: ContentLevel.AgeAnswer) -> void:
	Settings.answer_age_gate(answer, _picker.level)
	finished.emit()


## Saved at once: the under-18 page has no way back.
func _on_under_18() -> void:
	Settings.answer_age_gate(ContentLevel.AgeAnswer.UNDER_18)
	show_step(Step.UNDER_18)


func _unhandled_input(event: InputEvent) -> void:
	# Back steps from the level page to the question; nothing else goes back.
	if event.is_action_pressed(&"ui_cancel") and step == Step.LEVEL:
		show_step(Step.WARNING)
		get_viewport().set_input_as_handled()
