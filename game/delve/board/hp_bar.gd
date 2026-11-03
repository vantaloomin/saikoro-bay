class_name HpBar
extends Control
## An HP bar with a ghost chunk: the part End turn would take off is drawn
## hatched, so the result of the turn reads without numbers or color (SA-5).

var max_hp: int = 1:
	set(v):
		max_hp = maxi(v, 1)
		queue_redraw()
var hp: int = 0:
	set(v):
		hp = v
		queue_redraw()
## HP this turn would remove (0 = none).
var ghost: int = 0:
	set(v):
		ghost = v
		queue_redraw()
## HP this turn would add (0 = none): drawn hatched past the bar's end,
## the mirror of the ghost (Mara, #30).
var gain: int = 0:
	set(v):
		gain = v
		queue_redraw()
var fill: Color = BoardStyle.JADE


func _init() -> void:
	custom_minimum_size = Vector2(0, 28)


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, BoardStyle.FELT)
	var per: float = size.x / max_hp
	var kept: int = clampi(hp - ghost, 0, hp)
	draw_rect(Rect2(0, 0, per * kept, size.y), fill)
	if ghost > 0 and hp > kept:
		var ghost_rect: Rect2 = Rect2(per * kept, 0, per * (hp - kept), size.y)
		draw_rect(ghost_rect, fill.darkened(0.55))
		var x: float = ghost_rect.position.x - size.y
		while x < ghost_rect.end.x:
			var a: Vector2 = Vector2(maxf(x, ghost_rect.position.x), size.y - (maxf(x, ghost_rect.position.x) - x))
			var b: Vector2 = Vector2(minf(x + size.y, ghost_rect.end.x), size.y - (minf(x + size.y, ghost_rect.end.x) - x))
			draw_line(a, b, fill, 3.0)
			x += 10
		draw_rect(ghost_rect, BoardStyle.INK, false, 2.0)
	var added: int = clampi(gain, 0, max_hp - hp)
	if added > 0:
		var gain_rect: Rect2 = Rect2(per * hp, 0, per * added, size.y)
		_hatch(gain_rect, fill.lightened(0.35))
		draw_rect(gain_rect, BoardStyle.INK, false, 2.0)


func _hatch(r: Rect2, color: Color) -> void:
	var x: float = r.position.x - size.y
	while x < r.end.x:
		var a: Vector2 = Vector2(maxf(x, r.position.x), size.y - (maxf(x, r.position.x) - x))
		var b: Vector2 = Vector2(minf(x + size.y, r.end.x), size.y - (minf(x + size.y, r.end.x) - x))
		draw_line(a, b, color, 3.0)
		x += 10
