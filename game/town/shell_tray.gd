class_name ShellTray
extends Control
## This visit's actions as shell tokens, not a count (two-halves section 1):
## a pearl in its shell for the action kept from the last visit, a full
## shell for each fresh one, and an outline for each one spent. Spending
## takes fresh actions first, so the pearl goes last.

const SHELL: float = 25.0
const GAP: float = 10.0

var tokens: Array[String] = []


## The tokens left to right: "kept", then "fresh", then "spent".
static func tokens_for(data: GameData, state: GameState) -> Array[String]:
	var base: int = data.row("town", data.ids("town")[0])["base_actions"]
	var kept: int = mini(state.town.kept, state.town.actions_left)
	var fresh: int = mini(state.town.actions_left - kept, base)
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


func show_state(data: GameData, state: GameState) -> void:
	tokens = tokens_for(data, state)
	tooltip_text = describe(state)
	custom_minimum_size = Vector2(tokens.size() * (SHELL * 2.0 + GAP), SHELL * 2.0 + 8.0)
	queue_redraw()


func _draw() -> void:
	for i: int in tokens.size():
		var center: Vector2 = Vector2(SHELL + i * (SHELL * 2.0 + GAP), SHELL + 4.0)
		_draw_shell(center, tokens[i])


func _draw_shell(center: Vector2, token: String) -> void:
	# A scallop: a fan of ribs over a half-disc, standing on a hinge.
	var points: PackedVector2Array = [center + Vector2(0, SHELL * 0.8)]
	for step: int in 13:
		var angle: float = PI + PI * step / 12.0
		points.append(center + Vector2(cos(angle), sin(angle)) * SHELL)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	if token != "spent":
		draw_colored_polygon(points, TownStyle.SAND if token == "fresh" else TownStyle.WASHI)
	for step: int in range(2, 12, 3):
		var angle: float = PI + PI * step / 12.0
		draw_line(center + Vector2(0, SHELL * 0.8), center + Vector2(cos(angle), sin(angle)) * SHELL,
			TownStyle.LOT_LINE if token != "spent" else TownStyle.STONE, 1.5)
	draw_polyline(outline, TownStyle.INK if token != "spent" else TownStyle.STONE, 2.5 if token != "spent" else 2.0)
	if token == "kept":
		draw_circle(center + Vector2(0, -SHELL * 0.25), SHELL * 0.32, Color.WHITE)
		draw_arc(center + Vector2(0, -SHELL * 0.25), SHELL * 0.32, 0.0, TAU, 24, TownStyle.INK, 2.0)
