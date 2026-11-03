class_name TownStyle
extends RefCounted
## The town half's look (specs/two-halves.md section 1): high-key daylight,
## sand and sea teal with a vermilion accent, washi-paper panels with
## rounded corners and soft shadows (drawn by PaperBox). Shapes carry
## meaning so nothing rests on color alone (SA-5).
##
## Type (M3 PR 5c): M PLUS Rounded 1c for the UI, Klee One for signage and
## handwritten notes (the notes on the notice board).

const UI_FONT_PATH: String = "res://content/sfw/fonts/MPLUSRounded1c-Medium-Latin.ttf"
const STRONG_FONT_PATH: String = "res://content/sfw/fonts/MPLUSRounded1c-Bold-Latin.ttf"
const SIGN_FONT_PATH: String = "res://content/sfw/fonts/KleeOne-SemiBold-Latin.ttf"

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
## The notice board and the shell tray are driftwood; the ledger's spine
## is indigo cloth.
const DRIFTWOOD: Color = Color(0.72, 0.57, 0.4)
const DRIFTWOOD_DARK: Color = Color(0.48, 0.35, 0.24)
const INDIGO: Color = Color(0.22, 0.27, 0.42)
const SHADOW: Color = Color(0.2, 0.15, 0.1, 0.22)
## A fresh tide shell is shell pink, so it stands out on the tray's sand;
## a spent one is only a faded outline.
const SHELL: Color = Color(0.97, 0.78, 0.7)
const SPENT: Color = Color(0.64, 0.56, 0.46)
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


static var _theme: Theme
static var _strong: Font
static var _sign: Font


## The town theme: M PLUS Rounded 1c as the default font, so every label
## and button under the town screen uses it.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = load(UI_FONT_PATH) as Font
		_theme.default_font_size = BODY
	return _theme


## Titles and buttons.
static func strong_font() -> Font:
	if _strong == null:
		_strong = load(STRONG_FONT_PATH) as Font
	return _strong


## Signage and handwritten notes.
static func sign_font() -> Font:
	if _sign == null:
		_sign = load(SIGN_FONT_PATH) as Font
	return _sign


## A washi-paper panel: rounded corners, a hand-drawn border and a drop
## shadow. The HUD's furniture uses PaperBox.make() with its own kind.
static func panel() -> PaperBox:
	return PaperBox.make(PaperBox.Kind.PAPER)


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
		stack.add_child(title_label(title))
	return box


## A panel's title, in the bold weight.
static func title_label(text: String) -> Label:
	var out: Label = label(text, TITLE)
	out.add_theme_font_override("font", strong_font())
	return out


## Sand buttons, hand-drawn like the panels, with a heavy ink frame when
## focused: the frame is a shape, so focus never rests on color alone
## (two-halves section 3).
static func style_button(button: Button, font_size: int = BODY) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_font_override("font", strong_font())
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, button_box(state))
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, INK)
	button.add_theme_color_override("font_disabled_color", DIM)


## One state of a town button. Focus draws over the button, so it's a frame
## with no fill.
static func button_box(state: String) -> PaperBox:
	var box: PaperBox = PaperBox.make(PaperBox.Kind.PAPER, 14.0)
	box.fill = SAND.lightened(0.25) if state == "hover" else (STONE if state == "disabled" else SAND)
	box.radius = 12.0
	box.shadow = state in ["normal", "hover"]
	if state == "pressed":
		box.fill = SAND.darkened(0.06)
	if state == "focus":
		box.draw_fill = false
		box.edge = INK
		box.edge_width = 4.0
	return box


## A tab in the right column's header (Mara's #42 re-review): the open tab
## takes the fill and edge of the sheet under it and is open at the bottom,
## so the two read as one; the others are flat sand with no border. A heavy
## frame is only for focus.
static func style_tab(button: Button, fill: Color = WASHI, edge: Color = LOT_LINE) -> void:
	style_button(button, SMALL)
	for state: String in ["normal", "hover"]:
		var flat: PaperBox = PaperBox.make(PaperBox.Kind.TAB, 12.0)
		flat.fill = SAND.lightened(0.15) if state == "hover" else Color(SAND, 0.92)
		flat.edge_width = 0.0
		button.add_theme_stylebox_override(state, flat)
	for state: String in ["pressed", "hover_pressed"]:
		var open: PaperBox = PaperBox.make(PaperBox.Kind.TAB, 12.0)
		open.fill = fill
		open.edge = edge
		# Reaches down over the sheet's top edge, so the two join.
		open.expand_bottom = 4.0
		button.add_theme_stylebox_override(state, open)
	button.add_theme_color_override("font_hover_pressed_color", INK)
