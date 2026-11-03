extends GutTest
## The M3 camera spike (tools/camera_spike): both views agree with Godot's
## own tilemaps, clicks land on what's drawn on top, every task in both
## layouts can be done, and the orders cross views with layouts.

const AREA: Rect2 = Rect2(0, 150, 1920, 930)
const VIEWS: Array[SpikeTown.View] = [SpikeTown.View.TOP_DOWN, SpikeTown.View.ISOMETRIC]


func test_both_views_line_up_with_godots_tilemaps() -> void:
	for view: SpikeTown.View in VIEWS:
		var town: SpikeTown = SpikeTown.make(0, view, AREA)
		var layer: TileMapLayer = CameraSpike.ground_layer(town)
		for y: int in SpikeTown.HEIGHT:
			for x: int in SpikeTown.WIDTH:
				var cell: Vector2i = Vector2i(x, y)
				assert_almost_eq(layer.position + layer.map_to_local(cell), town.cell_center(cell), Vector2(0.01, 0.01))
				assert_eq(layer.local_to_map(town.cell_center(cell) - layer.position), cell)
				assert_eq(town.cell_at(town.cell_center(cell)), cell)
		layer.free()


func test_the_map_fits_under_the_banner() -> void:
	for view: SpikeTown.View in VIEWS:
		var town: SpikeTown = SpikeTown.make(0, view, AREA)
		for row: Dictionary in town.standing():
			for point: Vector2 in town.block_outline(row):
				assert_true(AREA.grow(1).has_point(point), "%s fits in view %d" % [row["id"], view])
			assert_true(AREA.has_point(town.marker_center(row)))
		for corner: Vector2 in town.footprint(Rect2i(0, 0, SpikeTown.WIDTH, SpikeTown.HEIGHT)):
			assert_true(AREA.grow(1).has_point(corner))


func test_a_click_lands_on_what_is_drawn_on_top() -> void:
	var town: SpikeTown = SpikeTown.make(0, SpikeTown.View.ISOMETRIC, AREA)
	# The boat shed's front face hides the path cell just behind it.
	var face: Vector2 = town.grid_point(Vector2(8.05, 4.05)) + Vector2(0, -20)
	assert_eq(town.pick(face)["id"], "boat_shed")
	assert_eq(town.cell_at(face), Vector2i(7, 3), "the ground under that point is a path")
	# Carrying a building looks through blocks to the ground.
	assert_eq(town.pick(face, true), {"kind": "cell", "cell": Vector2i(7, 3)})
	# A marker wins over the roof it floats above.
	assert_eq(town.pick(town.marker_center(town.building("home_s")))["kind"], "villager")


## Mara: one target per layout sits behind a tall landmark at an angle.
func test_each_layout_hides_a_target_behind_a_landmark() -> void:
	var a: SpikeTown = SpikeTown.make(0, SpikeTown.View.ISOMETRIC, AREA)
	var hidden: int = 0
	for y: int in a.empty_lot.size.y:
		for x: int in a.empty_lot.size.x:
			var cell: Vector2i = a.empty_lot.position + Vector2i(x, y)
			if a.pick(a.cell_center(cell)).get("id", "") == "cafe":
				hidden += 1
	assert_gt(hidden, 0, "part of A's empty lot is behind the Café")
	var b: SpikeTown = SpikeTown.make(1, SpikeTown.View.ISOMETRIC, AREA)
	var behind: Array[Vector2i] = []
	for spot: Vector2i in _place_spots(b):
		if b.pick(b.cell_center(spot)).get("id", "") == "cafe":
			behind.append(spot)
	assert_gt(behind.size(), 0, "a spot beside B's Bait shop is behind the Café")


func test_every_task_can_be_done_in_both_layouts() -> void:
	for layout: int in 2:
		for view: SpikeTown.View in VIEWS:
			var town: SpikeTown = SpikeTown.make(layout, view, AREA)
			assert_true(town.task_done(SpikeTown.Task.EMPTY_LOT, town.pick(town.cell_center(_visible_lot_cell(town)))))
			var empty_lots: int = 0
			for lot: Rect2i in town.lots:
				var built: bool = false
				for row: Dictionary in town.standing():
					built = built or lot.intersects(row["rect"] as Rect2i)
				empty_lots += 0 if built else 1
			assert_eq(empty_lots, 1, "exactly one lot has nothing built on it")
			var home: Dictionary = {}
			for row: Dictionary in town.standing():
				if row["villager"] == town.unhappy:
					home = row
			assert_false(home.is_empty(), "the unhappy villager's home stands")
			assert_true(town.task_done(SpikeTown.Task.UNHAPPY, town.pick(town.marker_center(home))))
			var spots: Array[Vector2i] = _place_spots(town)
			assert_gt(spots.size(), 0, "somewhere to put the Tea stall")
			for spot: Vector2i in spots:
				var hit: Dictionary = town.pick(town.cell_center(spot), true)
				assert_true(town.task_done(SpikeTown.Task.PLACE, hit))


func test_the_layouts_differ() -> void:
	var a: SpikeTown = SpikeTown.make(0, SpikeTown.View.TOP_DOWN, AREA)
	var b: SpikeTown = SpikeTown.make(1, SpikeTown.View.TOP_DOWN, AREA)
	assert_ne(a.empty_lot, b.empty_lot)
	assert_ne(a.unhappy, b.unhappy)
	assert_ne(a.neighbor, b.neighbor)
	assert_ne(a.lots, b.lots, "different streets")
	assert_eq(a.task_text(SpikeTown.Task.EMPTY_LOT), "Find the lot with nothing built on it, and click it.")
	assert_eq(b.task_text(SpikeTown.Task.PLACE), "Put the Tea stall right beside the Bait shop, touching one of its sides.")


func test_the_orders_cross_views_with_layouts() -> void:
	var seen: Dictionary[Vector2i, int] = {}
	for order: Array in CameraSpike.ORDERS:
		var first: Vector2i = order[0]
		var second: Vector2i = order[1]
		assert_ne(first.x, second.x, "both views")
		assert_ne(first.y, second.y, "both layouts, neither twice")
		for pair: Vector2i in [first, second]:
			seen[pair] = seen.get(pair, 0) + 1
	assert_eq(seen.size(), 4)
	for pair: Vector2i in seen:
		assert_eq(seen[pair], 2, "every view meets every layout equally often")


func test_next_to_means_sharing_an_edge_on_a_free_lot() -> void:
	var town: SpikeTown = SpikeTown.make(0, SpikeTown.View.TOP_DOWN, AREA)
	# A's Net shed covers (0, 2) and (1, 2).
	assert_true(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(2, 2)}))
	assert_true(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(1, 1)}))
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(2, 1)}), "diagonal")
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(0, 3)}), "a path")
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(0, 2)}), "on the shed")


func test_a_session_counts_misclicks_time_and_answers() -> void:
	var spike: CameraSpike = autofree(CameraSpike.new())
	add_child(spike)
	spike.start(1)
	assert_null(spike.town, "the tester sees the intro first")
	spike.begin()
	var town: SpikeTown = spike.town
	assert_eq([town.view, town.layout_name], [SpikeTown.View.ISOMETRIC, "A"])
	assert_false(spike.click(Vector2(5, 5)), "off the map")
	assert_true(spike.click(town.cell_center(_visible_lot_cell(town))))
	assert_true(spike.click(town.marker_center(_home_of(town, town.unhappy))))
	assert_true(spike.click(town.cell_center(_place_spots(town)[0])))
	spike.call("_begin_run", 1)
	town = spike.town
	assert_eq([town.view, town.layout_name], [SpikeTown.View.TOP_DOWN, "B"])
	for i: int in 3:
		spike.call("_finish_task", true)
	assert_null(spike.town)
	for choice: String in ["At an angle", "Straight down", "No difference"]:
		spike.answer(choice)
	var results: Array[Dictionary] = spike.get("_results")
	assert_eq(results.size(), 6)
	assert_eq(results[0]["misclicks"], 1)
	assert_eq(results[0]["layout"], "A")
	assert_true(results[5]["skipped"])
	var answers: Dictionary[String, String] = spike.get("_answers")
	var text: String = CameraSpike.results_text(results, answers)
	assert_string_contains(text, "At an angle (town A) · task 1: ")
	assert_string_contains(text, "1 misclick,")
	assert_string_contains(text, "At an angle (town A) in all: 1 misclick,")
	assert_string_contains(text, "(skipped)")
	assert_string_contains(text, "Which view would you rather look at for an hour? At an angle")
	assert_string_contains(text, "Which was easier to use? No difference")
	assert_string_contains(text, "about 30% less area")


## A cell of the empty lot that no block covers, as a tester would click.
func _visible_lot_cell(town: SpikeTown) -> Vector2i:
	for y: int in town.empty_lot.size.y:
		for x: int in town.empty_lot.size.x:
			var cell: Vector2i = town.empty_lot.position + Vector2i(x, y)
			if town.pick(town.cell_center(cell))["kind"] == "cell":
				return cell
	return SpikeTown.NO_CELL


func test_skips_stay_out_of_the_totals() -> void:
	var answers: Dictionary[String, String] = {}
	var rows: Array[Dictionary] = [
		{"view": "At an angle", "layout": "A", "task": 1, "seconds": 10.0, "misclicks": 2, "skipped": false, "input": "mouse"},
		{"view": "At an angle", "layout": "A", "task": 2, "seconds": 4.0, "misclicks": 3, "skipped": true, "input": "mouse"},
		{"view": "Straight down", "layout": "B", "task": 1, "seconds": 6.0, "misclicks": 0, "skipped": false, "input": "controller"},
	]
	var text: String = CameraSpike.results_text(rows, answers)
	assert_string_contains(text, "At an angle (town A) in all: 2 misclicks, 10.0 s · 1 skipped")
	assert_string_contains(text, "Straight down (town B) in all: 0 misclicks, 6.0 s\n")
	assert_string_contains(text, "task 1: 6.0 s, 0 misclicks (controller)")


func test_the_view_answers_swap_between_testers() -> void:
	var spike: CameraSpike = autofree(CameraSpike.new())
	add_child(spike)
	var firsts: Array[String] = []
	for tester: int in 2:
		spike.start(0)
		spike.begin()
		for half: int in 2:
			if half == 1:
				spike.call("_begin_run", 1)
			for i: int in 3:
				spike.call("_finish_task", true)
		var buttons: Array[Node] = (spike.get("_question_panel") as Control).get_child(0).get_children().filter(
			func(node: Node) -> bool: return node is Button)
		firsts.append((buttons[0] as Button).text)
		assert_eq((buttons[2] as Button).text, "No difference")
		for q: int in 3:
			spike.answer("No difference")
	assert_ne(firsts[0], firsts[1])


func _home_of(town: SpikeTown, villager: String) -> Dictionary:
	for row: Dictionary in town.standing():
		if row["villager"] == villager:
			return row
	return {}


func _place_spots(town: SpikeTown) -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	for y: int in SpikeTown.HEIGHT:
		for x: int in SpikeTown.WIDTH:
			var cell: Vector2i = Vector2i(x, y)
			if town.is_free_lot(cell) and town.touches(cell, town.neighbor):
				spots.append(cell)
	return spots
