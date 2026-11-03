class_name DieView
extends Button
## One die in the hand or in a slot socket. Drawn, not textured: the face,
## focus brackets when selected or focused, a padlock when House-locked, a
## cross when spent on a reroll, and a "-1" bite marker against Snake eyes.
## Every state has a shape, so it reads in greyscale (SA-5).

## Right-click or the controller's B button on this die.
signal secondary_pressed

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


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		secondary_pressed.emit()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		secondary_pressed.emit()
		accept_event()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2(8, 8), size - Vector2(16, 16))
	if placed:
		draw_rect(rect, BoardStyle.DIM, false, 3.0)
		if has_focus() or is_hovered():
			BoardStyle.draw_brackets(self, rect, BoardStyle.INK, 3.0)
		return
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
		BoardStyle.draw_brackets(self, rect, BoardStyle.GOLD, 6.0)
	elif has_focus() or is_hovered():
		BoardStyle.draw_brackets(self, rect, BoardStyle.INK, 3.0)
