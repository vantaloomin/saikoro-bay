class_name PauseMenu
extends Control
## The pause menu (Start or Esc). It uses the neutral third skin from the
## two-halves spec, plain ink on off-white, so it belongs to neither half.
## It holds Resume, the three volumes (Music, Sounds, Menus), the content
## level (AC-2: change it at any time) and Quit; more settings join it
## later. The content level is one row on the main page that opens the
## level rows on a page of their own, so the menu fits a 16:10 screen
## (Mara's #56 review). Quit lives here, away from the town's only hold-to-commit button
## (Mara's #41 review).

signal closed

const PAPER: Color = NeutralSkin.PAPER
const INK: Color = NeutralSkin.INK
const VOLUME_NAMES: Dictionary[String, String] = {"Music": "Music", "SFX": "Sounds", "UI": "Menus"}

var _resume: Button
var _main: VBoxContainer
var _content_page: VBoxContainer
var _content_row: Button
var _content: ContentPicker
var _ask_again: Button
var _confirm: VBoxContainer


## The neutral skin's theme (NeutralSkin.theme).
static func neutral_theme() -> Theme:
	return NeutralSkin.theme()


func _ready() -> void:
	theme = neutral_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(NeutralSkin.shade())
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel: PanelContainer = NeutralSkin.panel(640)
	center.add_child(panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.name = "Main"
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	_main = stack
	stack.add_child(NeutralSkin.label("Paused", 36))
	_resume = _button("Resume")
	_resume.pressed.connect(close)
	stack.add_child(_resume)
	for bus: String in Settings.BUSES:
		stack.add_child(_volume_row(bus))
	_content_row = _button("")
	_content_row.name = "ContentRow"
	_content_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content_row.pressed.connect(open_content_page)
	stack.add_child(_content_row)
	var quit: Button = _button("Quit to desktop")
	quit.name = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	stack.add_child(quit)
	_content_page = _make_content_page()
	panel.add_child(_content_page)
	Settings.changed.connect(_show_content)
	_show_content()


func open() -> void:
	_show_main()
	visible = true
	_resume.grab_focus()


## Back: from the content page to the main page, otherwise closes. The
## half's Esc or B calls this.
func cancel() -> void:
	if _confirm.visible:
		_show_confirm(false)
	elif _content_page.visible:
		_show_main()
		_content_row.grab_focus()
	else:
		close()


func open_content_page() -> void:
	_main.visible = false
	_content_page.visible = true
	_show_content()
	var target: Control = _content.focus_target()
	(target if target != null else _content_page.get_node("Back") as Control).grab_focus()


func is_content_page_open() -> bool:
	return visible and _content_page.visible


## "Adult content · Suggestive  >"
static func content_row_text(level: ContentLevel.Level) -> String:
	return "Adult content · %s  >" % ContentLevel.NAMES[level]


func _show_main() -> void:
	_confirm.visible = false
	_content_page.visible = false
	_main.visible = true
	_show_content()


func _show_content() -> void:
	_content_row.text = content_row_text(Settings.effective_content_level())
	_content.show_settings()
	(_content_page.get_node("Hint") as Control).visible = not _content.is_locked()
	_ask_again.visible = Settings.can_ask_age_again() and not _confirm.visible
	# One way out at a time: Cancel while the question is open.
	(_content_page.get_node("Back") as Control).visible = not _confirm.visible


## Swaps the ask-again button for its confirm, or back.
func _show_confirm(open_it: bool) -> void:
	_confirm.visible = open_it
	_show_content()
	if open_it:
		(_confirm.find_child("No", true, false) as Control).grab_focus()
	elif Settings.can_ask_age_again():
		_ask_again.grab_focus()
	else:
		(_content_page.get_node("Back") as Control).grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## A volume: its name over a slider, saved as it moves.
func _volume_row(bus: String) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.name = bus + "Volume"
	var label: Label = Label.new()
	label.text = VOLUME_NAMES[bus]
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", INK)
	row.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.name = "Slider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volumes.get(bus, 1.0)
	slider.custom_minimum_size = Vector2(0, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(slider)
	# Left and right on a pad or the keys step it by 5%, the slider's step.
	var readout: Label = Label.new()
	readout.name = "Readout"
	readout.custom_minimum_size = Vector2(64, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 24)
	readout.add_theme_color_override("font_color", INK)
	readout.text = percent(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = percent(value)
		Settings.set_volume(bus, value))
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.add_child(slider)
	line.add_child(readout)
	row.add_child(line)
	return row


## The content level's own page: the three rows, saved as soon as one is
## picked (or why it's locked), and Back.
func _make_content_page() -> VBoxContainer:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "ContentPage"
	page.visible = false
	page.add_theme_constant_override("separation", 16)
	page.add_child(NeutralSkin.label("Adult content", 36))
	_content = ContentPicker.new()
	_content.name = "Picker"
	_content.picked.connect(func(level: ContentLevel.Level) -> void:
		if not Settings.set_content_level(level):
			_show_content())
	page.add_child(_content)
	var hint: Label = NeutralSkin.paragraph("Changes the level for every scene.", 22, NeutralSkin.SOFT_INK)
	hint.name = "Hint"
	page.add_child(hint)
	# The way back for an adult who misclicked "under 18": behind a
	# confirm, and only from the next launch (Mara's and Nori's #56 reviews).
	_ask_again = _button("Answer the age question again")
	_ask_again.name = "AskAgain"
	_ask_again.pressed.connect(_show_confirm.bind(true))
	page.add_child(_ask_again)
	_confirm = VBoxContainer.new()
	_confirm.name = "Confirm"
	_confirm.visible = false
	_confirm.add_theme_constant_override("separation", 12)
	_confirm.add_child(NeutralSkin.paragraph("Ask the age question again next time you start the game?", 24))
	var choices: HBoxContainer = HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	var yes: Button = _button("Ask again")
	yes.name = "Yes"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func() -> void:
		Settings.ask_age_again()
		_show_confirm(false))
	choices.add_child(yes)
	var no: Button = _button("Cancel")
	no.name = "No"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(_show_confirm.bind(false))
	choices.add_child(no)
	_confirm.add_child(choices)
	page.add_child(_confirm)
	var back: Button = _button("Back")
	back.name = "Back"
	back.pressed.connect(cancel)
	page.add_child(back)
	return page


## A volume as the menu reads it: "75%".
static func percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


## Plain ink on off-white like the buttons: a grey track, the level filled
## in ink, a round grabber, and a frame when focused.
func _style_slider(slider: HSlider) -> void:
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.82, 0.82, 0.8)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var level: StyleBoxFlat = track.duplicate() as StyleBoxFlat
	level.bg_color = INK
	slider.add_theme_stylebox_override("grabber_area", level)
	slider.add_theme_stylebox_override("grabber_area_highlight", level)
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = INK
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(4)
	focus.set_expand_margin_all(6)
	slider.add_theme_stylebox_override("focus", focus)
	var knob: Image = Image.create(28, 28, false, Image.FORMAT_RGBA8)
	for y: int in 28:
		for x: int in 28:
			var d: float = Vector2(x + 0.5 - 14.0, y + 0.5 - 14.0).length()
			if d <= 13.5:
				knob.set_pixel(x, y, INK if d > 10.0 else PAPER)
	var texture: ImageTexture = ImageTexture.create_from_image(knob)
	for icon: String in ["grabber", "grabber_highlight"]:
		slider.add_theme_icon_override(icon, texture)


func _button(text: String) -> Button:
	return NeutralSkin.button(text)
