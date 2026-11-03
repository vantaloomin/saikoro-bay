class_name CameraSpike
extends Node2D
## Camera spike runner (vertical slice plan section 10, Mara's test): the
## same three tasks in a top-down town and an isometric one, counting
## misclicks and time, then three preference questions. Open
## tools/camera_spike/camera_spike.tscn in the editor and press F6.
##
## Two layouts cross the two views (Mara's #35 review): tester 1 gets order
## 1, tester 2 order 2, and so on, so each view meets each layout equally
## often and nobody sees a layout twice. Mouse or a controller's left stick
## and A button.
##
## Greybox in town colors (two-halves spec: sand, sea teal, vermilion).
## Placeholder throughout; nothing here ships.

const VIEW_NAMES: Dictionary[SpikeTown.View, String] = {
	SpikeTown.View.TOP_DOWN: "Straight down", SpikeTown.View.ISOMETRIC: "At an angle",
}
## [view, layout] for the first and second half of each order.
const ORDERS: Array = [
	[Vector2i(SpikeTown.View.TOP_DOWN, 0), Vector2i(SpikeTown.View.ISOMETRIC, 1)],
	[Vector2i(SpikeTown.View.ISOMETRIC, 0), Vector2i(SpikeTown.View.TOP_DOWN, 1)],
	[Vector2i(SpikeTown.View.TOP_DOWN, 1), Vector2i(SpikeTown.View.ISOMETRIC, 0)],
	[Vector2i(SpikeTown.View.ISOMETRIC, 1), Vector2i(SpikeTown.View.TOP_DOWN, 0)],
]
## Asked after both halves. Speed favors top-down, so feel gets a say too.
const QUESTIONS: Array[String] = [
	"Which view would you rather look at for an hour?",
	"Which one felt more like a town?",
	"Which was easier to use?",
]
const ANSWERS: Array[String] = ["Straight down", "At an angle", "No difference"]
const CURSOR_SPEED: float = 900.0
const STICK_DEADZONE: float = 0.2
const TASKS: Array[SpikeTown.Task] = [SpikeTown.Task.EMPTY_LOT, SpikeTown.Task.UNHAPPY, SpikeTown.Task.PLACE]
const SCREEN: Vector2 = Vector2(1920, 1080)
const BANNER_HEIGHT: float = 150.0

const SKY: Color = Color(0.96, 0.93, 0.86)
const SAND: Color = Color(0.93, 0.84, 0.66)
const STONE: Color = Color(0.74, 0.72, 0.68)
const SEA: Color = Color(0.29, 0.62, 0.64)
const INK: Color = Color(0.2, 0.17, 0.15)
const LOT_LINE: Color = Color(0.55, 0.42, 0.28)
const ROOF: Dictionary[String, Color] = {
	"home": Color(0.96, 0.95, 0.92), "shop": Color(0.83, 0.86, 0.9), "landmark": Color(0.88, 0.36, 0.27),
}
const HAPPY: Color = Color(0.25, 0.6, 0.5)
## Plum: used nowhere else on the map, so no landmark reads as unhappy.
const UNHAPPY: Color = Color(0.47, 0.33, 0.66)
const CLOUD: Color = Color(0.42, 0.46, 0.56)
## Buildings between the cursor and the ground while carrying.
const FADED: float = 0.3
const MISS: Color = Color(0.86, 0.33, 0.24)

var town: SpikeTown
var _ground: TileMapLayer
var _font: Font = ThemeDB.fallback_font
var _order: int = 0
## Testers so far, which picks the next order.
var _testers: int = 0
var _run: int = 0
var _task_index: int = 0
var _task_started_ms: int = 0
var _misclicks: int = 0
var _results: Array[Dictionary] = []
var _answers: Dictionary[String, String] = {}
var _question: int = 0
## "mouse" or "controller", whichever moved last.
var _input_kind: String = "mouse"
var _cursor: Vector2 = SCREEN / 2.0
var _hover: Vector2i = SpikeTown.NO_CELL
var _miss_at: Vector2 = Vector2.ZERO
var _miss_ms: int = -10000

var _ui: CanvasLayer
var _banner: PanelContainer
var _view_label: Label
var _task_label: Label
var _start_panel: PanelContainer
var _intro_panel: PanelContainer
var _between_panel: PanelContainer
var _question_panel: PanelContainer
var _question_label: Label
var _view_answers: Array[Button] = []
var _order_label: Label
var _results_panel: PanelContainer
var _results_label: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY)
	_build_ui()
	_show_only(_start_panel)


# --- Flow -----------------------------------------------------------------------------

## The organizer picks an order; the tester then sees a neutral intro.
func start(order: int) -> void:
	_order = order
	_results.clear()
	_answers.clear()
	_show_only(_intro_panel)


## The tester presses Start.
func begin() -> void:
	_testers += 1
	_begin_run(0)


func _begin_run(run: int) -> void:
	_run = run
	var pair: Vector2i = ORDERS[_order][run]
	town = SpikeTown.make(pair.y, pair.x as SpikeTown.View, Rect2(Vector2(0, BANNER_HEIGHT), SCREEN - Vector2(0, BANNER_HEIGHT)))
	_rebuild_ground()
	_show_only(_banner)
	_begin_task(0)


func _begin_task(index: int) -> void:
	_task_index = index
	_misclicks = 0
	_task_started_ms = Time.get_ticks_msec()
	_view_label.text = "%s · task %d of %d" % [VIEW_NAMES[town.view], index + 1, TASKS.size()]
	_task_label.text = town.task_text(TASKS[index])
	queue_redraw()


func _finish_task(skipped: bool) -> void:
	_results.append({
		"view": VIEW_NAMES[town.view], "layout": town.layout_name, "task": _task_index + 1,
		"input": _input_kind,
		"seconds": snappedf((Time.get_ticks_msec() - _task_started_ms) / 1000.0, 0.1),
		"misclicks": _misclicks, "skipped": skipped,
	})
	if _task_index + 1 < TASKS.size():
		_begin_task(_task_index + 1)
	elif _run == 0:
		_clear_town()
		_show_only(_between_panel)
	else:
		_clear_town()
		_question = 0
		_question_label.text = QUESTIONS[0]
		_order_answers()
		_show_only(_question_panel)


## Every other tester sees the two views' answers the other way round, so
## first-option bias evens out (Mara, #35). "No difference" stays last.
func _order_answers() -> void:
	var first: Button = _view_answers[_testers % 2]
	first.get_parent().move_child(first, 2)


## One answer to the current exit question. Public so the tests can drive it.
func answer(choice: String) -> void:
	_answers[QUESTIONS[_question]] = choice
	_question += 1
	if _question < QUESTIONS.size():
		_question_label.text = QUESTIONS[_question]
		return
	_results_label.text = "Order %d\n%s" % [_order + 1, results_text(_results, _answers)]
	print(JSON.stringify({"order": _order + 1, "tasks": _results, "answers": _answers}))
	_order_label.text = _order_text()
	_show_only(_results_panel)


func _clear_town() -> void:
	town = null
	if _ground != null:
		_ground.queue_free()
		_ground = null
	queue_redraw()


## The results the organizer copies down.
static func results_text(results: Array[Dictionary], answers: Dictionary[String, String]) -> String:
	var lines: PackedStringArray = []
	var totals: Dictionary[String, Vector2] = {}
	var skips: Dictionary[String, int] = {}
	for row: Dictionary in results:
		var view: String = "%s (town %s)" % [row["view"], row["layout"]]
		var notes: String = (" (skipped)" if row["skipped"] else "") \
			+ (" (controller)" if row["input"] == "controller" else "")
		lines.append("%s · task %d: %.1f s, %d misclick%s%s" % [
			view, int(row["task"]), float(row["seconds"]), int(row["misclicks"]),
			"" if int(row["misclicks"]) == 1 else "s", notes])
		# A skip is a give-up, not a quick run: it stays out of the totals,
		# which would otherwise reward the view people gave up on (Mara, #35).
		var total: Vector2 = totals.get(view, Vector2.ZERO)
		if row["skipped"]:
			skips[view] = skips.get(view, 0) + 1
		else:
			total += Vector2(int(row["misclicks"]), float(row["seconds"]))
		totals[view] = total
	lines.append("")
	for view: String in totals:
		var misses: int = int(totals[view].x)
		var skipped: String = " · %d skipped" % skips[view] if skips.has(view) else ""
		lines.append("%s in all: %d misclick%s, %.1f s%s" % [
			view, misses, "" if misses == 1 else "s", totals[view].y, skipped])
	lines.append("")
	for question: String in answers:
		lines.append("%s %s" % [question, answers[question]])
	lines.append("")
	lines.append("Cells: straight down 96×96 px, at an angle a 160×80 px diamond (about 30% less area).")
	lines.append("The whole town fits on screen with no pan or zoom. A bigger town changes the comparison.")
	return "\n".join(lines)


# --- Input ------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_input_kind = "mouse"
		_point_at(get_local_mouse_position())
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_input_kind = "mouse"
		if town != null:
			click(get_local_mouse_position())
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A and town != null:
		_input_kind = "controller"
		click(_cursor)


## A controller moves a free cursor with the left stick (two-halves spec:
## the town has a free cursor on controller).
func _process(delta: float) -> void:
	if town == null:
		return
	var stick: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() < STICK_DEADZONE:
		return
	_input_kind = "controller"
	_point_at((_cursor + stick * CURSOR_SPEED * delta).clamp(Vector2.ZERO, SCREEN))


func _point_at(point: Vector2) -> void:
	_cursor = point
	if town == null:
		return
	var hit: Dictionary = town.pick(point, _carrying())
	_hover = hit["cell"] if hit["kind"] == "cell" else SpikeTown.NO_CELL
	queue_redraw()


## One left click on the map. Public so the tests can drive it.
func click(point: Vector2) -> bool:
	var task: SpikeTown.Task = TASKS[_task_index]
	var hit: Dictionary = town.pick(point, _carrying())
	if town.task_done(task, hit):
		if task == SpikeTown.Task.PLACE:
			town.place_tea_stall(hit["cell"] as Vector2i)
		_finish_task(false)
		return true
	_misclicks += 1
	_miss_at = point
	_miss_ms = Time.get_ticks_msec()
	queue_redraw()
	get_tree().create_timer(0.35).timeout.connect(queue_redraw)
	return false


## The Tea stall task: the player is carrying a building.
func _carrying() -> bool:
	return town != null and TASKS[_task_index] == SpikeTown.Task.PLACE


# --- Drawing ----------------------------------------------------------------------------

func _rebuild_ground() -> void:
	if _ground != null:
		_ground.queue_free()
	_ground = ground_layer(town)
	# Under this node's own drawing (lots, blocks, markers).
	_ground.z_index = -1
	add_child(_ground)


## The ground as a real TileMapLayer, square or isometric, so the spike also
## shows whether Godot's tilemaps get in the way of either view (plan
## section 11). Tiles are drawn into an image at runtime: no art files.
static func ground_layer(for_town: SpikeTown) -> TileMapLayer:
	var tile_set: TileSet = TileSet.new()
	var iso: bool = for_town.view == SpikeTown.View.ISOMETRIC
	var size: Vector2i = Vector2i(int(SpikeTown.ISO_HALF_W * 2), int(SpikeTown.ISO_HALF_H * 2)) if iso \
		else Vector2i(int(SpikeTown.TOP_CELL), int(SpikeTown.TOP_CELL))
	if iso:
		tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
		tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = size
	var colors: Array[Color] = [SAND, STONE, SEA]
	var image: Image = Image.create(size.x * colors.size(), size.y, false, Image.FORMAT_RGBA8)
	for kind: int in colors.size():
		_paint_tile(image, Rect2i(Vector2i(size.x * kind, 0), size), colors[kind], iso)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = size
	for kind: int in colors.size():
		source.create_tile(Vector2i(kind, 0))
	tile_set.add_source(source, 0)
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = tile_set
	for y: int in SpikeTown.HEIGHT:
		for x: int in SpikeTown.WIDTH:
			layer.set_cell(Vector2i(x, y), 0, Vector2i(int(for_town.ground(Vector2i(x, y))), 0))
	layer.position = for_town.cell_center(Vector2i.ZERO) - layer.map_to_local(Vector2i.ZERO)
	return layer


static func _paint_tile(image: Image, rect: Rect2i, color: Color, iso: bool) -> void:
	var edge: Color = color.darkened(0.08)
	var half: Vector2 = Vector2(rect.size) / 2.0
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			var inside: float
			if iso:
				inside = absf(x + 0.5 - half.x) / half.x + absf(y + 0.5 - half.y) / half.y
				if inside > 1.0:
					continue
				inside = 1.0 - inside
			else:
				inside = minf(minf(x + 0.5, rect.size.x - x - 0.5), minf(y + 0.5, rect.size.y - y - 0.5)) / half.y
			image.set_pixel(rect.position.x + x, rect.position.y + y, edge if inside < 0.03 else color)


func _draw() -> void:
	if town == null:
		return
	for lot: Rect2i in town.lots:
		_draw_dashed_outline(town.footprint(lot), LOT_LINE)
	for row: Dictionary in town.draw_order():
		_draw_block(row)
	for row: Dictionary in town.draw_order():
		if not str(row["villager"]).is_empty():
			_draw_marker(row)
	if _carrying() and town.in_bounds(_hover):
		_draw_ghost(_hover)
	if Time.get_ticks_msec() - _miss_ms < 300:
		draw_arc(_miss_at, 18.0, 0.0, TAU, 24, MISS, 4.0)
	if _input_kind == "controller":
		draw_arc(_cursor, 14.0, 0.0, TAU, 24, INK, 3.0)
		draw_circle(_cursor, 3.0, INK)


func _draw_block(row: Dictionary) -> void:
	# While carrying, a building between the cursor and the ground fades,
	# so the ghost and the ground behind it stay readable (Mara, #35).
	var alpha: float = FADED if _carrying() \
		and Geometry2D.is_point_in_polygon(_cursor, town.block_outline(row)) else 1.0
	var roof: Color = Color(ROOF[str(row["kind"])], alpha)
	var ink: Color = Color(INK, alpha)
	var base: PackedVector2Array = town.footprint(row["rect"] as Rect2i)
	if town.view == SpikeTown.View.TOP_DOWN:
		var inset: PackedVector2Array = _inset(base, 6.0)
		draw_colored_polygon(inset, roof)
		draw_polyline(inset + PackedVector2Array([inset[0]]), ink, 2.0)
	else:
		var up: Vector2 = Vector2(0.0, -town.block_height(row))
		var left: PackedVector2Array = [base[3] + up, base[2] + up, base[2], base[3]]
		var right: PackedVector2Array = [base[2] + up, base[1] + up, base[1], base[2]]
		var top: PackedVector2Array = [base[0] + up, base[1] + up, base[2] + up, base[3] + up]
		draw_colored_polygon(left, Color(roof.darkened(0.3), alpha))
		draw_colored_polygon(right, Color(roof.darkened(0.15), alpha))
		draw_colored_polygon(top, roof)
		draw_polyline(town.block_outline(row) + PackedVector2Array([town.block_outline(row)[0]]), ink, 2.0)
		draw_polyline(PackedVector2Array([base[3] + up, base[2] + up, base[1] + up]), ink, 1.5)
		draw_line(base[2] + up, base[2], ink, 1.5)
	if str(row["villager"]).is_empty():
		var text_color: Color = Color(Color.WHITE, alpha) if row["kind"] == "landmark" else ink
		_draw_centered(str(row["name"]), town.roof_center(row), 24, text_color)


## The carried Tea stall, on top of everything so it never hides behind a
## block. A cell it can't go on gets a dashed outline and no fill.
func _draw_ghost(cell: Vector2i) -> void:
	var ghost: Dictionary = SpikeTown.TEA_STALL.duplicate()
	ghost["rect"] = Rect2i(cell, Vector2i.ONE)
	var outline: PackedVector2Array = town.block_outline(ghost)
	if town.is_free_lot(cell):
		draw_colored_polygon(outline, Color(ROOF["shop"], 0.75))
		draw_polyline(outline + PackedVector2Array([outline[0]]), INK, 2.5)
	else:
		_draw_dashed_outline(outline, MISS)


func _draw_marker(row: Dictionary) -> void:
	var center: Vector2 = town.marker_center(row)
	var sad: bool = row["villager"] == town.unhappy
	var fill: Color = UNHAPPY if sad else HAPPY
	draw_circle(center, SpikeTown.MARKER_RADIUS, fill)
	draw_arc(center, SpikeTown.MARKER_RADIUS, 0.0, TAU, 32, INK, 2.0)
	_draw_centered(SpikeTown.VILLAGER_INITIALS[str(row["villager"])], center + Vector2(0, -5), 20, Color.WHITE)
	# Smile or frown, and a rain cloud when unhappy, so mood never rests on
	# color alone (SA-5) and survives greyscale (Mara, #35).
	var mouth: Vector2 = center + Vector2(0, 11)
	if sad:
		draw_arc(mouth + Vector2(0, 7), 8.0, PI * 1.15, PI * 1.85, 8, Color.WHITE, 3.0)
		_draw_rain_cloud(center + Vector2(SpikeTown.MARKER_RADIUS + 12, -SpikeTown.MARKER_RADIUS + 2))
	else:
		draw_arc(mouth - Vector2(0, 4), 8.0, PI * 0.15, PI * 0.85, 8, Color.WHITE, 3.0)


func _draw_rain_cloud(at: Vector2) -> void:
	var puffs: Array[Vector3] = [Vector3(-13, 3, 11), Vector3(0, -6, 15), Vector3(14, 3, 11)]
	for drop: float in [-11.0, 0.0, 11.0]:
		draw_line(at + Vector2(drop, 12), at + Vector2(drop - 4, 26), CLOUD, 4.0)
	for puff: Vector3 in puffs:
		draw_circle(at + Vector2(puff.x, puff.y), puff.z + 2.0, INK)
	for puff: Vector3 in puffs:
		draw_circle(at + Vector2(puff.x, puff.y), puff.z, CLOUD)


func _draw_centered(text: String, center: Vector2, size: int, color: Color) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, center + Vector2(-width / 2.0, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_dashed_outline(corners: PackedVector2Array, color: Color) -> void:
	var inset: PackedVector2Array = _inset(corners, 3.0)
	for i: int in inset.size():
		draw_dashed_line(inset[i], inset[(i + 1) % inset.size()], color, 2.0, 10.0)


## Pulls a convex polygon's corners toward its middle by `pixels`.
static func _inset(corners: PackedVector2Array, pixels: float) -> PackedVector2Array:
	var middle: Vector2 = Vector2.ZERO
	for corner: Vector2 in corners:
		middle += corner
	middle /= corners.size()
	var out: PackedVector2Array = []
	for corner: Vector2 in corners:
		out.append(corner + (middle - corner).normalized() * pixels)
	return out


# --- UI ---------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_banner = _panel(Vector2(0, 0), Vector2(SCREEN.x, BANNER_HEIGHT - 10))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	_banner.add_child(row)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_view_label = _label("", 26)
	_task_label = _label("", 40)
	text.add_child(_view_label)
	text.add_child(_task_label)
	var skip: Button = _button("Skip this task")
	skip.pressed.connect(func() -> void: _finish_task(true))
	row.add_child(skip)

	skip.focus_mode = Control.FOCUS_NONE

	# The organizer's screen. Testers only see the intro after it.
	_start_panel = _centered_panel()
	var start_box: VBoxContainer = _start_panel.get_child(0) as VBoxContainer
	start_box.add_child(_label("Camera test: organizer", 40))
	_order_label = _label(_order_text(), 24)
	start_box.add_child(_order_label)
	for order: int in ORDERS.size():
		var pick: Button = _button(_order_name(order))
		pick.pressed.connect(start.bind(order))
		start_box.add_child(pick)

	_intro_panel = _centered_panel()
	var intro_box: VBoxContainer = _intro_panel.get_child(0) as VBoxContainer
	intro_box.add_child(_label("Town test", 44))
	intro_box.add_child(_label("You'll do three small tasks on a town map, then three more on a\ndifferent town seen another way. Click as you normally would. Don't rush.", 28))
	var go: Button = _button("Start")
	go.pressed.connect(begin)
	intro_box.add_child(go)

	_between_panel = _centered_panel()
	var between_box: VBoxContainer = _between_panel.get_child(0) as VBoxContainer
	between_box.add_child(_label("Half done. Next, three tasks on a different town, seen another way.", 30))
	var next: Button = _button("Continue")
	next.pressed.connect(func() -> void: _begin_run(1))
	between_box.add_child(next)

	_question_panel = _centered_panel()
	var question_box: VBoxContainer = _question_panel.get_child(0) as VBoxContainer
	question_box.add_child(_label("Last, three quick questions about the two views.", 28))
	_question_label = _label("", 36)
	question_box.add_child(_question_label)
	for choice: String in ANSWERS:
		var pick_answer: Button = _button(choice)
		pick_answer.pressed.connect(answer.bind(choice))
		question_box.add_child(pick_answer)
		if choice != ANSWERS[-1]:
			_view_answers.append(pick_answer)

	_results_panel = _centered_panel()
	var results_box: VBoxContainer = _results_panel.get_child(0) as VBoxContainer
	results_box.add_child(_label("Results: copy these into the thread", 36))
	_results_label = _label("", 24)
	results_box.add_child(_results_label)
	var again: Button = _button("Next tester")
	again.pressed.connect(func() -> void: _show_only(_start_panel))
	results_box.add_child(again)


static func _order_name(order: int) -> String:
	var halves: PackedStringArray = []
	for pair: Vector2i in ORDERS[order]:
		halves.append("%s, town %s" % [VIEW_NAMES[pair.x as SpikeTown.View].to_lower(), SpikeTown.LAYOUTS[pair.y]["name"]])
	return "Order %d: %s, then %s" % [order + 1, halves[0], halves[1]]


func _order_text() -> String:
	return "Testers so far: %d. Next tester: order %d. Give 2 testers a controller." \
		% [_testers, _testers % ORDERS.size() + 1]


func _show_only(panel: Control) -> void:
	for each: Control in [_banner, _start_panel, _intro_panel, _between_panel, _question_panel, _results_panel]:
		each.visible = each == panel
	# Focus the first button, so a controller can press it.
	if panel != _banner:
		for child: Node in panel.get_child(0).get_children():
			if child is Button:
				(child as Button).grab_focus.call_deferred()
				break


func _panel(at: Vector2, size: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1, 0.99, 0.96)
	style.border_color = LOT_LINE
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	style.shadow_color = Color(0, 0, 0, 0.12)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.position = at
	panel.size = size
	_ui.add_child(panel)
	return panel


func _centered_panel() -> PanelContainer:
	var panel: PanelContainer = _panel(Vector2(SCREEN.x / 2 - 520, 220), Vector2(1040, 0))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	return panel


func _label(text: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 28)
	button.custom_minimum_size = Vector2(0, 64)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = SAND.lightened(0.2) if state == "hover" else SAND
		style.border_color = INK if state == "focus" else LOT_LINE
		style.set_border_width_all(3 if state == "focus" else 2)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(12)
		button.add_theme_stylebox_override(state, style)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, INK)
	return button
