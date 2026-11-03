class_name DieView
extends Button
## One die in the hand or in a slot socket. Drawn, not textured: the face,
## focus brackets when selected or focused, a padlock when House-locked, a
## cross when spent on a reroll, and a "-1" bite marker against Snake eyes.
## Every state has a shape, so it reads in greyscale (SA-5).

## How far a held die lifts, and how thick its corners are, so held and
## focused differ in greyscale too (focus is 3 px corners, no lift).
const HELD_LIFT: float = 20.0

## Right-click or the controller's B button on this die.
signal secondary_pressed
## The player started dragging this die (mouse or touch).
signal drag_started

var die_id: int = -1
var value: int = 1:
	set(v):
		value = v
		queue_redraw()
var locked: bool = false:
	set(v):
		locked = v
		queue_redraw()
var discarded: bool = false:
	set(v):
		discarded = v
		queue_redraw()
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
## In a slot this turn: the hand keeps an outline so the row doesn't jump,
## and pressing it takes the die back.
var placed: bool = false:
	set(v):
		placed = v
		queue_redraw()
## The order number of the slot it's in, shown as "→3" on the outline.
var placed_order: int = 0
## Shows "-1 if unplaced" against Snake eyes.
var bite_marker: bool = false:
	set(v):
		bite_marker = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(BoardStyle.DIE_SIZE, BoardStyle.DIE_SIZE)
	focus_mode = Control.FOCUS_ALL
	flat = true
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


## Drag a free die onto a slot; it's the same move as click, then click.
func _get_drag_data(_at: Vector2) -> Variant:
	var payload: Variant = drag_payload()
	if payload == null:
		return null
	var ghost: DieView = DieView.new()
	ghost.value = value
	ghost.modulate.a = 0.85
	ghost.position = -ghost.custom_minimum_size / 2.0
	var holder: Control = Control.new()
	holder.add_child(ghost)
	set_drag_preview(holder)
	return payload


## What a drag of this die carries, or null when it can't be dragged.
## Starting one holds the die (drag_started).
func drag_payload() -> Variant:
	if placed or discarded or locked or disabled:
		return null
	drag_started.emit()
	return {"die": die_id}


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		secondary_pressed.emit()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		secondary_pressed.emit()
		accept_event()


func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i: int in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 3.0, 10.0)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2(8, 8), size - Vector2(16, 16))
	if placed:
		_draw_dashed_rect(rect, BoardStyle.DIM)
		var font: Font = get_theme_default_font()
		draw_string(font, rect.position + Vector2(rect.size.x * 0.22, rect.size.y * 0.62), "→%d" % placed_order,
			HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.NUMBER, BoardStyle.DIM)
		if has_focus() or is_hovered():
			BoardStyle.draw_brackets(self, rect, BoardStyle.INK, 3.0)
		return
	if selected:
		# A held die lifts off the felt, so held vs focused isn't color alone.
		draw_rect(rect, Color(0, 0, 0, 0.55))
		rect.position.y -= HELD_LIFT
	var face: Color = BoardStyle.DIE_FACE
	if discarded:
		face = BoardStyle.DIM
	BoardStyle.draw_die(self, rect, value, face)
	if locked:
		draw_rect(rect, Color(0, 0, 0, 0.45))
		BoardStyle.draw_padlock(self, rect)
	if discarded:
		draw_line(rect.position, rect.end, BoardStyle.DANGER, 6.0)
		draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), BoardStyle.DANGER, 6.0)
	if bite_marker:
		var font: Font = get_theme_default_font()
		draw_rect(Rect2(rect.end.x - 40, rect.position.y - 6, 46, 30), BoardStyle.DANGER)
		draw_string(font, Vector2(rect.end.x - 36, rect.position.y + 18), "-1", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BoardStyle.INK)
	if selected:
		BoardStyle.draw_brackets(self, rect, BoardStyle.GOLD, 10.0)
	elif has_focus() or is_hovered():
		BoardStyle.draw_brackets(self, rect, BoardStyle.INK, 3.0)
