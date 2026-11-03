class_name KitMarks
extends RefCounted
## The small drawn pieces of the Kit tab (specs/bridge.md section 5): a
## gain or cost mark, a die's strip of faces drawn as the table draws them,
## and the kit strip above Go down. The town's fonts have no ▲ or ▼, so the
## marks are drawn, and a gain and a cost differ in shape, not only color.


## ▲ for a gain, ▼ for a cost.
class Mark:
	extends Control
	var cost: bool = false

	func _init(is_cost: bool = false) -> void:
		cost = is_cost
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: Vector2 = custom_minimum_size
		var top: float = 5.0
		var points: PackedVector2Array
		if cost:
			points = [Vector2(2, top), Vector2(s.x - 2, top), Vector2(s.x / 2.0, s.y - 3)]
		else:
			points = [Vector2(s.x / 2.0, top - 2), Vector2(s.x - 2, s.y - 3), Vector2(2, s.y - 3)]
		draw_colored_polygon(points, TownStyle.VERMILION if cost else TownStyle.HAPPY)


## One die as a strip of its faces, drawn as the table draws them (two-
## halves: the dice look the same in both halves). A face that differs from
## the loadout's die is outlined.
class FaceStrip:
	extends Control
	const CELL: float = 40.0
	const GAP: float = 6.0
	var faces: Array[int] = []
	var changed: Array[bool] = []

	func _init(die_faces: Array[int] = [], die_changed: Array[bool] = []) -> void:
		faces = die_faces
		changed = die_changed
		custom_minimum_size = Vector2(faces.size() * (CELL + GAP), CELL + 6.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i: int in faces.size():
			var rect: Rect2 = Rect2(Vector2(i * (CELL + GAP) + 3.0, 3.0), Vector2(CELL, CELL))
			BoardStyle.draw_die(self, rect, faces[i], BoardStyle.DIE_FACE, BoardStyle.DIE_PIP)
			draw_rect(rect, TownStyle.LOT_LINE, false, 1.0)
			if i < changed.size() and changed[i]:
				draw_rect(rect.grow(2.0), TownStyle.VERMILION, false, 3.0)


## The read-only strip above Go down: a mini die per kit die, with a dot on
## one that's changed or added. Pressing it opens the Kit tab.
class Strip:
	extends Button
	const MINI: float = 30.0
	const GAP: float = 8.0
	## One {"top", "changed"} per die: the face it shows and its dot.
	var dice: Array[Dictionary] = []

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(0, MINI + 16.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func show_kit(data: GameData, kit: Kit) -> void:
		dice.clear()
		if kit != null:
			for row: Dictionary in KitSheet.dice_rows(data, kit):
				dice.append({"top": (row["faces"] as Array).max(), "changed": KitSheet.is_changed(row)})
			tooltip_text = KitSheet.summary(data, kit)
		queue_redraw()

	func _draw() -> void:
		var width: float = dice.size() * (MINI + GAP) - GAP
		var x: float = size.x - width
		var y: float = (size.y - MINI) / 2.0
		var font: Font = TownStyle.theme().default_font
		var label: String = "Kit"
		var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TownStyle.SMALL)
		draw_string(font, Vector2(x - label_size.x - 14.0, y + MINI * 0.75), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TownStyle.SMALL, TownStyle.INK)
		for d: Dictionary in dice:
			var rect: Rect2 = Rect2(Vector2(x, y), Vector2(MINI, MINI))
			BoardStyle.draw_die(self, rect, int(d["top"]), BoardStyle.DIE_FACE, BoardStyle.DIE_PIP)
			draw_rect(rect, TownStyle.LOT_LINE, false, 1.0)
			if d["changed"]:
				draw_circle(rect.position + Vector2(MINI, 0), 6.0, TownStyle.VERMILION)
				draw_arc(rect.position + Vector2(MINI, 0), 6.0, 0, TAU, 16, TownStyle.WASHI, 1.5)
			x += MINI + GAP
		if has_focus() or is_hovered():
			draw_rect(Rect2(Vector2(size.x - width - 6.0, y - 6.0), Vector2(width + 12.0, MINI + 12.0)),
				TownStyle.INK, false, 2.0)
