class_name PauseMenu
extends Control
## The pause menu (Start or Esc). It uses the neutral third skin from the
## two-halves spec, plain ink on off-white, so it belongs to neither half.
## It holds Resume, the three volumes (Music, Sounds, Menus), the content
## level (AC-2: change it at any time) and Quit; more settings join it
## later. Quit lives here, away from the town's only hold-to-commit button
## (Mara's #41 review).

signal closed

const PAPER: Color = NeutralSkin.PAPER
const INK: Color = NeutralSkin.INK
const VOLUME_NAMES: Dictionary[String, String] = {"Music": "Music", "SFX": "Sounds", "UI": "Menus"}

var _resume: Button
var _content: ContentPicker


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
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	stack.add_child(NeutralSkin.label("Paused", 36))
	_resume = _button("Resume")
	_resume.pressed.connect(close)
	stack.add_child(_resume)
	for bus: String in Settings.BUSES:
		stack.add_child(_volume_row(bus))
	stack.add_child(_content_section())
	var quit: Button = _button("Quit to desktop")
	quit.name = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	stack.add_child(quit)


func open() -> void:
	_content.show_settings()
	visible = true
	_resume.grab_focus()


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


## "Adult content" over the three levels, saved as soon as one is picked.
func _content_section() -> Control:
	var section: VBoxContainer = VBoxContainer.new()
	section.name = "Content"
	section.add_theme_constant_override("separation", 8)
	section.add_child(NeutralSkin.label("Adult content", 24))
	_content = ContentPicker.new()
	_content.name = "Picker"
	_content.picked.connect(func(level: ContentLevel.Level) -> void:
		if not Settings.set_content_level(level):
			_content.show_settings())
	Settings.changed.connect(_content.show_settings)
	section.add_child(_content)
	return section


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
