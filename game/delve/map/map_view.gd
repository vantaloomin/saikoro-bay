class_name MapView
extends Control
## The floor map (specs/delve-map.md section 8, Mara's review #3-#5, #10).
## It shows one floor top to bottom from a RunView, so it can't show a room
## the player hasn't seen: the rooms, the links, the path walked so far, and
## at the bottom the landing (a band with a torii) or Koban's vault.
##
## Hover or focus on a room lights every path through it and says what
## those paths hold. Picking a "next" room emits room_chosen. Input is
## ignored for GUARD_MS after the map appears, so a press meant for the
## screen before can't pick a room.

signal room_chosen(col: int)

const GUARD_MS: int = 400
const MAP_WIDTH: float = 900.0
const COL_GAP: float = 270.0
const ENTRY_Y: float = 70.0
const ROW_Y0: float = 210.0
const ROW_GAP: float = 210.0
const BAND_HEIGHT: float = 110.0
const VAULT_SIZE: float = 132.0
const LEGEND: Array[Array] = [
	[DelveMap.FIGHT, "Fight"],
	[DelveMap.ELITE, "Elite fight"],
	[DelveMap.REST, "Safe room: rest, treasure or rescue"],
	[RunView.HIDDEN, "Not seen yet"],
]


## The outline key, drawn with the map's own shapes.
class Legend:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(440, LEGEND.size() * 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font: Font = get_theme_default_font()
		for i: int in LEGEND.size():
			var y: float = i * 64.0
			MapGlyphs.draw_room(self, Rect2(0, y, 52, 52), LEGEND[i][0] as String, BoardStyle.INK, 3.0)
			draw_string(font, Vector2(72, y + 36), LEGEND[i][1] as String, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.SMALL, BoardStyle.INK)


var data: GameData
var view: RunView

var _rows: Array = []
var _paths: Array[Array] = []
var _nodes: Dictionary[Vector2i, MapNode] = {}
var _lit_cells: Dictionary = {}
var _lit_links: Dictionary = {}
var _guard_until: int = 0
var _pulse_time: float = 0.0
var _last_floor: bool = false
var _prize: String = ""

var _title: Label
var _room_name: Label
var _summary: Label
var _notes: Label
var _canvas: Control


func setup(game_data: GameData) -> void:
	data = game_data


func _ready() -> void:
	theme = BoardStyle.theme()
	_build()


## Shows `run_view`'s floor and starts the input guard.
func show_view(run_view: RunView) -> void:
	view = run_view
	_rows = view.rows()
	_paths = MapPaths.all_paths(_rows)
	_last_floor = view.floor_index() == view.floor_count() - 1
	_prize = ""
	var prize: Dictionary = view.vault_prize()
	if prize.has("landmark"):
		_prize = data.row("landmarks", str(prize["landmark"]))["name"]
	_title.text = "Floor %d of %d" % [view.floor_index() + 1, view.floor_count()]
	_set_lit(Vector2i(-1, -1))
	for n: MapNode in _nodes.values():
		n.queue_free()
	_nodes.clear()
	for r: int in _rows.size():
		for room: Dictionary in _rows[r] as Array:
			var cell: Vector2i = Vector2i(r, room["col"] as int)
			var n: MapNode = MapNode.new()
			n.set_room(cell, room["type"] as String, room["state"] as String)
			n.position = node_center(cell) - n.size / 2.0
			n.picked.connect(_on_picked)
			n.hovered.connect(_on_hovered)
			_canvas.add_child(n)
			_nodes[cell] = n
	_guard_until = Time.get_ticks_msec() + GUARD_MS
	var first: MapNode = _first_next()
	if first != null:
		first.grab_focus()
	_canvas.queue_redraw()


## What the rooms played since the last stop gave (the bot plays those
## rooms until their boards exist).
func show_notes(lines: PackedStringArray) -> void:
	_notes.text = "\n".join(lines)
	_notes.visible = not lines.is_empty()


## Where a room sits on the map canvas.
func node_center(cell: Vector2i) -> Vector2:
	var width: int = (_rows[cell.x] as Array).size()
	var x: float = MAP_WIDTH / 2.0 + (cell.y - (width - 1) / 2.0) * COL_GAP
	return Vector2(x, ROW_Y0 + cell.x * ROW_GAP)


func _first_next() -> MapNode:
	var keys: Array = _nodes.keys()
	keys.sort()
	for cell: Vector2i in keys:
		if _nodes[cell].state == "next":
			return _nodes[cell]
	return null


func _process(delta: float) -> void:
	if Settings.reduce_motion:
		if _pulse_time != 0.0:
			_pulse_time = 0.0
			_set_pulse(0.0)
		return
	_pulse_time = fmod(_pulse_time + delta, 1.4)
	_set_pulse(_pulse_time / 1.4)


func _set_pulse(phase: float) -> void:
	for n: MapNode in _nodes.values():
		if n.state == "next":
			n.pulse = phase


func _on_picked(col: int) -> void:
	if Time.get_ticks_msec() < _guard_until:
		return
	room_chosen.emit(col)


func _on_hovered(cell: Vector2i, on: bool) -> void:
	_set_lit(cell if on else Vector2i(-1, -1))


func _set_lit(cell: Vector2i) -> void:
	_lit_cells = {}
	_lit_links = {}
	if cell.x < 0 or not _nodes.has(cell):
		_room_name.text = ""
		_summary.text = "Pick a room in the next row. Point at any room to see the paths through it."
	else:
		var n: MapNode = _nodes[cell]
		_room_name.text = room_name(n.type)
		match n.state:
			"next", "open":
				var through: Array[Array] = MapPaths.through(_paths, cell)
				_lit_cells = MapPaths.cells(through)
				_lit_links = MapPaths.links(through)
				_summary.text = "Through here: %s" % MapPaths.summary(_rows, through)
			"closed":
				_summary.text = "Out of reach now."
			_:
				_summary.text = "You've been here."
	for c: Vector2i in _nodes:
		_nodes[c].lit = _lit_cells.has(c)
	if _canvas != null:
		_canvas.queue_redraw()


func room_name(type: String) -> String:
	if type == RunView.HIDDEN or not data.has_row("rooms", type):
		return "Not seen yet"
	return data.row("rooms", type)["name"]


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 24)
	left.position = Vector2(40, 40)
	left.custom_minimum_size = Vector2(440, 0)
	add_child(left)
	_title = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.GOLD)
	_title.add_theme_font_override("font", BoardStyle.title_font())
	left.add_child(_title)
	left.add_child(Legend.new())

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.custom_minimum_size = Vector2(MAP_WIDTH, 1000)
	_canvas.position = Vector2((1920.0 - MAP_WIDTH) / 2.0, 0)
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)

	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.position = Vector2(1920.0 - 40 - 440, 40)
	right.custom_minimum_size = Vector2(440, 0)
	add_child(right)
	_room_name = BoardStyle.label("", BoardStyle.NUMBER)
	right.add_child(_room_name)
	_summary = BoardStyle.label("", BoardStyle.BODY)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(440, 0)
	right.add_child(_summary)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	right.add_child(gap)
	_notes = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.custom_minimum_size = Vector2(440, 0)
	_notes.visible = false
	right.add_child(_notes)


func _draw_canvas() -> void:
	if _rows.is_empty():
		return
	var last: int = _rows.size() - 1
	var bottom_y: float = ROW_Y0 + _rows.size() * ROW_GAP - 40.0
	var entry: Vector2 = Vector2(MAP_WIDTH / 2.0, ENTRY_Y)
	# The way in: a short bar the floor's first row hangs from.
	_canvas.draw_rect(Rect2(entry.x - 60, entry.y - 6, 120, 12), BoardStyle.DIM)
	for room: Dictionary in _rows[0] as Array:
		var to: Vector2i = Vector2i(0, room["col"] as int)
		_draw_link(entry, node_center(to), _link_style(Vector2i(-1, -1), to))
	for r: int in last:
		for room: Dictionary in _rows[r] as Array:
			var from: Vector2i = Vector2i(r, room["col"] as int)
			for to_col: Variant in room["links"] as Array:
				var to: Vector2i = Vector2i(r + 1, int(to_col))
				_draw_link(node_center(from), node_center(to), _link_style(from, to))
	var end: Vector2 = Vector2(MAP_WIDTH / 2.0, bottom_y + (VAULT_SIZE / 2.0 if _last_floor else 0.0))
	for room: Dictionary in _rows[last] as Array:
		var from: Vector2i = Vector2i(last, room["col"] as int)
		var target: Vector2 = Vector2(node_center(from).x, bottom_y) if not _last_floor else end
		_draw_link(node_center(from), target, _link_style(from, Vector2i(-1, -1)))
	if _last_floor:
		var rect: Rect2 = Rect2(end - Vector2(VAULT_SIZE, VAULT_SIZE) / 2.0, Vector2(VAULT_SIZE, VAULT_SIZE))
		MapGlyphs.draw_room(_canvas, rect, DelveMap.VAULT, BoardStyle.GOLD, 5.0)
		var caption: String = "Koban's vault" + (" · the %s" % _prize if not _prize.is_empty() else "")
		_centered_text(caption, Vector2(end.x, rect.end.y + 40), BoardStyle.BODY, BoardStyle.GOLD)
	else:
		var band: Rect2 = Rect2(0, bottom_y, MAP_WIDTH, BAND_HEIGHT)
		_canvas.draw_rect(band, BoardStyle.FELT)
		_canvas.draw_rect(band, BoardStyle.GOLD, false, 2.0)
		MapGlyphs.draw_torii(_canvas, Rect2(band.get_center() - Vector2(50, 50), Vector2(100, 100)), BoardStyle.GOLD)
		var font: Font = BoardStyle.strong_font()
		_canvas.draw_string(font, Vector2(24, band.get_center().y + 10), "Landing", HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY, BoardStyle.INK)
		_canvas.draw_string(font, Vector2(MAP_WIDTH - 260, band.get_center().y + 10), "A safe way up", HORIZONTAL_ALIGNMENT_RIGHT, 236, BoardStyle.BODY, BoardStyle.INK)


## [color, width] for the link between two rooms; (-1, -1) stands for the
## way in (as `from`) or the floor's end (as `to`).
func _link_style(from: Vector2i, to: Vector2i) -> Array:
	var from_state: String = "visited" if from.x < 0 else _state(from)
	var to_state: String = "open" if to.x < 0 else _state(to)
	var walked: Array[String] = ["visited", "current"]
	if from_state in walked and to_state in walked:
		return [BoardStyle.GOLD, 7.0]
	if from.x >= 0 and to.x >= 0 and _lit_links.has([from, to]):
		return [BoardStyle.INK, 7.0]
	if to.x < 0 and _lit_cells.has(from):
		return [BoardStyle.INK, 7.0]
	if from_state == "closed" or to_state == "closed":
		return [Color(BoardStyle.DIM, 0.35), 3.0]
	if to_state == "next" and (from.x < 0 or from_state in walked):
		return [BoardStyle.INK, 5.0]
	return [BoardStyle.DIM, 3.0]


func _state(cell: Vector2i) -> String:
	return _nodes[cell].state if _nodes.has(cell) else "open"


func _draw_link(a: Vector2, b: Vector2, style: Array) -> void:
	_canvas.draw_line(a, b, style[0] as Color, style[1] as float, true)


func _centered_text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font: Font = BoardStyle.strong_font()
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_canvas.draw_string(font, Vector2(at.x - w / 2.0, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
