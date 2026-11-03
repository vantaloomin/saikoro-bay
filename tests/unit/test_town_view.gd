extends GutTest
## The town's diorama camera and picking (M3 PR 5a): the projection round-
## trips, the whole town fits the screen, pan and zoom keep the ground under
## the pointer, villagers never stand inside a building, and a click lands
## on the nearest thing along the ray. Also the shell tray's tokens and the
## hold-to-confirm button.

var data: GameData
var map: TownMap


func before_all() -> void:
	data = GameData.load_dir()
	map = GameState.town_map(data)


func _state(villagers: Array[String] = []) -> GameState:
	var state: GameState = GameState.new(5)
	state.arrive(data)
	for villager: String in villagers:
		state._villagers.append(villager)
	return state


func _place(state: GameState, building: String, cell: Vector2i, resident: String = "") -> int:
	var uid: int = state.town.place(building, cell)
	if not resident.is_empty():
		state.town.homes[resident] = uid
	return uid


func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func test_every_cell_round_trips_through_the_screen() -> void:
	for screen: Vector2 in [Vector2(1920, 1080), Vector2(1280, 800), Vector2(1280, 720)]:
		var view: TownView = TownView.make(map, screen)
		for y: int in map.height:
			for x: int in map.width:
				var cell: Vector2i = Vector2i(x, y)
				assert_eq(view.cell_at(view.to_screen(_cell_center(cell))), cell, "%s at %s" % [cell, screen])


func test_the_whole_town_fits_the_screen() -> void:
	for screen: Vector2 in [Vector2(1920, 1080), Vector2(1280, 800)]:
		var view: TownView = TownView.make(map, screen)
		var tall: float = TownView.BODY_HEIGHT["landmark"] + TownView.ROOF_HEIGHT["landmark"]
		for corner: Vector3 in [Vector3(0, tall, 0), Vector3(map.width, tall, 0), Vector3(0, 0, map.land_rows + 1.0),
				Vector3(map.width, 0, map.land_rows + 1.0)]:
			assert_true(Rect2(Vector2.ZERO, screen).has_point(view.to_screen(corner)), "%s on a %s screen" % [corner, screen])


func test_off_the_map_is_no_cell() -> void:
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	assert_eq(view.cell_at(view.to_screen(Vector3(-2.0, 0.0, -2.0))), TownView.NO_CELL)
	assert_eq(view.cell_at(Vector2(960, -4000)), TownView.NO_CELL, "the sky")


func test_zoom_keeps_the_ground_under_the_pointer() -> void:
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var pointer: Vector2 = view.to_screen(_cell_center(Vector2i(3, 2)))
	var before: Vector3 = view.ground_at(pointer)
	view.zoom_at(pointer, 1.5)
	assert_almost_eq((view.ground_at(pointer) as Vector3).distance_to(before), 0.0, 0.01)
	view.zoom_at(pointer, 100.0)
	assert_eq(view.distance, view.min_distance, "zoom stops at the closest")
	view.zoom_at(pointer, 0.001)
	assert_eq(view.distance, view.max_distance, "and at the farthest")


func test_pan_drags_the_ground_with_the_pointer() -> void:
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var grabbed: Vector3 = view.ground_at(Vector2(960, 540))
	view.pan(Vector2(120, -80))
	assert_almost_eq((view.ground_at(Vector2(1080, 460)) as Vector3).distance_to(grabbed), 0.0, 0.01)
	for i: int in 50:
		view.pan(Vector2(4000, 4000))
	assert_true(view.target.x >= -TownView.PAN_SLACK and view.target.z >= -TownView.PAN_SLACK,
		"you can't pan the town away")


func test_a_click_lands_on_buildings_villagers_and_ground() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	var shed: int = _place(state, "boat_shed", Vector2i(10, 6))
	_place(state, "cottage", Vector2i(0, 7), "pearl_diver")
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var roof: Vector3 = TownView.block_box(data, state.town.entry(shed)).get_center()
	assert_eq(view.pick(view.to_screen(roof), data, state), {"kind": "building", "uid": shed})
	var spot: Vector3 = view.home_spot(data, state.town, "pearl_diver")
	assert_eq(view.pick(view.to_screen(spot + Vector3(0, 0.5, 0)), data, state),
		{"kind": "villager", "villager": "pearl_diver"})
	var empty: Vector2 = view.to_screen(_cell_center(Vector2i(6, 2)))
	assert_eq(view.pick(empty, data, state), {"kind": "cell", "cell": Vector2i(6, 2)})
	assert_eq(view.pick(view.to_screen(roof), data, state, true)["kind"], "cell", "carrying looks through buildings")


func test_villagers_stand_outside_every_building() -> void:
	var state: GameState = _state(["pearl_diver", "shipwright"] as Array[String])
	_place(state, "cottage", Vector2i(2, 5), "shipwright")
	_place(state, "net_shed", Vector2i(2, 6))
	_place(state, "cottage", Vector2i(0, 7), "pearl_diver")
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var spots: Dictionary[String, Vector3] = view.villager_spots(data, state)
	for villager: String in spots:
		var feet: Vector2i = Vector2i(floori(spots[villager].x), floori(spots[villager].z))
		assert_true(state.town.building_at(data, feet).is_empty(), "%s isn't inside a building" % villager)
		assert_ne(map.ground(feet), TownMap.Ground.SEA, "%s isn't in the sea" % villager)


func test_villagers_with_no_home_wait_on_the_dock() -> void:
	var state: GameState = _state(["pearl_diver", "shipwright"] as Array[String])
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var spots: Dictionary[String, Vector3] = view.villager_spots(data, state)
	assert_eq(spots["pearl_diver"], view.dock_spot(0))
	assert_eq(spots["shipwright"], view.dock_spot(1))
	assert_eq(view.pick(view.to_screen(view.dock_spot(1) + Vector3(0, 0.5, 0)), data, state),
		{"kind": "villager", "villager": "shipwright"})


# --- Walking -----------------------------------------------------------------------------

## Whether a walk along `route` ever steps into a building, checked every
## few centimetres, and whether it ever leaves the land or the dock.
func _walk_problem(view: TownView, state: GameState, route: PackedVector3Array) -> String:
	for i: int in 401:
		var at: Vector3 = TownView.along(route, i / 400.0)
		var feet: Vector3 = Vector3(at.x, 0.05, at.z)
		for placed: Dictionary in state.town.placed:
			if TownView.block_box(data, placed).has_point(feet):
				return "walks through the %s at %s" % [placed["building"], at]
		var on_dock: bool = at.z < map.land_rows + 1.1 and at.x < TownView.DOCK_CELLS + 0.3
		if at.x < 0.0 or at.x > map.width or at.z < 0.0 or (at.z > map.land_rows and not on_dock):
			return "walks off the land at %s" % at
	return ""


func test_open_ground_is_crossed_in_one_stroke() -> void:
	var state: GameState = _state()
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var route: PackedVector3Array = view.walk_route(data, state.town, Vector3(0.5, 0.0, 0.5), Vector3(10.5, 0.0, 6.5))
	assert_eq(route, PackedVector3Array([Vector3(0.5, 0.0, 0.5), Vector3(10.5, 0.0, 6.5)]))


func test_a_walk_goes_round_a_building_not_through_it() -> void:
	var state: GameState = _state()
	_place(state, "hot_spring", Vector2i(5, 5))
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var from: Vector3 = Vector3(6.5, 0.0, 4.5)
	var to: Vector3 = Vector3(6.5, 0.06, 7.5)
	var route: PackedVector3Array = view.walk_route(data, state.town, from, to)
	assert_ne(_walk_problem(view, state, PackedVector3Array([from, to])), "", "the straight line would cut through")
	assert_eq(_walk_problem(view, state, route), "")
	assert_eq(route[0], from, "starts where they stand")
	assert_eq(route[route.size() - 1], to, "and ends where they're going")
	assert_lt(route.size(), 6, "a few corners, not a staircase")


func test_a_walk_threads_a_row_of_houses_from_the_dock() -> void:
	var state: GameState = _state()
	for x: int in 4:
		_place(state, "cottage", Vector2i(x, 7))
	_place(state, "net_shed", Vector2i(5, 7))
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var to: Vector3 = Vector3(1.5, 0.06, 6.5)
	for i: int in 4:
		var route: PackedVector3Array = view.walk_route(data, state.town, view.dock_spot(i), to)
		assert_eq(_walk_problem(view, state, route), "", "from dock spot %d" % i)


func test_every_gathering_walk_stays_out_of_buildings() -> void:
	var state: GameState = _state(["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"] as Array[String])
	_place(state, "cottage", Vector2i(0, 7), "pearl_diver")
	_place(state, "cottage", Vector2i(2, 5), "shipwright")
	_place(state, "cottage", Vector2i(9, 2), "onsen_keeper")
	_place(state, "net_shed", Vector2i(5, 6))
	_place(state, "boat_shed", Vector2i(9, 5))
	_place(state, "tea_stall", Vector2i(1, 2))
	var landmark: int = _place(state, "hot_spring", Vector2i(5, 0))
	var view: TownView = TownView.make(map, Vector2(1920, 1080))
	var homes: Dictionary[String, Vector3] = view.villager_spots(data, state)
	var spots: Array[Vector3] = view.gather_spots(data, state.town, state.town.entry(landmark), homes.size())
	var i: int = 0
	for villager: String in homes:
		var there: PackedVector3Array = view.walk_route(data, state.town, homes[villager], spots[i])
		assert_eq(_walk_problem(view, state, there), "", "%s on the way there" % villager)
		var back: PackedVector3Array = view.walk_route(data, state.town, spots[i], homes[villager])
		assert_eq(_walk_problem(view, state, back), "", "%s on the way home" % villager)
		i += 1


func test_a_point_along_a_route_goes_by_distance() -> void:
	var route: PackedVector3Array = [Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 1)]
	assert_eq(TownView.along(route, 0.0), Vector3(0, 0, 0))
	assert_eq(TownView.along(route, 0.75), Vector3(3, 0, 0), "three of the four steps are the first leg")
	assert_eq(TownView.along(route, 1.0), Vector3(3, 0, 1))
	assert_eq(TownView.along(PackedVector3Array([Vector3.ONE]), 0.5), Vector3.ONE)


# --- Shells and the hold button -------------------------------------------------------------

func test_shells_show_kept_fresh_and_spent() -> void:
	var state: GameState = _state()
	state.town.actions_left = 5
	state.town.kept = 1
	assert_eq(ShellTray.tokens_for(data, state), ["kept", "fresh", "fresh", "fresh", "fresh"] as Array[String])
	state.town.actions_left = 3
	assert_eq(ShellTray.tokens_for(data, state), ["kept", "fresh", "fresh", "spent", "spent"] as Array[String],
		"fresh actions go first, so the pearl is spent last")
	state.town.actions_left = 0
	state.town.kept = 0
	assert_eq(ShellTray.tokens_for(data, state), ["spent", "spent", "spent", "spent"] as Array[String])
	assert_eq(ShellTray.describe(state), "No actions left")
	state.town.actions_left = 2
	state.town.kept = 1
	assert_eq(ShellTray.describe(state), "2 actions left, 1 kept from your last visit")


func test_hold_button_fills_drains_and_fires_once() -> void:
	var button: HoldButton = HoldButton.new()
	add_child_autofree(button)
	watch_signals(button)
	button.start_hold()
	button.advance(HoldButton.HOLD_SECONDS * 0.5)
	button.stop_hold()
	assert_signal_not_emitted(button, "held", "letting go early does nothing")
	assert_almost_eq(button.progress(), 0.5, 0.01, "the fill stays for a moment")
	button.advance(HoldButton.DRAIN_SECONDS)
	assert_eq(button.progress(), 0.0, "then drains away")
	button.start_hold()
	button.advance(HoldButton.HOLD_SECONDS)
	button.advance(HoldButton.HOLD_SECONDS)
	assert_signal_emit_count(button, "held", 1)
	assert_false(button.is_holding(), "a finished hold needs a new press")
	button.disabled = true
	button.start_hold()
	button.advance(HoldButton.HOLD_SECONDS)
	assert_signal_emit_count(button, "held", 1, "a disabled button can't be held")


func _hud() -> Array[Rect2]:
	return [Rect2(32, 32, 280, 200), Rect2(32, 900, 330, 148), Rect2(1468, 32, 420, 860), Rect2(1408, 920, 480, 128)]


func test_the_land_is_framed_clear_of_the_hud() -> void:
	var hud: Array[Rect2] = _hud()
	var view: TownView = TownView.make(map, Vector2(1920, 1080), hud)
	var outline: PackedVector2Array = view.land_outline()
	for rect: Rect2 in hud:
		var corners: PackedVector2Array = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]
		assert_eq(Geometry2D.intersect_polygons(outline, corners).size(), 0, "nothing of the land under %s" % rect)
	var free: TownView = TownView.make(map, Vector2(1920, 1080))
	assert_gt(view.distance, free.distance, "the HUD costs some size")
	assert_lt(view.distance, free.distance * 1.6, "but panels may cover the sky and sea")


func test_a_selection_is_kept_out_from_under_the_hud() -> void:
	var hud: Array[Rect2] = _hud()
	var view: TownView = TownView.make(map, Vector2(1920, 1080), hud)
	var far_corner: Vector3 = Vector3(map.width - 0.5, 0.0, 0.5)
	view.zoom_at(view.to_screen(Vector3(1.0, 0.0, map.land_rows - 1.0)), 2.0)
	view.ensure_visible(far_corner)
	var at: Vector2 = view.to_screen(far_corner)
	assert_true(Rect2(Vector2.ZERO, view.size).has_point(at))
	for rect: Rect2 in hud:
		assert_false(rect.has_point(at), "not under %s" % rect)