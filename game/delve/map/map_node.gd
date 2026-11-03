class_name MapNode
extends Control
## One room on the map (Mara's review #3, #4, #10). It draws the room's
## outline and glyph by its state:
##   next     bright, with a solid ring (and a pulse unless reduce motion)
##   open     bright: still reachable later
##   current  gold: the room you're in
##   visited  gold, filled: where you've been
##   closed   dimmed to 40%: cut off
## Hover or focus asks the map to light the paths through it; a click or A
## on a "next" room picks it.

signal picked(col: int)
signal hovered(cell: Vector2i, on: bool)

const SIZE: float = 96.0

var cell: Vector2i = Vector2i.ZERO
var type: String = RunView.HIDDEN
var state: String = "open"
## 0-1, the pulse ring's phase on a "next" room (the map drives it).
var pulse: float = 0.0:
	set(v):
		pulse = v
		queue_redraw()
## On a path the player is looking at.
var lit: bool = false:
	set(v):
		lit = v
		queue_redraw()
## The room being pointed at: a jade ring to match the glowing paths, so a
## still frame shows which room it is (Mara, #29).
var pointed: bool = false:
	set(v):
		pointed = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit(cell, true))
	mouse_exited.connect(func() -> void: hovered.emit(cell, false))
	focus_entered.connect(func() -> void:
		hovered.emit(cell, true)
		queue_redraw())
	focus_exited.connect(func() -> void:
		hovered.emit(cell, false)
		queue_redraw())


func set_room(new_cell: Vector2i, new_type: String, new_state: String) -> void:
	cell = new_cell
	type = new_type
	state = new_state
	# Every room you might still walk through can take focus, so a
	# controller can read the paths too, and so can the room you're at
	# (where focus starts); other rooms behind you can't.
	focus_mode = Control.FOCUS_ALL if state in ["next", "open", "current"] else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if state == "next" else Control.CURSOR_ARROW
	tooltip_text = ""
	queue_redraw()


## Marks a room you see only thanks to Foresight with its giver's face
## chip (KP-2).
func set_foresight(villager_id: String, role: String) -> void:
	var chip: FaceChip = FaceChip.new()
	chip.villager_id = villager_id
	chip.role = role
	chip.custom_minimum_size = Vector2(34, 34)
	chip.size = Vector2(34, 34)
	chip.position = Vector2(SIZE - 22, -12)
	chip.tooltip_text = "Seen with Foresight · %s" % role
	add_child(chip)


func _gui_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if clicked or event.is_action_pressed("ui_accept"):
		accept_event()
		if state == "next":
			picked.emit(cell.y)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var color: Color = BoardStyle.INK
	match state:
		"visited", "current":
			color = BoardStyle.GOLD
		"closed":
			color = Color(BoardStyle.INK, 0.4)
	if state == "next":
		var c: Vector2 = rect.get_center()
		var r: float = SIZE / 2.0 + 10.0
		draw_arc(c, r, 0, TAU, 48, BoardStyle.GOLD, 3.0, true)
		if pulse > 0.0:
			draw_arc(c, r + 4.0 + pulse * 14.0, 0, TAU, 48, Color(BoardStyle.GOLD, 1.0 - pulse), 3.0, true)
	if pointed:
		draw_arc(rect.get_center(), SIZE / 2.0 + 18.0, 0, TAU, 48, BoardStyle.JADE, 6.0, true)
	var width: float = 6.0 if lit or state == "current" else 4.0
	MapGlyphs.draw_room(self, rect, type, color, width)
	if state == "visited":
		# Been here: a check mark under the room, so it isn't color alone.
		var y: float = SIZE + 10.0
		draw_polyline(PackedVector2Array([Vector2(SIZE * 0.4, y), Vector2(SIZE * 0.48, y + 8), Vector2(SIZE * 0.62, y - 8)]),
			BoardStyle.GOLD, 4.0, true)
	if has_focus():
		BoardStyle.draw_brackets(self, rect.grow(8), BoardStyle.INK)
