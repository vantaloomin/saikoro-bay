class_name DieView
extends Button
## One die in the hand or in a slot socket. Drawn, not textured: the face,
## focus brackets when selected or focused, a padlock when House-locked, a
## cross when spent on a reroll, and a "-1" bite marker against Snake eyes.
## Every state has a shape, so it reads in greyscale (SA-5).

## How far a held die lifts, and how thick its corners are, so held and
## focused differ in greyscale too (focus is 3 px corners, no lift).
const HELD_LIFT: float = 20.0
## The face range's size, under a kit die (outside its own rect).
const RANGE_FONT: int = 22

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
## A die the town changed or added (the kit): a notched corner, the Kit
## tab's mark, so the Weighted die and the d4 read as yours on the table
## too (specs/bridge.md section 5). Its name is the tooltip.
var kit_mark: bool = false:
	set(v):
		kit_mark = v
		queue_redraw()
## Shows "-1 if unplaced" against Snake eyes.
var bite_marker: bool = false:
	set(v):
		bite_marker = v
		queue_redraw()


## Under a kit die, always: its face range, "2–5" (Mara's #52 review: the
## notch says "different", the range says how). "" on a standard die.
var kit_range: String = ""
## What the board's result area says while a kit die is focused or held,
## since a pad has no hover: "Weighted die · Net shed · no 1s or 6s".
var kit_note: String = ""


## Marks a die whose type isn't one of the loadout's, and names it.
func show_type(data: GameData, type_id: String) -> void:
	var loadout: Array = data.row("loadouts", Kit.LOADOUT).get("dice", []) as Array
	kit_mark = not loadout.has(type_id)
	kit_range = ""
	kit_note = ""
	tooltip_text = ""
	if not kit_mark or not data.has_row("dice", type_id):
		return
	var faces: Array = data.row("dice", type_id)["faces"] as Array
	kit_range = "%d–%d" % [int(faces.min()), int(faces.max())]
	kit_note = note_for(data, type_id)
	tooltip_text = kit_note


## The note of the held kit die, else the focused one, else "": what a
## board's second line says in place of its usual detail.
static func held_note(views: Array[DieView]) -> String:
	for view: DieView in views:
		if view.selected and not view.kit_note.is_empty():
			return view.kit_note
	for view: DieView in views:
		if view.has_focus() and not view.kit_note.is_empty():
			return view.kit_note
	return ""


## "Weighted die · Net shed · no 1s or 6s", or "Four-sided die · Boat
## shed · added": the die, who gives it, and what changed.
static func note_for(data: GameData, type_id: String) -> String:
	var parts: PackedStringArray = [str(data.row("dice", type_id).get("name", type_id))]
	for perk_id: String in data.ids("perks"):
		var perk: Dictionary = data.row("perks", perk_id)
		if str(perk.get("die", "")) != type_id:
			continue
		for table: String in ["buildings", "villagers"]:
			for id: String in data.ids(table):
				if str(data.row(table, id).get("perk", "")) == perk_id:
					parts.append(KitSheet.source_name(data, id))
		if perk["kind"] == "add_die":
			parts.append("added")
		else:
			var plain: Array = data.row("dice", str((data.row("loadouts", Kit.LOADOUT)["dice"] as Array)[0]))["faces"] as Array
			var faces: Array[int] = []
			faces.assign(data.row("dice", type_id)["faces"] as Array)
			parts.append(KitSheet.change_text(plain, faces))
	return " · ".join(parts)


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
	# Above the cursor, so the slot footer and ruler caret stay visible.
	ghost.position = Vector2(-ghost.custom_minimum_size.x / 2.0, -ghost.custom_minimum_size.y - 24)
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
	if kit_mark:
		var notch: float = rect.size.x * 0.14
		draw_colored_polygon(PackedVector2Array([rect.end - Vector2(notch, 0), rect.end, rect.end - Vector2(0, notch)]),
			BoardStyle.DIE_PIP)
	if locked:
		# Lightly greyed so the pips still show what it is; the padlock sits
		# in a corner badge, like the bite tag, instead of over the pips.
		draw_rect(rect, Color(0, 0, 0, 0.25))
		var badge: Rect2 = Rect2(rect.position - Vector2(14, 14), Vector2(36, 36))
		draw_rect(badge, BoardStyle.LACQUER)
		draw_rect(badge, BoardStyle.DANGER, false, 2.0)
		BoardStyle.draw_padlock(self, badge.grow(4))
	if discarded:
		# Dark under red, so the cross reads in greyscale too.
		for pass_color: Color in [BoardStyle.LACQUER, BoardStyle.DANGER]:
			var width: float = 12.0 if pass_color == BoardStyle.LACQUER else 6.0
			draw_line(rect.position, rect.end, pass_color, width)
			draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), pass_color, width)
	if bite_marker:
		var font: Font = get_theme_default_font()
		draw_rect(Rect2(rect.end.x - 40, rect.position.y - 6, 46, 30), BoardStyle.DANGER)
		draw_string(font, Vector2(rect.end.x - 36, rect.position.y + 18), "-1", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BoardStyle.LACQUER)
	if not kit_range.is_empty() and not placed:
		var font: Font = get_theme_default_font()
		var width: float = font.get_string_size(kit_range, HORIZONTAL_ALIGNMENT_LEFT, -1, RANGE_FONT).x
		draw_string(font, Vector2((size.x - width) / 2.0, size.y + RANGE_FONT + 2), kit_range,
			HORIZONTAL_ALIGNMENT_LEFT, -1, RANGE_FONT, BoardStyle.INK)
	if selected:
		BoardStyle.draw_brackets(self, rect, BoardStyle.GOLD, 10.0)
	elif has_focus() or is_hovered():
		BoardStyle.draw_brackets(self, rect, BoardStyle.INK, 3.0)
