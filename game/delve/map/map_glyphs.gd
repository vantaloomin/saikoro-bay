class_name MapGlyphs
extends RefCounted
## Room shapes for the delve map (specs/delve-map.md section 8, Mara's
## review #3). The outline says the category and the glyph inside says the
## type, so a room reads at map size and in greyscale:
##   fight     circle            crossed dice
##   elite     8-point starburst crossed dice, larger
##   treasure  rounded square    chest
##   rest      rounded square    lantern
##   rescue    rounded square    open hand behind bars
##   unknown   dashed circle     "?"
##   vault     double-rim circle cat coin
## The landing isn't a node: it's a band across the map with a torii.

const UNKNOWN: String = "?"


## The room's outline, filled with lacquer, in `rect`.
static func draw_outline(canvas: CanvasItem, rect: Rect2, type: String, color: Color, width: float = 4.0) -> void:
	var c: Vector2 = rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) / 2.0
	match type:
		DelveMap.FIGHT:
			canvas.draw_circle(c, r, BoardStyle.LACQUER)
			canvas.draw_arc(c, r - width / 2.0, 0, TAU, 48, color, width, true)
		DelveMap.ELITE:
			var points: PackedVector2Array = starburst(c, r, r * 0.74)
			canvas.draw_colored_polygon(points, BoardStyle.LACQUER)
			points.append(points[0])
			canvas.draw_polyline(points, color, width, true)
		DelveMap.TREASURE, DelveMap.REST, DelveMap.RESCUE:
			var box: StyleBoxFlat = StyleBoxFlat.new()
			box.bg_color = BoardStyle.LACQUER
			box.border_color = color
			box.set_border_width_all(int(width))
			box.set_corner_radius_all(int(r * 0.35))
			box.anti_aliasing = true
			canvas.draw_style_box(box, rect.grow(-r * 0.08))
		DelveMap.VAULT:
			canvas.draw_circle(c, r, BoardStyle.LACQUER)
			canvas.draw_arc(c, r - width / 2.0, 0, TAU, 64, color, width, true)
			canvas.draw_arc(c, r * 0.8, 0, TAU, 64, color, width * 0.75, true)
		_:
			# Unknown: a dashed circle, so it never reads as a fight.
			canvas.draw_circle(c, r, BoardStyle.LACQUER)
			var dashes: int = 14
			for i: int in dashes:
				var a: float = TAU * i / dashes
				canvas.draw_arc(c, r - width / 2.0, a, a + TAU / dashes * 0.55, 6, color, width, true)


## The type's glyph, centered in `rect`.
static func draw_glyph(canvas: CanvasItem, rect: Rect2, type: String, color: Color) -> void:
	var c: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x, rect.size.y)
	match type:
		DelveMap.FIGHT:
			_crossed_dice(canvas, c, s * 0.5, color)
		DelveMap.ELITE:
			_crossed_dice(canvas, c, s * 0.62, color)
		DelveMap.TREASURE:
			_chest(canvas, c, s * 0.55, color)
		DelveMap.REST:
			_lantern(canvas, c, s * 0.6, color)
		DelveMap.RESCUE:
			_caged_hand(canvas, c, s * 0.6, color)
		DelveMap.VAULT:
			_cat_coin(canvas, c, s * 0.55, color)
		_:
			var font: Font = BoardStyle.strong_font()
			var size: int = int(s * 0.55)
			var w: float = font.get_string_size(UNKNOWN, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			canvas.draw_string(font, c + Vector2(-w / 2.0, size * 0.36), UNKNOWN, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## A room: outline and glyph together.
static func draw_room(canvas: CanvasItem, rect: Rect2, type: String, color: Color, width: float = 4.0) -> void:
	draw_outline(canvas, rect, type, color, width)
	draw_glyph(canvas, rect, type, color)


## A torii gate (the landing), centered in `rect`.
static func draw_torii(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var c: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x, rect.size.y)
	var w: float = s * 0.9
	var top: float = c.y - s * 0.36
	# Kasagi: the top beam, lifted at the ends.
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - w / 2, top - s * 0.08), Vector2(c.x + w / 2, top - s * 0.08),
		Vector2(c.x + w * 0.44, top + s * 0.04), Vector2(c.x - w * 0.44, top + s * 0.04),
	]), color)
	# Nuki: the tie beam.
	canvas.draw_rect(Rect2(c.x - w * 0.38, top + s * 0.16, w * 0.76, s * 0.07), color)
	# Posts.
	for side: float in [-1.0, 1.0]:
		var x: float = c.x + side * w * 0.26
		canvas.draw_rect(Rect2(x - s * 0.045, top + s * 0.04, s * 0.09, s * 0.74), color)


static func starburst(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i: int in 16:
		var a: float = TAU * i / 16.0 - PI / 2.0
		points.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return points


static func _crossed_dice(canvas: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var d: float = s * 0.5
	for side: float in [-1.0, 1.0]:
		var center: Vector2 = c + Vector2(side * s * 0.2, side * -s * 0.04)
		var angle: float = side * 0.35
		var corners: PackedVector2Array = []
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(center + (corner * d / 2.0).rotated(angle))
		canvas.draw_colored_polygon(corners, color)
		corners.append(corners[0])
		canvas.draw_polyline(corners, BoardStyle.LACQUER, maxf(2.0, s * 0.04), true)
		var pips: Array = [Vector2(0, 0)] if side < 0 else [Vector2(-0.22, -0.22), Vector2(0.22, 0.22)]
		for pip: Vector2 in pips:
			canvas.draw_circle(center + (pip * d).rotated(angle), d * 0.11, BoardStyle.LACQUER)


static func _chest(canvas: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var body: Rect2 = Rect2(c.x - s / 2, c.y - s * 0.08, s, s * 0.46)
	canvas.draw_rect(body, color)
	# Lid: a low dome.
	var lid: PackedVector2Array = [Vector2(body.position.x, body.position.y), Vector2(body.end.x, body.position.y)]
	for i: int in range(8, -1, -1):
		var a: float = PI * i / 8.0
		lid.append(Vector2(c.x + cos(a) * s / 2, body.position.y - sin(a) * s * 0.3))
	canvas.draw_colored_polygon(lid, color)
	canvas.draw_line(Vector2(body.position.x, body.position.y), Vector2(body.end.x, body.position.y), BoardStyle.LACQUER, maxf(2.0, s * 0.06))
	canvas.draw_rect(Rect2(c.x - s * 0.09, body.position.y - s * 0.05, s * 0.18, s * 0.2), BoardStyle.LACQUER)


static func _lantern(canvas: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var w: float = s * 0.46
	var h: float = s * 0.62
	var body: Rect2 = Rect2(c.x - w / 2, c.y - h / 2 + s * 0.06, w, h)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(w * 0.4))
	canvas.draw_style_box(box, body)
	# Caps and the ribs of a paper lantern.
	canvas.draw_rect(Rect2(c.x - w * 0.32, body.position.y - s * 0.07, w * 0.64, s * 0.08), color)
	canvas.draw_rect(Rect2(c.x - w * 0.32, body.end.y - s * 0.01, w * 0.64, s * 0.08), color)
	for k: float in [0.33, 0.66]:
		var y: float = body.position.y + h * k
		canvas.draw_line(Vector2(body.position.x + 3, y), Vector2(body.end.x - 3, y), BoardStyle.LACQUER, maxf(2.0, s * 0.03))
	canvas.draw_arc(Vector2(c.x, body.position.y - s * 0.12), s * 0.08, PI, TAU, 10, color, maxf(2.0, s * 0.04))


static func _caged_hand(canvas: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	# An open hand, palm out.
	var palm: Vector2 = c + Vector2(0, s * 0.12)
	canvas.draw_circle(palm, s * 0.2, color)
	var finger_w: float = s * 0.09
	for i: int in 4:
		var x: float = palm.x + (i - 1.5) * s * 0.105
		canvas.draw_line(Vector2(x, palm.y - s * 0.05), Vector2(x, palm.y - s * 0.38 + absf(i - 1.5) * s * 0.06), color, finger_w)
	canvas.draw_line(palm + Vector2(-s * 0.14, 0), palm + Vector2(-s * 0.3, -s * 0.16), color, finger_w)
	# Bars in front of it, dark-edged so they read on the hand.
	for k: float in [-0.3, 0.0, 0.3]:
		var x: float = c.x + k * s
		canvas.draw_line(Vector2(x, c.y - s * 0.46), Vector2(x, c.y + s * 0.42), BoardStyle.LACQUER, s * 0.09)
		canvas.draw_line(Vector2(x, c.y - s * 0.46), Vector2(x, c.y + s * 0.42), color, s * 0.045)


static func _cat_coin(canvas: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var coin: Vector2 = c + Vector2(0, s * 0.08)
	var rx: float = s * 0.34
	var ry: float = s * 0.42
	# Ears.
	for side: float in [-1.0, 1.0]:
		canvas.draw_colored_polygon(PackedVector2Array([
			coin + Vector2(side * rx * 0.25, -ry * 0.8), coin + Vector2(side * rx * 0.95, -ry * 0.55),
			coin + Vector2(side * rx * 0.85, -ry * 1.25),
		]), color)
	# An oval koban coin.
	var oval: PackedVector2Array = []
	for i: int in 32:
		var a: float = TAU * i / 32.0
		oval.append(coin + Vector2(cos(a) * rx, sin(a) * ry))
	canvas.draw_colored_polygon(oval, color)
	canvas.draw_line(coin + Vector2(-rx * 0.5, -ry * 0.35), coin + Vector2(rx * 0.5, -ry * 0.35), BoardStyle.LACQUER, maxf(2.0, s * 0.04))
	canvas.draw_line(coin + Vector2(-rx * 0.5, ry * 0.35), coin + Vector2(rx * 0.5, ry * 0.35), BoardStyle.LACQUER, maxf(2.0, s * 0.04))
	canvas.draw_rect(Rect2(coin.x - rx * 0.18, coin.y - ry * 0.18, rx * 0.36, ry * 0.36), BoardStyle.LACQUER)
