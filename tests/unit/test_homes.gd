extends GutTest
## Homes and wishes (specs/town.md section 5, PR 4): villagers move into
## free homes in rescue order, swapping homes is one free call, and
## happiness is derived from the layout, never saved.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _state(villagers: Array[String] = []) -> GameState:
	var state: GameState = GameState.new(11)
	state.town.actions_left = 5
	state.town.needs_budget = false
	state.add_resource("driftwood", 60)
	state.add_resource("pearls", 10)
	for villager: String in villagers:
		state._villagers.append(villager)
	return state


func _uid_at(state: GameState, cell: Vector2i) -> int:
	return state.town.building_at(data, cell)["uid"]


func test_next_to_means_sharing_an_edge() -> void:
	var cottage: Rect2i = Rect2i(1, 1, 1, 1)
	assert_true(Town.touches(cottage, Rect2i(2, 1, 1, 1)), "right")
	assert_true(Town.touches(cottage, Rect2i(1, 0, 1, 1)), "above")
	assert_true(Town.touches(cottage, Rect2i(0, 2, 2, 1)), "a wide building below")
	assert_false(Town.touches(cottage, Rect2i(2, 2, 1, 1)), "diagonal")
	assert_false(Town.touches(cottage, Rect2i(3, 1, 1, 1)), "a gap")
	assert_false(Town.touches(cottage, Rect2i(0, 0, 2, 2)), "overlapping")
	assert_false(Town.touches(Rect2i(3, 0, 1, 1), Rect2i(5, 0, 1, 1)), "a path between")


func test_villagers_move_into_free_homes_in_rescue_order() -> void:
	var state: GameState = _state(["pearl_diver", "shipwright"] as Array[String])
	assert_eq(state.homeless(), ["pearl_diver", "shipwright"] as Array[String])
	assert_eq(state.build(data, "cottage", Vector2i(2, 2)), [] as Array[Dictionary])
	assert_eq(state.town.homes, {"pearl_diver": 1} as Dictionary[String, int], "first rescued, first housed")
	state.build(data, "cottage", Vector2i(0, 0))
	assert_eq(state.town.homes, {"pearl_diver": 1, "shipwright": 2} as Dictionary[String, int])
	state.build(data, "cottage", Vector2i(1, 0))
	assert_eq(state.town.resident(3), "", "a spare home stays empty")
	assert_eq(state.homeless(), [] as Array[String])
	state._villagers.append("onsen_keeper")
	assert_eq(state.settle_villagers(data), ["onsen_keeper"] as Array[String], "a new arrival takes the spare")
	assert_eq(state.settle_villagers(data), [] as Array[String], "settling twice changes nothing")
	assert_eq(state.town_problems(data), PackedStringArray())


func test_only_homes_house_anyone() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "net_shed", Vector2i(0, 0))
	assert_eq(state.homeless(), ["pearl_diver"] as Array[String])
	assert_eq(state.swap_home(data, "pearl_diver", 1), "Not a home")


func test_the_nowhere_to_live_line() -> void:
	var state: GameState = _state()
	assert_eq(state.homeless_line(data), "")
	state._villagers.append("pearl_diver")
	assert_eq(state.homeless_line(data), "The Pearl diver has nowhere to live")
	state._villagers.append("shipwright")
	assert_eq(state.homeless_line(data), "The Pearl diver and the Shipwright have nowhere to live")
	state._villagers.append("onsen_keeper")
	assert_eq(state.homeless_line(data), "3 villagers have nowhere to live")
	state.build(data, "cottage", Vector2i(0, 0))
	assert_eq(state.homeless_line(data), "The Shipwright and the Onsen keeper have nowhere to live")


func test_swapping_homes_moves_both_or_neither() -> void:
	var state: GameState = _state(["pearl_diver", "shipwright"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 0))
	state.build(data, "cottage", Vector2i(2, 0))
	assert_eq(state.swap_home(data, "pearl_diver", 2), "")
	assert_eq(state.town.homes, {"pearl_diver": 2, "shipwright": 1} as Dictionary[String, int], "the shipwright swaps back")
	assert_eq(state.swap_home(data, "pearl_diver", 2), "Already lives here")
	assert_eq(state.swap_home(data, "onsen_keeper", 1), "Not in town")
	assert_eq(state.swap_home(data, "pearl_diver", 99), "Not a home")
	assert_eq(state.town.homes, {"pearl_diver": 2, "shipwright": 1} as Dictionary[String, int], "refusals change nothing")
	assert_eq(state.town.actions_left, 3, "swaps cost nothing")


func test_a_villager_from_the_dock_takes_a_home_and_its_owner_waits() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 0))
	state._villagers.append("shipwright")
	assert_eq(state.swap_home(data, "shipwright", 1), "")
	assert_eq(state.town.homes, {"shipwright": 1} as Dictionary[String, int])
	assert_eq(state.homeless(), ["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(2, 0))
	assert_eq(state.town.homes["pearl_diver"], 2, "and moves into the next home built")


func test_a_sea_wish_needs_a_home_on_the_shore() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.HOMELESS)
	state.build(data, "cottage", Vector2i(0, 6))
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.UNHAPPY, "one row up from the sea")
	assert_eq(state.move_building(data, 1, Vector2i(0, 7)), "")
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.HAPPY, "moving the home moves the wish")


func test_a_next_to_wish_counts_any_named_building_on_an_edge() -> void:
	var state: GameState = _state(["onsen_keeper"] as Array[String])
	state.build(data, "cottage", Vector2i(1, 1))
	assert_eq(state.mood(data, "onsen_keeper"), Town.Mood.UNHAPPY)
	state.build(data, "tea_stall", Vector2i(2, 2))
	assert_eq(state.mood(data, "onsen_keeper"), Town.Mood.UNHAPPY, "diagonal doesn't count")
	state.move_building(data, 2, Vector2i(2, 1))
	assert_eq(state.mood(data, "onsen_keeper"), Town.Mood.HAPPY)
	state.move_building(data, 2, Vector2i(5, 1))
	assert_eq(state.mood(data, "onsen_keeper"), Town.Mood.UNHAPPY, "a move can break a wish")
	state._landmarks.append("hot_spring")
	state.build(data, "hot_spring", Vector2i(1, 2))
	assert_eq(state.mood(data, "onsen_keeper"), Town.Mood.HAPPY, "the Hot Spring counts too")


func test_moods_are_never_saved() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 7))
	var text: String = JSON.stringify(state.to_dict())
	for word: String in ["mood", "happy", "HAPPY"]:
		assert_false(text.contains(word), word)
	var loaded: GameState = GameState.from_dict(JSON.parse_string(text))
	assert_eq(loaded.mood(data, "pearl_diver"), Town.Mood.HAPPY)


func test_banking_a_delve_settles_the_rescued() -> void:
	var state: GameState = _state()
	state.build(data, "cottage", Vector2i(0, 0))
	state.start_delve(data)
	var haul: Haul = Haul.new()
	haul.villagers.append("pearl_diver")
	assert_true(state.finish_delve(data, Haul.SURFACED, haul))
	assert_eq(state.town.homes, {"pearl_diver": 1} as Dictionary[String, int], "arrival lives in finish_delve")


## Imogen's #38 audit: whatever the player does, nobody waits at the dock
## while a home stands empty, and the town stays loadable.
func test_nobody_is_homeless_beside_an_empty_home() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var ids: PackedStringArray = data.ids("buildings")
	var map: TownMap = GameState.town_map(data)
	for run: int in 40:
		rng.seed = 1000 + run
		var state: GameState = _state()
		state._landmarks.append_array(["cafe", "hot_spring"] as Array[String])
		for step: int in 60:
			state.town.actions_left = 5
			state.add_resource("driftwood", 10)
			state.add_resource("pearls", 3)
			var cell: Vector2i = Vector2i(rng.randi_range(0, map.width - 1), rng.randi_range(0, map.height - 1))
			match rng.randi_range(0, 3):
				0:
					state.build(data, ids[rng.randi_range(0, ids.size() - 1)], cell)
				1:
					if not state.town.placed.is_empty():
						state.move_building(data, state.town.placed[rng.randi_range(0, state.town.placed.size() - 1)]["uid"], cell)
				2:
					if not state.villagers().is_empty() and not state.town.placed.is_empty():
						state.swap_home(data, state.villagers()[rng.randi_range(0, state.villagers().size() - 1)],
							state.town.placed[rng.randi_range(0, state.town.placed.size() - 1)]["uid"])
				3:
					var left: Array[String] = state.villagers_left(data)
					state.start_delve(data)
					var haul: Haul = Haul.new()
					if not left.is_empty():
						haul.villagers.append(left[0])
					state.finish_delve(data, Haul.SURFACED, haul)
			var free_home: bool = state.town.placed.any(func(building: Dictionary) -> bool:
				return building["building"] == "cottage" and state.town.resident(building["uid"]).is_empty())
			if not state.homeless().is_empty() and free_home:
				fail_test("run %d step %d: %s homeless beside an empty home" % [run, step, state.homeless()])
				return
			if not state.town_problems(data).is_empty():
				fail_test("run %d step %d: %s" % [run, step, state.town_problems(data)])
				return
	pass_test("40 random towns of 60 steps")


func test_wish_spots_light_the_cells_that_make_someone_happier() -> void:
	var state: GameState = _state(["onsen_keeper"] as Array[String])
	state.build(data, "cottage", Vector2i(1, 1))
	var before: Dictionary = state.town.to_dict()
	var spots: Array[Vector2i] = state.wish_spots(data, "tea_stall")
	assert_eq(state.town.to_dict(), before, "looking changes nothing")
	assert_eq(spots.size(), 4, "the four cells around her home: %s" % [spots])
	for cell: Vector2i in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		assert_has(spots, cell)


func test_wish_spots_for_a_new_home_count_who_would_move_in() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	var spots: Array[Vector2i] = state.wish_spots(data, "cottage")
	assert_gt(spots.size(), 0)
	for cell: Vector2i in spots:
		assert_eq(cell.y, GameState.town_map(data).land_rows - 1, "a cottage on the shore, for the pearl diver")


func test_wish_spots_for_a_move_lift_the_building() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(1, 1))
	var uid: int = state.town.homes["pearl_diver"]
	var spots: Array[Vector2i] = state.wish_spots(data, "cottage", uid)
	assert_has(spots, Vector2i(1, 7), "moving her home to the shore")
	assert_does_not_have(spots, Vector2i(1, 1), "where it already is changes nothing")
