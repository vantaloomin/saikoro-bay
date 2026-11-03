extends GutTest
## The build list's words (M3 PR 5b): costs read in shells and resources,
## waiting landmarks come first and are free, locked rows name the next
## step, and a card lists every reason but "No actions left", which the
## tray says once.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _state() -> GameState:
	var state: GameState = GameState.new(3)
	state.town.actions_left = 4
	state.town.needs_budget = false
	return state


func test_costs_read_in_shells_and_resources() -> void:
	assert_eq(BuildList.cost_text(data, "cottage"), "1 shell + 4 driftwood")
	assert_eq(BuildList.cost_text(data, "tea_stall"), "1 shell + 3 driftwood + 1 pearl")
	assert_eq(BuildList.cost_text(data, "boat_shed"), "1 shell + 8 driftwood + 2 pearls")
	assert_eq(BuildList.cost_text(data, "hot_spring"), "Free", "landmarks are free to place")


func test_the_list_puts_waiting_landmarks_first() -> void:
	var state: GameState = _state()
	var ids: Array = BuildList.entries(data, state).map(func(entry: Dictionary) -> String: return entry["id"])
	assert_false(ids.has("hot_spring"), "a landmark not won yet isn't on the list")
	state._landmarks.append("hot_spring")
	var first: Dictionary = BuildList.entries(data, state)[0]
	assert_eq(first["id"], "hot_spring")
	assert_eq(first["cost"], BuildList.FREE)
	assert_eq(first["status"], BuildList.WAITING)
	state.town.place("hot_spring", Vector2i(9, 0))
	assert_ne(BuildList.entries(data, state)[0]["id"], "hot_spring", "placed, it leaves the list")


func test_locked_and_all_built_rows_say_why() -> void:
	var state: GameState = _state()
	var rows: Dictionary = {}
	for entry: Dictionary in BuildList.entries(data, state):
		rows[entry["id"]] = entry
	assert_true(rows["bait_shop"]["locked"])
	assert_eq(rows["bait_shop"]["status"], "Needs 2 buildings placed (you have 0)")
	assert_eq(rows["boat_shed"]["status"], "The Shipwright needs to live in town first")
	assert_false(rows["cottage"]["locked"])
	assert_eq(rows["cottage"]["status"], "", "short on driftwood is the card's to say")
	state.town.place("net_shed", Vector2i(0, 0))
	for entry: Dictionary in BuildList.entries(data, state):
		if entry["id"] == "net_shed":
			assert_true(entry["done"])
			assert_eq(entry["status"], BuildList.ALL_BUILT)


func test_a_card_lists_every_reason_but_no_actions() -> void:
	var state: GameState = _state()
	state.add_resource("driftwood", 1)
	var card: Dictionary = BuildList.card_for(data, state, "tea_stall")
	assert_eq(card["title"], "Tea stall")
	assert_eq(Array(card["lines"]), [
		"Will feed a dice perk (M4).", "Costs 1 shell + 3 driftwood + 1 pearl",
		"Needs 2 more driftwood (you have 1) · found in fights and small locks below",
		"Needs 1 more pearl (you have 0) · found in fights and pearl locks below",
	])
	assert_false(card["can_place"])
	state.add_resource("driftwood", 3)
	state.add_resource("pearls", 1)
	assert_true(BuildList.card_for(data, state, "tea_stall")["can_place"])
	state.town.actions_left = 0
	card = BuildList.card_for(data, state, "tea_stall")
	assert_false(card["can_place"])
	assert_eq((card["lines"] as PackedStringArray).size(), 2, "no actions is said on the tray, not here")
