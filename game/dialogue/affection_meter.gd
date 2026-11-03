class_name AffectionMeter
extends Control
## The affection meter (RD-5), on the villager card and the date's result:
## one bead per milestone, filled as far as you've come towards it, so
## "+3" on the result lands on the same picture the card shows (Mara's
## date-flow review). Every bead full means every milestone is reached.
## On the result the fill grows from `from` to the points (a fade-like
## grow; reduce motion shows the end at once).

const BEAD: float = 22.0
const GAP: float = 10.0
const GROW_SECONDS: float = 0.6

## Affection being shown (a float while it grows).
var shown: float = 0.0
## Milestone points in rising order.
var marks: Array[int] = []
## Where to grow from once in the tree, or -1.
var _grow_from: int = -1


## Shows `points`, growing from `from` when it's lower and motion is on.
func show_points(data: GameData, points: int, from: int = -1) -> void:
	marks.clear()
	for milestone: Dictionary in Affection.milestones(data):
		marks.append(milestone["points"] as int)
	custom_minimum_size = Vector2(marks.size() * (BEAD + GAP), BEAD + 8.0)
	tooltip_text = "Affection %d" % points
	shown = float(points)
	if from >= 0 and from < points and not Settings.reduce_motion and is_inside_tree():
		shown = float(from)
		create_tween().tween_method(_set_shown, float(from), float(points), GROW_SECONDS)
	elif from >= 0 and from < points and not is_inside_tree():
		_grow_from = from
	queue_redraw()




func _ready() -> void:
	if _grow_from >= 0 and not Settings.reduce_motion:
		var target: float = shown
		shown = float(_grow_from)
		create_tween().tween_method(_set_shown, float(_grow_from), target, GROW_SECONDS)
	_grow_from = -1


func _set_shown(value: float) -> void:
	shown = value
	queue_redraw()


## How full bead `index` is, 0 to 1, at `points`.
static func fill(marks_in: Array[int], index: int, points: float) -> float:
	var low: float = 0.0 if index == 0 else float(marks_in[index - 1])
	var high: float = float(marks_in[index])
	return clampf((points - low) / maxf(high - low, 1.0), 0.0, 1.0)


func _draw() -> void:
	for i: int in marks.size():
		var centre: Vector2 = Vector2(i * (BEAD + GAP) + BEAD * 0.5, size.y * 0.5)
		var radius: float = BEAD * 0.5
		var amount: float = fill(marks, i, shown)
		if amount >= 1.0:
			draw_circle(centre, radius, TownStyle.SHELL)
		elif amount > 0.0:
			# Filled from the bottom up, like water in a cup.
			var top: float = centre.y + radius - amount * radius * 2.0
			var points: PackedVector2Array = []
			for step: int in 25:
				var angle: float = PI * 0.5 + TAU * step / 24.0
				var at: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
				points.append(Vector2(at.x, maxf(at.y, top)))
			draw_colored_polygon(points, TownStyle.SHELL)
		draw_arc(centre, radius, 0.0, TAU, 32, TownStyle.LOT_LINE, 2.0, true)
