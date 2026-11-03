class_name BoardStyle
extends RefCounted
## Greybox tokens for the delve half (specs/two-halves.md section 1): low-key
## indigo and lacquer black with gold and jade, hard edges, no shadows.
## Colors are placeholders until the M6 skin; shapes carry meaning so
## nothing depends on color alone (SA-5).

const BACKGROUND: Color = Color(0.1, 0.06, 0.19)
const FELT: Color = Color(0.13, 0.09, 0.24)
const LACQUER: Color = Color(0.05, 0.04, 0.08)
const GOLD: Color = Color(0.88, 0.72, 0.29)
const JADE: Color = Color(0.36, 0.72, 0.6)
const INK: Color = Color(0.93, 0.9, 0.84)
const DIM: Color = Color(0.55, 0.52, 0.6)
const DANGER: Color = Color(0.9, 0.38, 0.3)
## Waiting, not refused (a half-filled Pair Bet).
const AMBER: Color = Color(0.95, 0.66, 0.25)
const DIE_FACE: Color = Color(0.93, 0.9, 0.84)
const DIE_PIP: Color = Color(0.08, 0.06, 0.12)

## Delve type (two-halves section 1): Barlow Condensed with tabular figures
## for numbers and labels, Shippori Mincho B1 for titles. Barlow is narrow,
## so body text runs a size up to stay readable at 1080p.
const LABEL_FONT_PATH: String = "res://content/sfw/fonts/BarlowCondensed-Medium.ttf"
const STRONG_FONT_PATH: String = "res://content/sfw/fonts/BarlowCondensed-SemiBold.ttf"
const TITLE_FONT_PATH: String = "res://content/sfw/fonts/ShipporiMinchoB1-Bold-Latin.ttf"

const BODY: int = 30
const SMALL: int = 26
const NUMBER: int = 40
const BIG: int = 56

## Motion (two-halves: 80-150 ms, hard stops).
const STEP_SECONDS: float = 0.15
const SNAP_SECONDS: float = 0.09

## Smallest size for dice and pip rulers at 1080p (Mara: 48 px minimum).
const DIE_SIZE: int = 96
const RULER_CELL: int = 48


static var _theme: Theme
static var _strong: Font
static var _title: Font


## The delve theme: Barlow Condensed with tabular figures as the default
## font, so every label and number under the board uses it.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = _tabular(load(LABEL_FONT_PATH) as Font)
		_theme.default_font_size = BODY
	return _theme


## Buttons and emphasis.
static func strong_font() -> Font:
	if _strong == null:
		_strong = _tabular(load(STRONG_FONT_PATH) as Font)
	return _strong


## Titles such as the enemy's name.
static func title_font() -> Font:
	if _title == null:
		_title = load(TITLE_FONT_PATH) as Font
	return _title


static func _tabular(base: Font) -> FontVariation:
	var font: FontVariation = FontVariation.new()
	font.base_font = base
	font.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return font


## Pip positions for faces 1-6 on a unit square.
const PIPS: Dictionary[int, Array] = {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
}


## A flat lacquer panel: hard edges, a thin gold inlay, no shadow.
static func panel(border: Color = GOLD, fill: Color = LACQUER) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(16)
	return box


static func label(text: String, size: int = BODY, color: Color = INK) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Draws a die face (value 1-6) into `rect` on `canvas`.
static func draw_die(canvas: CanvasItem, rect: Rect2, value: int, face: Color = DIE_FACE, pip: Color = DIE_PIP) -> void:
	canvas.draw_rect(rect, face)
	var radius: float = rect.size.x * 0.09
	for spot: Variant in PIPS.get(value, []) as Array:
		canvas.draw_circle(rect.position + (spot as Vector2) * rect.size, radius, pip)


## Focus brackets: four corner marks, a shape rather than a color (two-halves
## section 3), drawn just outside `rect`.
static func draw_brackets(canvas: CanvasItem, rect: Rect2, color: Color = GOLD, width: float = 4.0) -> void:
	var r: Rect2 = rect.grow(6)
	var arm: float = minf(r.size.x, r.size.y) * 0.25
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx: float = 1.0 if corner.x == r.position.x else -1.0
		var sy: float = 1.0 if corner.y == r.position.y else -1.0
		canvas.draw_line(corner, corner + Vector2(arm * sx, 0), color, width)
		canvas.draw_line(corner, corner + Vector2(0, arm * sy), color, width)


## A padlock (House lock), centered in `rect`.
static func draw_padlock(canvas: CanvasItem, rect: Rect2, color: Color = DANGER) -> void:
	var c: Vector2 = rect.get_center()
	var w: float = rect.size.x * 0.42
	var body: Rect2 = Rect2(c.x - w / 2, c.y - w * 0.1, w, w * 0.75)
	canvas.draw_arc(Vector2(c.x, body.position.y), w * 0.3, PI, TAU, 16, color, 5.0)
	canvas.draw_rect(body, color)


## A sword (attack) or shield (guard) glyph in `rect`.
static func draw_intent_glyph(canvas: CanvasItem, rect: Rect2, kind: String, color: Color = INK) -> void:
	var c: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x, rect.size.y)
	match kind:
		"attack":
			canvas.draw_line(c + Vector2(-s * 0.3, s * 0.3), c + Vector2(s * 0.3, -s * 0.3), color, s * 0.1)
			canvas.draw_line(c + Vector2(-s * 0.32, s * 0.08), c + Vector2(-s * 0.08, s * 0.32), color, s * 0.1)
		"guard":
			var pts: PackedVector2Array = [
				c + Vector2(-s * 0.32, -s * 0.34), c + Vector2(s * 0.32, -s * 0.34),
				c + Vector2(s * 0.28, s * 0.05), c + Vector2(0, s * 0.36), c + Vector2(-s * 0.28, s * 0.05),
			]
			canvas.draw_colored_polygon(pts, color)
