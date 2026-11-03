class_name HankoButton
extends Button
## The hanko stamp: the town's only confirm, for an action that costs a
## shell (two-halves section 1). Free actions never ask. A round vermilion
## seal sits at its left; pressing it stamps once and disables the button
## until the screen re-arms it, so a double click can't spend twice
## (Imogen's rule: the stamp waits for the sim's answer).
##
## `stamped` fires when the seal touches the paper, at the bottom of the
## punch, so the build and its sound land on that frame (Mara's #44
## review); with reduce motion there's no punch and it fires at once.

signal stamped

const SEAL_RADIUS: float = 34.0
const PUNCH_SECONDS: float = 0.18


func _ready() -> void:
	TownStyle.style_button(self, TownStyle.TITLE)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBox = get_theme_stylebox(state)
		box.content_margin_left = SEAL_RADIUS * 2.0 + 30.0
	custom_minimum_size = Vector2(0, SEAL_RADIUS * 2.0 + 24.0)
	pressed.connect(_stamp)


## Lets the stamp be pressed again: after the sim said no, say.
func rearm() -> void:
	disabled = false
	queue_redraw()


func _stamp() -> void:
	if disabled:
		return
	disabled = true
	queue_redraw()
	if Settings.reduce_motion or not is_inside_tree():
		stamped.emit()
		return
	pivot_offset = size / 2.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(0.96, 0.96), PUNCH_SECONDS / 2.0)
	tween.tween_callback(stamped.emit)
	tween.tween_property(self, "scale", Vector2.ONE, PUNCH_SECONDS / 2.0)


func _draw() -> void:
	var center: Vector2 = Vector2(SEAL_RADIUS + 18.0, size.y / 2.0)
	var ink: Color = TownStyle.STONE.darkened(0.2) if disabled else TownStyle.VERMILION
	draw_circle(center, SEAL_RADIUS, ink)
	draw_arc(center, SEAL_RADIUS - 5.0, 0.0, TAU, 40, TownStyle.WASHI, 2.5, true)
	# A carved mark in the seal: a little roof over a square, "build".
	var half: float = SEAL_RADIUS * 0.38
	draw_rect(Rect2(center + Vector2(-half, -half * 0.2), Vector2(half * 2.0, half * 1.4)), TownStyle.WASHI, false, 3.0)
	draw_polyline([center + Vector2(-half * 1.3, -half * 0.1), center + Vector2(0, -half * 1.3),
		center + Vector2(half * 1.3, -half * 0.1)], TownStyle.WASHI, 3.0, true)
