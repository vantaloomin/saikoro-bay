class_name FaceChip
extends Control
## A villager's face chip, so a perk shows who gives it (KP-2). Placeholder
## until portraits exist: a disc in the villager's color with their initials.

## Placeholder colors per villager id; anything else draws in DIM.
const COLORS: Dictionary[String, Color] = {
	"pearl_diver": Color(0.33, 0.62, 0.82),
	"shipwright": Color(0.72, 0.5, 0.32),
	"onsen_keeper": Color(0.86, 0.5, 0.58),
	"shrine_keeper": Color(0.92, 0.55, 0.22),
}

var villager_id: String = "":
	set(v):
		villager_id = v
		queue_redraw()
## The words the initials come from, such as "Pearl diver".
var role: String = "":
	set(v):
		role = v
		queue_redraw()
var dimmed: bool = false:
	set(v):
		dimmed = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func initials() -> String:
	var out: String = ""
	for word: String in role.split(" ", false):
		out += word.substr(0, 1).to_upper()
	return out.substr(0, 2)


func _draw() -> void:
	var radius: float = minf(size.x, size.y) / 2.0
	var center: Vector2 = size / 2.0
	var fill: Color = COLORS.get(villager_id, BoardStyle.DIM)
	if dimmed:
		fill = fill.darkened(0.5)
	draw_circle(center, radius, fill)
	draw_arc(center, radius - 1, 0, TAU, 32, BoardStyle.LACQUER, 2.0)
	var font: Font = get_theme_default_font()
	var text: String = initials()
	var font_size: int = int(radius * 0.95)
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-w / 2.0, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BoardStyle.LACQUER)
