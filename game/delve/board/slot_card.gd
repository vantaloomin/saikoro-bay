class_name SlotCard
extends Button
## One action card slot. Shows its order number, name, rule text, a pip
## ruler (six cells for faces 1-6, the faces it accepts filled), its die
## sockets, and the preview for the die being held over it (DR-3).

## Right-click or B on the card: take back its last die.
signal secondary_pressed
## A die was dragged onto this slot. Every die drop is taken, so the board
## can explain a refusal instead of the drop silently doing nothing.
signal die_dropped(die_id: int)

var slot_id: String = ""
var order: int = 1
var title: String = ""
var rule_text: String = ""
## Faces 1-6 this slot accepts. A pair slot shows two frames joined by "=".
var accepted: Array[bool] = [true, true, true, true, true, true]
var is_pair: bool = false
var sockets: int = 1
## Values of the dice placed here, in order.
var placed_values: Array[int] = []
## Preview line for the held die, e.g. "8 damage (4 through guard)".
var preview_text: String = ""
## How the footer reads: "ok", "wait" (allowed, needs more dice) or "error".
var preview_tone: String = "ok"
## The value of the die being held (0 = none): a caret marks it on the ruler.
var held_value: int = 0
## Whether the held die fits here: 0 nothing held, 1 fits, -1 refused.
var held_fit: int = 0
## Briefly true after an invalid drop: the ruler pulses for a wrong value,
## the sockets for a full slot.
var pulsing: bool = false
var pulsing_sockets: bool = false
## A persistent lock that has opened (a rescue cage lock): it stays open
## and takes no dice, so its sockets show OPEN instead.
var opened: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(400, 388)
	focus_mode = Control.FOCUS_ALL
	flat = true
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("die")


func _drop_data(_at: Vector2, data: Variant) -> void:
	die_dropped.emit((data as Dictionary)["die"] as int)


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		secondary_pressed.emit()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		secondary_pressed.emit()
		accept_event()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, BoardStyle.LACQUER)
	var border: Color = BoardStyle.GOLD if has_focus() or is_hovered() else BoardStyle.DIM
	var border_width: float = 2.0
	if held_fit == 1:
		border = BoardStyle.INK
		border_width = 5.0
	elif held_fit == -1:
		border = BoardStyle.DIM.darkened(0.5)
	draw_rect(r, border, false, border_width)
	# Order badge, so "resolve top to bottom" is visible (Mara 10).
	draw_rect(Rect2(12, 12, 40, 40), BoardStyle.GOLD)
	draw_string(font, Vector2(23, 42), str(order), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY, BoardStyle.LACQUER)
	draw_string(font, Vector2(64, 42), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 76, BoardStyle.BODY, BoardStyle.INK)
	draw_multiline_string(font, Vector2(16, 82), rule_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, BoardStyle.SMALL, 2, BoardStyle.DIM)

	# Pip ruler: six cells, accepted faces filled.
	var cell: float = minf(BoardStyle.RULER_CELL, (size.x - 32) / 6.0 - 4)
	var ruler_y: float = 140
	var ruler_x: float = (size.x - (cell + 4) * 6) / 2.0
	for face: int in 6:
		var cr: Rect2 = Rect2(ruler_x + face * (cell + 4), ruler_y, cell, cell)
		var on: bool = accepted[face]
		var edge: Color = BoardStyle.DANGER if pulsing else BoardStyle.INK
		if on:
			BoardStyle.draw_die(self, cr, face + 1)
		else:
			draw_rect(cr, edge, false, 2.0)
			draw_string(font, cr.position + Vector2(cell * 0.36, cell * 0.68), str(face + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.SMALL, BoardStyle.DIM)
	if pulsing:
		draw_rect(Rect2(ruler_x - 6, ruler_y - 6, (cell + 4) * 6 + 8, cell + 12), BoardStyle.DANGER, false, 3.0)
	if held_value >= 1 and held_value <= 6:
		var cx: float = ruler_x + (held_value - 1) * (cell + 4) + cell / 2.0
		var cy: float = ruler_y + cell + 6
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(cx - 9, cy + 12), Vector2(cx + 9, cy + 12)]), BoardStyle.INK)

	# A slot the held die can't go in dims its chrome only. Placed dice and
	# the footer stay bright, so a placed die never reads as locked.
	if held_fit == -1:
		draw_rect(r, Color(0, 0, 0, 0.35))

	# Sockets.
	var socket: float = 88
	var gap: float = 44 if is_pair else 0
	var total: float = socket * sockets + gap * (sockets - 1)
	var sx: float = (size.x - total) / 2.0
	var sy: float = 212
	if opened:
		var band: Rect2 = Rect2(sx - 8, sy, total + 16, socket)
		draw_rect(band, BoardStyle.FELT)
		draw_rect(band, BoardStyle.JADE, false, 5.0)
		var word: String = "OPEN"
		var w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.NUMBER).x
		draw_string(font, Vector2(band.get_center().x - w / 2.0, band.get_center().y + BoardStyle.NUMBER * 0.36), word,
			HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.NUMBER, BoardStyle.JADE)
	for i: int in (0 if opened else sockets):
		var sr: Rect2 = Rect2(sx + i * (socket + gap), sy, socket, socket)
		if i < placed_values.size():
			BoardStyle.draw_die(self, sr.grow(-6), placed_values[i])
		else:
			draw_rect(sr, BoardStyle.DIM, false, 3.0)
		if pulsing_sockets:
			draw_rect(sr.grow(4), BoardStyle.DANGER, false, 4.0)
		if is_pair and i < sockets - 1:
			draw_string(font, Vector2(sr.end.x + 8, sy + socket * 0.62), "=", HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.NUMBER, BoardStyle.INK)

	if not preview_text.is_empty():
		var tone: Color = BoardStyle.JADE
		var mark: String = ""
		match preview_tone:
			"wait":
				tone = BoardStyle.AMBER
				mark = "… "
			"error":
				tone = BoardStyle.DANGER
				mark = "× "
		# Two lines at most, so a long preview wraps instead of clipping.
		var text: String = mark + preview_text
		var width: float = size.x - 32
		var one_line: bool = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.SMALL).x <= width
		var top: float = size.y - (20 if one_line else 50)
		draw_multiline_string(font, Vector2(16, top), text, HORIZONTAL_ALIGNMENT_LEFT, width,
			BoardStyle.SMALL, 2, tone)
