class_name ShellTray
extends Control
## This visit's actions as shell tokens, not a count (two-halves section 1):
## a pearl in its shell for the action kept from the last visit, a full
## shell for each fresh one, and an outline for each one spent. Spending
## takes fresh actions first, so the pearl goes last.

const SHELL: float = 25.0
const GAP: float = 10.0

var tokens: Array[String] = []
## How many shells, from the left, are shown in full; the rest wait at a
## fifth while a landmark arrival is staged (Mara's #46 review). -1 is all.
var lit: int = -1
## Drawn at this opacity: 1 normally, WAITING for a shell not lit yet.
var _alpha: float = 1.0

const WAITING: float = 0.2


## The tokens left to right: "kept", then "fresh", then "spent" (and
## "hatched" for one the stamp would spend).
static func tokens_for(data: GameData, state: GameState) -> Array[String]:
	return _tokens(data, state.town.kept, state.town.actions_left)


static func _tokens(data: GameData, kept_now: int, left: int) -> Array[String]:
	var base: int = data.row("town", data.ids("town")[0])["base_actions"]
	left = maxi(left, 0)
	var kept: int = mini(kept_now, left)
	var fresh: int = mini(left - kept, base)
	var out: Array[String] = []
	for i: int in kept:
		out.append("kept")
	for i: int in fresh:
		out.append("fresh")
	for i: int in base - fresh:
		out.append("spent")
	return out


## Words for screen readers and the tooltip, since the shells carry no number.
static func describe(state: GameState) -> String:
	var left: int = state.town.actions_left
	var text: String = "No actions left" if left == 0 else "%d action%s left" % [left, "" if left == 1 else "s"]
	if state.town.kept > 0 and left > 0:
		text += ", 1 kept from your last visit"
	return text


## `spending` shells about to go (the stamp is up) are drawn hatched.
func show_state(data: GameData, state: GameState, spending: int = 0) -> void:
	tokens = tokens_for(data, state)
	if spending > 0:
		var after: Array[String] = _tokens(data, state.town.kept, state.town.actions_left - spending)
		for i: int in tokens.size():
			if tokens[i] != "spent" and after[i] == "spent":
				tokens[i] = "hatched"
	tooltip_text = describe(state)
	custom_minimum_size = Vector2(tokens.size() * (SHELL * 2.0 + GAP), SHELL * 2.0 + 8.0)
	queue_redraw()


func _draw() -> void:
	for i: int in tokens.size():
		var center: Vector2 = Vector2(SHELL + i * (SHELL * 2.0 + GAP), SHELL + 4.0)
		_alpha = WAITING if lit >= 0 and i >= lit else 1.0
		_draw_shell(center, tokens[i])
	_alpha = 1.0


func _draw_shell(center: Vector2, token: String) -> void:
	# A scallop: a fan of ribs over a half-disc, standing on a hinge.
	var points: PackedVector2Array = [center + Vector2(0, SHELL * 0.8)]
	for step: int in 13:
		var angle: float = PI + PI * step / 12.0
		points.append(center + Vector2(cos(angle), sin(angle)) * SHELL)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	if token == "hatched":
		# About to be spent: the outline stays, crossed with ink hatching.
		for step: int in range(-4, 5):
			var x: float = step * SHELL * 0.3
			var line: PackedVector2Array = [center + Vector2(x - SHELL, SHELL), center + Vector2(x + SHELL, -SHELL)]
			for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, points):
				draw_polyline(piece, _c(TownStyle.INK), 1.5, true)
		draw_polyline(outline, _c(TownStyle.INK), 2.5)
		return
	if token != "spent":
		draw_colored_polygon(points, _c(TownStyle.SHELL) if token == "fresh" else _c(TownStyle.WASHI))
	for step: int in range(2, 12, 3):
		var angle: float = PI + PI * step / 12.0
		draw_line(center + Vector2(0, SHELL * 0.8), center + Vector2(cos(angle), sin(angle)) * SHELL,
			_c(TownStyle.LOT_LINE) if token != "spent" else _c(TownStyle.SPENT), 1.5)
	draw_polyline(outline, _c(TownStyle.INK) if token != "spent" else _c(TownStyle.SPENT), 2.5 if token != "spent" else 2.0)
	if token == "kept":
		draw_circle(center + Vector2(0, -SHELL * 0.25), SHELL * 0.32, _c(Color.WHITE))
		draw_arc(center + Vector2(0, -SHELL * 0.25), SHELL * 0.32, 0.0, TAU, 24, _c(TownStyle.INK), 2.0)


func _c(color: Color) -> Color:
	return Color(color, color.a * _alpha)
