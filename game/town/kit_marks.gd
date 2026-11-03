class_name KitMarks
extends RefCounted
## The small drawn pieces of the Kit tab (specs/bridge.md section 5): a
## gain or cost mark, a die's strip of faces drawn as the table draws them,
## and the kit strip above Go down. The town's fonts have no ▲ or ▼, so the
## marks are drawn, and a gain and a cost differ in shape, not only color.
## Red stays inside the hanko seal (Mara's #42 and #51 reviews): a cost is
## the rain cloud's plum, a change is ink.


## ▲ for a gain (teal), ▼ for a cost (plum).
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
		draw_colored_polygon(points, TownStyle.UNHAPPY if cost else TownStyle.HAPPY)


## One die as a strip of its faces, drawn as the table draws them (two-
## halves: the dice look the same in both halves). A face that differs from
## the loadout's die gets a heavy ink outline with a notched corner.
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
				var edge: Rect2 = rect.grow(2.0)
				draw_rect(edge, TownStyle.INK, false, 3.0)
				# The notch sits where the table's kit dice carry theirs.
				draw_colored_polygon(PackedVector2Array([edge.end - Vector2(11, 0), edge.end, edge.end - Vector2(0, 11)]),
					TownStyle.INK)


## The read-only strip above Go down: a blank mini die per kit die (a
## face would read as a roll already made; Mara's #51 review), a d4 smaller,
## an ink dot on one that's changed or added, then the perk count. Pressing
## it opens the Kit tab. While a shop waits on its stamp, the strip shows
## the kit it would make, the new die hatched and the count "4 → 5 perks",
## as the ledger previews a spend.
class Strip:
	extends Button
	const MINI: float = 30.0
	const GAP: float = 8.0
	## One {"small", "changed", "new"} per die.
	var dice: Array[Dictionary] = []
	var perks_text: String = ""

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(0, MINI + 16.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	## `after`, when given, is the kit a pending stamp would make.
	func show_kit(data: GameData, kit: Kit, after: Kit = null) -> void:
		dice.clear()
		perks_text = ""
		if kit != null:
			var now: Array[Dictionary] = KitSheet.dice_rows(data, kit)
			var shown: Array[Dictionary] = now if after == null else KitSheet.dice_rows(data, after)
			for i: int in shown.size():
				var row: Dictionary = shown[i]
				var is_new: bool = i >= now.size() or now[i]["faces"] != row["faces"]
				dice.append({"small": (row["faces"] as Array).size() < 6, "changed": KitSheet.is_changed(row), "new": is_new})
			var count: int = kit.perks.size()
			perks_text = "%d perk%s" % [count, "" if count == 1 else "s"]
			if after != null and after.perks.size() != count:
				perks_text = "%d → %d perks" % [count, after.perks.size()]
			tooltip_text = KitSheet.summary(data, kit if after == null else after)
		queue_redraw()

	func _draw() -> void:
		var font: Font = TownStyle.theme().default_font
		var tail: String = "· " + perks_text
		var tail_width: float = font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, TownStyle.SMALL).x
		var width: float = dice.size() * (MINI + GAP) - GAP
		var right: float = size.x - tail_width - 10.0
		var x: float = right - width
		var y: float = (size.y - MINI) / 2.0
		var baseline: float = y + MINI * 0.75
		var label: String = "Kit"
		var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TownStyle.SMALL)
		draw_string(font, Vector2(x - label_size.x - 14.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TownStyle.SMALL, TownStyle.INK)
		for d: Dictionary in dice:
			var side: float = MINI * (0.72 if d["small"] else 1.0)
			var rect: Rect2 = Rect2(Vector2(x + (MINI - side) / 2.0, y + MINI - side), Vector2(side, side))
			BoardStyle.draw_die(self, rect, 0, BoardStyle.DIE_FACE, BoardStyle.DIE_PIP)
			draw_rect(rect, TownStyle.LOT_LINE, false, 1.0)
			if d["new"]:
				# Hatched like a shell that would be spent.
				for step: int in range(1, 5):
					var t: float = step * side / 5.0
					draw_line(rect.position + Vector2(t, 0), rect.position + Vector2(0, t), TownStyle.SPENT, 1.5)
					draw_line(rect.end - Vector2(t, 0), rect.end - Vector2(0, t), TownStyle.SPENT, 1.5)
			if d["changed"]:
				draw_circle(rect.position + Vector2(side, 0), 5.0, TownStyle.INK)
				draw_arc(rect.position + Vector2(side, 0), 5.0, 0, TAU, 16, TownStyle.WASHI, 1.5)
			x += MINI + GAP
		draw_string(font, Vector2(right + 10.0, baseline), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, TownStyle.SMALL,
			TownStyle.INK)
		if has_focus() or is_hovered():
			var left: float = right - width - label_size.x - 20.0
			draw_rect(Rect2(Vector2(left, y - 6.0), Vector2(size.x - left, MINI + 12.0)), TownStyle.INK, false, 2.0)


## A soft fade over a scrolling sheet's bottom edge while there's more
## below (Mara's #51 review, for the Deck).
class Fade:
	extends Control
	const HEIGHT: float = 36.0
	var scroll: ScrollContainer

	func _init(over: ScrollContainer) -> void:
		scroll = over
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: queue_redraw())
		scroll.get_v_scroll_bar().changed.connect(queue_redraw)

	func more_below() -> bool:
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		return bar.max_value - bar.page > 1.0 and bar.value < bar.max_value - bar.page - 1.0

	func _draw() -> void:
		if not more_below():
			return
		var top: float = size.y - HEIGHT
		var steps: int = 12
		for i: int in steps:
			var color: Color = TownStyle.WASHI
			color.a = float(i + 1) / steps
			draw_rect(Rect2(Vector2(0, top + i * HEIGHT / steps), Vector2(size.x - 12.0, HEIGHT / steps + 0.5)), color)
