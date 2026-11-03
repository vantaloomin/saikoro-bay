class_name NeutralSkin
extends RefCounted
## The neutral third skin from the two-halves spec (section 2): plain ink on
## off-white in the engine's plain font, so the pause menu, the age gate
## and the scene notice belong to neither half.

const PAPER: Color = Color(0.97, 0.97, 0.95)
const INK: Color = Color(0.12, 0.12, 0.12)
## Second-line text: descriptions and hints.
const SOFT_INK: Color = Color(0.32, 0.32, 0.3)
const HOVER: Color = Color(0.9, 0.9, 0.88)
## A picked option in a row of choices.
const PICKED: Color = Color(0.84, 0.84, 0.8)

static var _theme: Theme


## The skin's theme: the engine's plain font, so these screens never take
## on the type of the half they open over.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = ThemeDB.fallback_font
	return _theme


## An off-white sheet with an ink border.
static func panel(width: float) -> PanelContainer:
	var panel_container: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(32)
	panel_container.add_theme_stylebox_override("panel", box)
	panel_container.custom_minimum_size = Vector2(width, 0)
	return panel_container


## A dimmed full-screen backdrop that eats clicks meant for what's behind.
static func shade(alpha: float = 0.35) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(0, 0, 0, alpha)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func label(text: String, size: int = 24, color: Color = INK) -> Label:
	var line: Label = Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", size)
	line.add_theme_color_override("font_color", color)
	return line


## A label that wraps to the panel's width.
static func paragraph(text: String, size: int = 24, color: Color = INK) -> Label:
	var line: Label = label(text, size, color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(0, 0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


static func button(text: String) -> Button:
	var plain: Button = Button.new()
	plain.text = text
	plain.custom_minimum_size = Vector2(0, 60)
	plain.add_theme_font_size_override("font_size", 26)
	style_button(plain)
	return plain


## Ink on off-white; a thick frame when focused, and a darker fill when
## it's the picked one of a row of toggle buttons.
static func style_button(target: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = PAPER
		if state == "hover":
			box.bg_color = HOVER
		elif state in ["pressed", "hover_pressed"]:
			box.bg_color = PICKED
		box.border_color = INK if state != "disabled" else SOFT_INK
		box.set_border_width_all(4 if state == "focus" else 1)
		if state in ["pressed", "hover_pressed"]:
			box.set_border_width_all(3)
		box.set_corner_radius_all(4)
		box.set_content_margin_all(12)
		box.draw_center = state != "focus"
		target.add_theme_stylebox_override(state, box)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(color_name, INK)
	target.add_theme_color_override("font_disabled_color", SOFT_INK)
