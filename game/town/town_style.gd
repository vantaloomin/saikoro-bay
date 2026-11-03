class_name TownStyle
extends RefCounted
## Greybox tokens for the town half (specs/two-halves.md section 1):
## high-key daylight, sand and sea teal with a vermilion accent, washi-paper
## panels with rounded corners and soft shadows. Placeholders until the town
## palette and type land; shapes carry meaning so nothing rests on color
## alone (SA-5).

const SKY: Color = Color(0.96, 0.93, 0.86)
const SAND: Color = Color(0.93, 0.84, 0.66)
const STONE: Color = Color(0.74, 0.72, 0.68)
const SEA: Color = Color(0.29, 0.62, 0.64)
const DOCK: Color = Color(0.62, 0.47, 0.32)
const INK: Color = Color(0.2, 0.17, 0.15)
const DIM: Color = Color(0.45, 0.4, 0.36)
const LOT_LINE: Color = Color(0.55, 0.42, 0.28)
const WASHI: Color = Color(0.99, 0.97, 0.92)
const VERMILION: Color = Color(0.85, 0.3, 0.2)
const ROOF: Dictionary[String, Color] = {
	"home": Color(0.96, 0.95, 0.92), "shop": Color(0.83, 0.86, 0.9),
	"decor": Color(0.95, 0.82, 0.45), "landmark": Color(0.88, 0.36, 0.27),
}
const HAPPY: Color = Color(0.25, 0.6, 0.5)
## Plum: used nowhere else on the map, so no landmark reads as unhappy.
const UNHAPPY: Color = Color(0.47, 0.33, 0.66)
const CLOUD: Color = Color(0.42, 0.46, 0.56)
const SELECTED: Color = Color(0.85, 0.3, 0.2)

## Type sizes at 1080p: body text at least 24 px (SA-6).
const BODY: int = 26
const SMALL: int = 24
const TITLE: int = 34
const MAP_LABEL: int = 22

## Motion (two-halves: floaty, 250-400 ms).
const EASE_SECONDS: float = 0.3


## A washi-paper panel: rounded corners, a soft border and a drop shadow.
static func panel() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = WASHI
	box.border_color = LOT_LINE
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.shadow_color = Color(0.2, 0.15, 0.1, 0.25)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	box.set_content_margin_all(18)
	return box


static func label(text: String, size: int = BODY, color: Color = INK) -> Label:
	var out: Label = Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return out


static func titled_panel(title: String) -> PanelContainer:
	var box: PanelContainer = PanelContainer.new()
	box.add_theme_stylebox_override("panel", panel())
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	box.add_child(stack)
	if not title.is_empty():
		stack.add_child(label(title, TITLE))
	return box


## Sand buttons with an ink frame when focused: the frame is a shape, so
## focus never rests on color alone (two-halves section 3).
static func style_button(button: Button, font_size: int = BODY) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = SAND.lightened(0.25) if state == "hover" else (STONE if state == "disabled" else SAND)
		box.border_color = INK if state == "focus" else LOT_LINE
		box.set_border_width_all(4 if state == "focus" else 2)
		box.set_corner_radius_all(12)
		box.set_content_margin_all(14)
		# Focus draws over the button, so it's a frame with no fill.
		box.draw_center = state != "focus"
		button.add_theme_stylebox_override(state, box)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, INK)
	button.add_theme_color_override("font_disabled_color", DIM)
