class_name PauseMenu
extends Control
## The pause menu (Start or Esc). It uses the neutral third skin from the
## two-halves spec, plain ink on off-white, so it belongs to neither half.
## It holds Resume, the three volumes (Music, Sounds, Menus) and Quit;
## more settings join it later. Quit lives here,
## away from the town's only hold-to-commit button (Mara's #41 review).

signal closed

const PAPER: Color = Color(0.97, 0.97, 0.95)
const INK: Color = Color(0.12, 0.12, 0.12)
const VOLUME_NAMES: Dictionary[String, String] = {"Music": "Music", "SFX": "Sounds", "UI": "Menus"}

var _resume: Button
static var _neutral: Theme


## The neutral skin's theme: the engine's plain font, so the menu never
## takes on the type of the half it opens over.
static func neutral_theme() -> Theme:
	if _neutral == null:
		_neutral = Theme.new()
		_neutral.default_font = ThemeDB.fallback_font
	return _neutral


func _ready() -> void:
	theme = neutral_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	var title: Label = Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", INK)
	stack.add_child(title)
	_resume = _button("Resume")
	_resume.pressed.connect(close)
	stack.add_child(_resume)
	for bus: String in Settings.BUSES:
		stack.add_child(_volume_row(bus))
	var quit: Button = _button("Quit to desktop")
	quit.name = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	stack.add_child(quit)


func open() -> void:
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
	_style_slider(slider)
	slider.value_changed.connect(func(value: float) -> void: Settings.set_volume(bus, value))
	row.add_child(slider)
	return row


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
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 60)
	button.add_theme_font_size_override("font_size", 26)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(0.9, 0.9, 0.88) if state == "hover" else PAPER
		box.border_color = INK
		box.set_border_width_all(4 if state == "focus" else 1)
		box.set_corner_radius_all(4)
		box.set_content_margin_all(12)
		box.draw_center = state != "focus"
		button.add_theme_stylebox_override(state, box)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, INK)
	return button
