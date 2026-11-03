class_name PauseMenu
extends Control
## The pause menu (Start or Esc). It uses the neutral third skin from the
## two-halves spec, plain ink on off-white, so it belongs to neither half.
## For now it holds Resume and Quit; settings join it later. Quit lives here,
## away from the town's only hold-to-commit button (Mara's #41 review).

signal closed

const PAPER: Color = Color(0.97, 0.97, 0.95)
const INK: Color = Color(0.12, 0.12, 0.12)

var _resume: Button


func _ready() -> void:
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
