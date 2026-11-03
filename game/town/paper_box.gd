class_name PaperBox
extends StyleBox
## The town's panels, drawn by hand (two-halves section 1: washi paper
## with rounded corners, a soft hand-drawn border and drop shadows). Each
## kind is a thing that belongs in the world, so the HUD hugs the edges as
## furniture rather than as windows (M3 PR 5c, the HUD frame):
##
## - PAPER: a washi sheet. Cards, sheets and buttons.
## - LEDGER: a washi page with an indigo cloth spine stitched down its left.
## - BOARD: a driftwood notice board with a paper note pinned to it.
## - TRAY: a driftwood tray with sand in it, where the tide shells sit.
## - TAB: a washi tab open at the bottom, joined to the sheet under it.
##
## The border wobbles a little, the same way every time (`grain` picks the
## wobble), so panels look drawn, not stamped out.

enum Kind { PAPER, LEDGER, BOARD, TRAY, TAB }

## How far the edge strays from a true line, in pixels.
const WOBBLE: float = 0.9
const SPINE: float = 16.0
const RIM: float = 12.0

var kind: Kind = Kind.PAPER
var fill: Color = TownStyle.WASHI
var edge: Color = TownStyle.LOT_LINE
var edge_width: float = 2.0
var radius: float = 14.0
var draw_fill: bool = true
var shadow: bool = true
var grain: int = 0
## Drawn this far past the bottom of its control: a tab reaches down over
## the edge of the sheet it joins.
var expand_bottom: float = 0.0


static func make(of_kind: Kind, margin: float = 18.0) -> PaperBox:
	var box: PaperBox = PaperBox.new()
	box.kind = of_kind
	box.set_content_margin_all(margin)
	match of_kind:
		Kind.LEDGER:
			box.content_margin_left = margin + SPINE
		Kind.BOARD, Kind.TRAY:
			box.fill = TownStyle.DRIFTWOOD
			box.edge = TownStyle.DRIFTWOOD_DARK
			box.set_content_margin_all(margin + RIM)
		Kind.TAB:
			box.shadow = false
			box.radius = 12.0
	return box


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	rect.size.y += expand_bottom
	var outline: PackedVector2Array = _rounded(rect, radius, kind == Kind.TAB)
	if shadow and draw_fill:
		var soft: PackedVector2Array = _rounded(rect.grow(3.0), radius + 3.0, false)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(soft, Vector2(0, 5)), [Color(TownStyle.SHADOW, TownStyle.SHADOW.a * 0.4)])
		RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(outline, Vector2(0, 4)), [TownStyle.SHADOW])
	if draw_fill:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, outline, [fill])
	match kind:
		Kind.LEDGER:
			_draw_spine(to_canvas_item, rect)
		Kind.BOARD:
			_draw_note(to_canvas_item, rect)
		Kind.TRAY:
			_draw_sand(to_canvas_item, rect)
	if edge_width > 0.0:
		var line: PackedVector2Array = outline.duplicate()
		if kind != Kind.TAB:
			line.append(outline[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, line, [edge], edge_width, true)


## The ledger's cloth spine: indigo down the left edge, stitched in washi.
func _draw_spine(item: RID, rect: Rect2) -> void:
	var spine: Rect2 = Rect2(rect.position, Vector2(SPINE, rect.size.y))
	var cloth: PackedVector2Array = _rounded(spine, radius, false)
	# Square the spine's right side, so it reads as a strip bound on.
	for i: int in cloth.size():
		cloth[i].x = minf(cloth[i].x, spine.end.x)
	RenderingServer.canvas_item_add_polygon(item, cloth, [TownStyle.INDIGO])
	var y: float = rect.position.y + 14.0
	while y + 8.0 < rect.end.y - 10.0:
		RenderingServer.canvas_item_add_line(item, Vector2(spine.get_center().x, y), Vector2(spine.get_center().x, y + 8.0),
			TownStyle.WASHI, 2.0, true)
		y += 18.0


## The notice board's pinned note: washi inset in the driftwood, with a
## brass pin at each top corner (vermilion is only ever the seal).
func _draw_note(item: RID, rect: Rect2) -> void:
	var note: Rect2 = rect.grow(-RIM)
	var paper: PackedVector2Array = _rounded(note, 4.0, false)
	RenderingServer.canvas_item_add_polygon(item, _moved(paper, Vector2(0, 2)), [TownStyle.SHADOW])
	RenderingServer.canvas_item_add_polygon(item, paper, [TownStyle.WASHI])
	for corner: Vector2 in [note.position + Vector2(16, 12), Vector2(note.end.x - 16, note.position.y + 12)]:
		RenderingServer.canvas_item_add_circle(item, corner + Vector2(0, 1.5), 5.0, TownStyle.SHADOW)
		RenderingServer.canvas_item_add_circle(item, corner, 5.0, TownStyle.BRASS)
		RenderingServer.canvas_item_add_circle(item, corner + Vector2(-1.5, -1.5), 1.6, TownStyle.WASHI)


## The shell tray: sand in a driftwood rim, a little shade under the top
## rim so the sand sits below it.
func _draw_sand(item: RID, rect: Rect2) -> void:
	var bed: Rect2 = rect.grow(-RIM)
	var sand: PackedVector2Array = _rounded(bed, maxf(radius - RIM, 4.0), false)
	RenderingServer.canvas_item_add_polygon(item, sand, [TownStyle.SAND.lightened(0.12)])
	RenderingServer.canvas_item_add_rect(item, Rect2(bed.position + Vector2(6, 0), Vector2(bed.size.x - 12, 4)), TownStyle.SHADOW)


## A rounded rect as a wobbly loop of points, clockwise from the top left.
## `open_bottom` squares the bottom corners and leaves the bottom edge out
## (a tab): the points run from the bottom left, round the top, to the
## bottom right.
func _rounded(rect: Rect2, r: float, open_bottom: bool) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) / 2.0)
	var centers: Array[Vector2] = [
		Vector2(rect.position.x + r, rect.position.y + r), Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r), Vector2(rect.position.x + r, rect.end.y - r),
	]
	var points: PackedVector2Array = []
	if open_bottom:
		points.append(Vector2(rect.position.x, rect.end.y))
		_edge(points, _arc_point(centers, r, 0, 0.0), 0)
		_arc(points, centers, r, 0)
		_edge(points, _arc_point(centers, r, 1, 0.0), 1)
		_arc(points, centers, r, 1)
		_edge(points, rect.end, 2)
		points.append(rect.end)
		return points
	for c: int in 4:
		_arc(points, centers, r, c)
		_edge(points, _arc_point(centers, r, (c + 1) % 4, 0.0), c)
	return points


## Corner `c` (top left, top right, bottom right, bottom left) at `t` along
## its quarter circle.
static func _arc_point(centers: Array[Vector2], r: float, c: int, t: float) -> Vector2:
	var angle: float = PI + (c + t) * PI / 2.0
	return centers[c] + Vector2(cos(angle), sin(angle)) * r


static func _arc(points: PackedVector2Array, centers: Array[Vector2], r: float, c: int) -> void:
	for step: int in 7:
		points.append(_arc_point(centers, r, c, step / 6.0))


## Points along a straight edge from the last point towards `to` (not
## including it), nudged off the line so the edge looks drawn.
func _edge(points: PackedVector2Array, to: Vector2, side: int) -> void:
	var from: Vector2 = points[points.size() - 1]
	var length: float = from.distance_to(to)
	if length <= 0.0:
		return
	var steps: int = maxi(1, int(length / 24.0))
	var normal: Vector2 = (to - from).orthogonal().normalized()
	for s: int in range(1, steps):
		points.append(from.lerp(to, float(s) / steps) + normal * sin(s * 1.9 + grain * 2.3 + side) * WOBBLE)


static func _moved(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = points.duplicate()
	for i: int in out.size():
		out[i] += by
	return out
