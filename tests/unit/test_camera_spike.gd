extends GutTest
## The M3 camera spike (tools/camera_spike): both views agree with Godot's
## own tilemaps, clicks land on what's drawn on top, and every task in both
## variants can be done.

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
	var shed: Dictionary = town.building("boat_shed")
	var face: Vector2 = town.grid_point(Vector2(8.05, 4.05)) + Vector2(0, -20)
	assert_eq(town.pick(face)["id"], "boat_shed")
	assert_eq(town.cell_at(face), Vector2i(7, 3), "the ground under that point is a path")
	# A marker wins over the roof it floats above.
	var home: Dictionary = town.building("home_s")
	assert_eq(town.pick(town.marker_center(home))["kind"], "villager")
	assert_false(shed.is_empty())
	# Carrying a building looks through blocks to the ground.
	assert_eq(town.pick(face, true), {"kind": "cell", "cell": Vector2i(7, 3)})


func test_every_task_can_be_done_in_both_variants() -> void:
	for variant: int in 2:
		for view: SpikeTown.View in VIEWS:
			var town: SpikeTown = SpikeTown.make(variant, view, AREA)
			var lot_cell: Vector2i = town.empty_lot.get_center()
			assert_true(town.task_done(SpikeTown.Task.EMPTY_LOT, town.pick(town.cell_center(lot_cell))))
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


func test_variant_b_moves_the_targets() -> void:
	var a: SpikeTown = SpikeTown.make(0, SpikeTown.View.TOP_DOWN, AREA)
	var b: SpikeTown = SpikeTown.make(1, SpikeTown.View.TOP_DOWN, AREA)
	assert_ne(a.empty_lot, b.empty_lot)
	assert_ne(a.unhappy, b.unhappy)
	assert_ne(a.neighbor, b.neighbor)
	assert_eq(b.task_text(SpikeTown.Task.PLACE), "Put the Tea stall next to the Bait shop.")


func test_next_to_means_sharing_an_edge_on_a_free_lot() -> void:
	var town: SpikeTown = SpikeTown.make(0, SpikeTown.View.TOP_DOWN, AREA)
	# Net shed covers (4, 2) and (5, 2).
	assert_true(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(6, 2)}))
	assert_true(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(5, 1)}))
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(6, 1)}), "diagonal")
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(4, 3)}), "a path")
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(3, 2)}), "a path")
	assert_false(town.task_done(SpikeTown.Task.PLACE, {"kind": "cell", "cell": Vector2i(4, 2)}), "on the shed")


func test_a_session_counts_misclicks_and_time() -> void:
	var spike: CameraSpike = autofree(CameraSpike.new())
	add_child(spike)
	spike.start(SpikeTown.View.ISOMETRIC)
	var town: SpikeTown = spike.town
	assert_eq(town.view, SpikeTown.View.ISOMETRIC)
	assert_false(spike.click(Vector2(5, 5)), "off the map")
	assert_true(spike.click(town.cell_center(town.empty_lot.get_center())))
	assert_true(spike.click(town.marker_center(_home_of(town, town.unhappy))))
	assert_true(spike.click(town.cell_center(_place_spots(town)[0])))
	spike.call("_begin_run", 1)
	town = spike.town
	assert_eq(town.view, SpikeTown.View.TOP_DOWN, "the second run swaps the view")
	spike.call("_finish_task", true)
	spike.call("_finish_task", true)
	spike.call("_finish_task", true)
	var results: Array[Dictionary] = spike.get("_results")
	assert_eq(results.size(), 6)
	assert_eq(results[0]["misclicks"], 1)
	assert_eq(results[0]["view"], "At an angle")
	assert_true(results[5]["skipped"])
	var text: String = CameraSpike.results_text(results)
	assert_string_contains(text, "At an angle · task 1: ")
	assert_string_contains(text, "1 misclick,")
	assert_string_contains(text, "At an angle in all: 1 misclick,")
	assert_string_contains(text, "(skipped)")


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
