class_name AffectionMeter
extends Control
## The villager card's affection meter (RD-5): one bead per point up to the
## last milestone, filled up to where you are, with each milestone's bead
## drawn larger so the next one reads at a glance. Past the last milestone
## the row stays full.

const BEAD: float = 18.0
const GAP: float = 8.0

var points: int = 0
var marks: Array[int] = []


func show_points(data: GameData, value: int) -> void:
	points = value
	marks.clear()
	for milestone: Dictionary in Affection.milestones(data):
		marks.append(milestone["points"] as int)
	var count: int = marks.back() if not marks.is_empty() else 0
	custom_minimum_size = Vector2(count * (BEAD + GAP), BEAD + 8.0)
	tooltip_text = "Affection %d" % points
	queue_redraw()


func _draw() -> void:
	var count: int = marks.back() if not marks.is_empty() else 0
	for i: int in count:
		var milestone: bool = marks.has(i + 1)
		var radius: float = BEAD * (0.5 if milestone else 0.36)
		var centre: Vector2 = Vector2(i * (BEAD + GAP) + BEAD * 0.5, size.y * 0.5)
		if i < points:
			draw_circle(centre, radius, TownStyle.SHELL)
		draw_arc(centre, radius, 0.0, TAU, 24, TownStyle.LOT_LINE, 2.0, true)
