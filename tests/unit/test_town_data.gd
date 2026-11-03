extends GutTest
## The town's data (specs/town.md sections 2, 3 and 5): the map, the
## buildings and villagers' wishes load cleanly, bad rows are reported, and
## the whole slice set fits the map (there's no demolishing, so a player
## must never run out of room).

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()
	assert_eq(data.errors, PackedStringArray(), "\n".join(data.errors))


func _map() -> TownMap:
	return TownMap.from_row(data.row("town", "saikoro_bay"))


func test_the_map_is_lots_between_paths_and_the_sea_below() -> void:
	var map: TownMap = _map()
	assert_eq([map.width, map.height, map.land_rows], [12, 9, 8])
	assert_eq(map.lots, [
		Rect2i(0, 0, 4, 4), Rect2i(5, 0, 3, 4), Rect2i(9, 0, 3, 4),
		Rect2i(0, 5, 4, 3), Rect2i(5, 5, 3, 3), Rect2i(9, 5, 3, 3),
	] as Array[Rect2i])
	assert_eq(map.ground(Vector2i(4, 0)), TownMap.Ground.PATH)
	assert_eq(map.ground(Vector2i(0, 4)), TownMap.Ground.PATH)
	assert_eq(map.ground(Vector2i(0, 8)), TownMap.Ground.SEA)
	assert_eq(map.ground(Vector2i(11, 7)), TownMap.Ground.LOT)
	assert_eq(map.lot_index(Vector2i(6, 6)), 4)
	assert_eq(map.lot_index(Vector2i(4, 4)), -1)
	assert_true(map.fits_one_lot(Rect2i(9, 5, 3, 2)))
	assert_false(map.fits_one_lot(Rect2i(3, 0, 2, 1)), "across a path")


func test_costs_parse_as_whole_amounts() -> void:
	assert_eq(TownMap.parse_cost(["driftwood:3", "pearls:1"]), {"driftwood": 3, "pearls": 1})
	assert_eq(TownMap.parse_cost([]), {})
	for bad: Array in [["driftwood"], ["driftwood:0"], ["driftwood:1.5"], ["driftwood:2", "driftwood:1"], [":2"]]:
		assert_null(TownMap.parse_cost(bad), str(bad))


func test_the_slice_buildings_and_wishes() -> void:
	assert_eq(data.ids("buildings").size(), 8)
	assert_eq(data.row("buildings", "cafe")["kind"], "landmark")
	assert_eq(TownMap.parse_cost(data.row("buildings", "tea_stall")["cost"] as Array), {"driftwood": 3, "pearls": 1})
	assert_eq(data.row("villagers", "pearl_diver")["wish_text"], "Next to the sea")
	assert_eq(data.row("villagers", "onsen_keeper")["wish_buildings"], ["hot_spring", "tea_stall"])


## Every slice building once, plus a Cottage for each villager, fits at once.
func test_the_whole_slice_set_fits_the_map() -> void:
	var map: TownMap = _map()
	var sizes: Array[Vector2i] = []
	for id: String in data.ids("buildings"):
		var building: Dictionary = data.row("buildings", id)
		var copies: int = data.ids("villagers").size() if building["kind"] == "home" else 1
		for i: int in copies:
			sizes.append(Vector2i(building["width"], building["height"]))
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y > b.x * b.y)
	assert_true(_pack(map, sizes, 0, {}), "%d buildings fit" % sizes.size())


func test_a_sea_wish_has_a_lot_beside_the_sea() -> void:
	var map: TownMap = _map()
	var shore: int = 0
	for lot: Rect2i in map.lots:
		shore += 1 if lot.end.y == map.land_rows else 0
	assert_gt(shore, 0)


func test_bad_town_rows_are_reported() -> void:
	var texts: Dictionary[String, String] = _shipped()
	var buildings: Dictionary = JSON.parse_string(texts["buildings"])
	var items: Array = buildings["items"]
	items[0]["cost"] = ["driftwood:0"]
	items[1]["cost"] = ["seashells:2"]
	items[2]["width"] = 5
	items[3]["unlock_count"] = 0
	items[4]["unlock_villager"] = "ghost"
	items[6]["cost"] = ["pearls:1"]
	texts["buildings"] = JSON.stringify(buildings)
	var villagers: Dictionary = JSON.parse_string(texts["villagers"])
	(villagers["items"] as Array)[0]["wish_buildings"] = ["net_shed"]
	texts["villagers"] = JSON.stringify(villagers)
	var bad: GameData = GameData.new()
	bad.load_texts(texts)
	assert_eq(bad.errors, PackedStringArray([
		"buildings \"cottage\": cost entries must be \"resource:amount\" with amounts of at least 1",
		"buildings \"net_shed\": cost names missing resource \"seashells\"",
		"buildings \"tea_stall\": 5x1 fits in no lot",
		"buildings \"bait_shop\": buildings_placed needs unlock_count >= 1 and no villager",
		"buildings \"boat_shed\": villager_in_town needs a real unlock_villager",
		"buildings \"cafe\": landmarks are free and everything else costs something",
		"villagers \"pearl_diver\": a sea wish names no buildings, a next_to wish names some",
	]))


func test_the_town_map_is_checked() -> void:
	var texts: Dictionary[String, String] = _shipped()
	var town: Dictionary = JSON.parse_string(texts["town"])
	(town["items"] as Array)[0]["path_columns"] = [8, 4]
	texts["town"] = JSON.stringify(town)
	var bad: GameData = GameData.new()
	bad.load_texts(texts)
	assert_eq(bad.errors, PackedStringArray(["town: path columns and rows must rise and stay on the land"]))
	var second: Dictionary = ((town["items"] as Array)[0] as Dictionary).duplicate()
	(town["items"] as Array).append(second)
	(town["items"] as Array)[1]["id"] = "second"
	texts["town"] = JSON.stringify(town)
	bad = GameData.new()
	bad.load_texts(texts)
	assert_eq(bad.errors, PackedStringArray(["town: needs exactly one row, got 2"]))


func _shipped() -> Dictionary[String, String]:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	return texts


## Backtracking: place sizes[index:] on free lot cells, or report it can't.
func _pack(map: TownMap, sizes: Array[Vector2i], index: int, taken: Dictionary) -> bool:
	if index == sizes.size():
		return true
	for lot: Rect2i in map.lots:
		for y: int in range(lot.position.y, lot.end.y - sizes[index].y + 1):
			for x: int in range(lot.position.x, lot.end.x - sizes[index].x + 1):
				var spot: Rect2i = Rect2i(Vector2i(x, y), sizes[index])
				var cells: Array[Vector2i] = []
				for dy: int in spot.size.y:
					for dx: int in spot.size.x:
						cells.append(spot.position + Vector2i(dx, dy))
				if cells.any(func(cell: Vector2i) -> bool: return taken.has(cell)):
					continue
				for cell: Vector2i in cells:
					taken[cell] = true
				if _pack(map, sizes, index + 1, taken):
					return true
				for cell: Vector2i in cells:
					taken.erase(cell)
	return false
