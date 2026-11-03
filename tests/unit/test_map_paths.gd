extends GutTest
## Path reading for the map screen's hover (Mara's review #4): paths come
## from what the player can see, and the summary counts per path.

const VILLAGERS: Array[String] = ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


## A hand-made floor: rows of [type, state, links].
func _rows(spec: Array) -> Array:
	var rows: Array = []
	for row_spec: Array in spec:
		var row: Array = []
		for c: int in row_spec.size():
			var room: Array = row_spec[c]
			row.append({"col": c, "type": room[0], "state": room[1], "links": room[2]})
		rows.append(row)
	return rows


func test_paths_start_at_the_rooms_you_can_walk_into() -> void:
	for s: int in range(1, 30):
		var run: DelveRun = DelveRun.create(data, s, [], VILLAGERS, LANDMARKS, 0)
		var rows: Array = RunView.new(run).rows()
		var paths: Array[Array] = MapPaths.all_paths(rows)
		assert_gt(paths.size(), 0)
		for p: Array in paths:
			assert_eq(p.size(), rows.size(), "top to bottom")
			assert_eq((p[0] as Vector2i).x, 0)
			for i: int in p.size() - 1:
				var a: Vector2i = p[i]
				var b: Vector2i = p[i + 1]
				assert_has((rows[a.x] as Array)[a.y]["links"], b.y, "seed %d: paths follow links" % s)


func test_no_paths_once_you_are_in_a_room() -> void:
	var run: DelveRun = DelveRun.create(data, 3, [], VILLAGERS, LANDMARKS, 0)
	run.choose(run.reachable()[0])
	assert_eq(MapPaths.all_paths(RunView.new(run).rows()), [] as Array[Array])


func test_summary_counts_each_path_and_gives_ranges() -> void:
	var rows: Array = _rows([
		[["fight", "next", [0, 1]]],
		[["rest", "open", [0]], ["fight", "open", [0]]],
		[["?", "open", []]],
	])
	var paths: Array[Array] = MapPaths.all_paths(rows)
	assert_eq(paths.size(), 2)
	assert_eq(MapPaths.summary(rows, paths), "1-2 fights · 0-1 rest · 1 ?")
	var through_rest: Array[Array] = MapPaths.through(paths, Vector2i(1, 0))
	assert_eq(MapPaths.summary(rows, through_rest), "1 fight · 1 rest · 1 ?")


func test_lit_links_are_only_the_paths_through_the_room() -> void:
	var rows: Array = _rows([
		[["fight", "next", [0]], ["treasure", "next", [0, 1]]],
		[["fight", "open", [0]], ["elite", "open", [0]]],
		[["rest", "open", []]],
	])
	var through: Array[Array] = MapPaths.through(MapPaths.all_paths(rows), Vector2i(1, 1))
	var links: Dictionary = MapPaths.links(through)
	assert_eq(links.size(), 2)
	assert_true(links.has([Vector2i(0, 1), Vector2i(1, 1)]))
	assert_true(links.has([Vector2i(1, 1), Vector2i(2, 0)]))
	assert_eq(MapPaths.cells(through).size(), 3)
	assert_eq(MapPaths.summary(rows, through), "0 fights · 1 elite · 1 rest · 1 treasure", "one path: no fights is worth saying")


func test_differing_paths_name_the_safest_and_the_riskiest() -> void:
	var rows: Array = _rows([
		[["fight", "next", [0]], ["rest", "next", [0, 1]]],
		[["elite", "open", [0]], ["rest", "open", [0]]],
		[["treasure", "open", []]],
	])
	var ends: Dictionary = MapPaths.extremes(rows, MapPaths.all_paths(rows))
	assert_eq(ends["safest"], "0 fights · 2 rests · 1 treasure")
	assert_eq(ends["riskiest"], "1 fight · 1 elite · 1 treasure", "an elite counts as two fights")
	var one: Array[Array] = MapPaths.through(MapPaths.all_paths(rows), Vector2i(0, 0))
	assert_eq(MapPaths.extremes(rows, one), {"only": "1 fight · 1 elite · 1 treasure"})


func test_rooms_seen_only_with_foresight_are_marked() -> void:
	var perks: Array[Dictionary] = [{"perk": "foresight", "source": "shrine_keeper"}]
	var run: DelveRun = DelveRun.create(data, 9, perks, VILLAGERS, LANDMARKS, 0)
	run.choose(run.reachable()[0])
	var rows: Array = RunView.new(run).rows()
	for r: int in rows.size():
		for room: Dictionary in rows[r] as Array:
			assert_eq(room.get("foresight", false), r == run.row + run.reveal_rows, "row %d" % r)
	var plain: DelveRun = DelveRun.create(data, 9, [], VILLAGERS, LANDMARKS, 0)
	for row_rooms: Array in RunView.new(plain).rows():
		for room: Dictionary in row_rooms:
			assert_false(room.has("foresight"))
