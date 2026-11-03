extends GutTest
## The kit's words and marks (specs/bridge.md section 5): every die row says
## which faces changed and who changed it, every perk line has its gain and
## a shop's its cost, and a villager's bonus is a happy line or a ghost.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _state(villagers: Array[String]) -> GameState:
	var state: GameState = GameState.new(11)
	state.town.actions_left = 8
	state.town.needs_budget = false
	state.add_resource("driftwood", 60)
	state.add_resource("pearls", 10)
	for villager: String in villagers:
		state._villagers.append(villager)
	return state


func test_a_plain_kit_has_no_changed_dice_and_no_sources() -> void:
	var rows: Array[Dictionary] = KitSheet.dice_rows(data, Kit.fresh(data))
	assert_eq(rows.size(), 4)
	for row: Dictionary in rows:
		assert_eq(row["faces"], [1, 2, 3, 4, 5, 6] as Array[int])
		assert_false(KitSheet.is_changed(row))
		assert_eq(row["source"], "")
	assert_eq(KitSheet.summary(data, Kit.fresh(data)), "Your kit: 4 dice · 0 perks")


func test_the_weighted_die_marks_only_the_faces_that_changed() -> void:
	var kit: Kit = Kit.fresh(data, [{"perk": "weighted_die", "source": "net_shed"}] as Array[Dictionary])
	var rows: Array[Dictionary] = KitSheet.dice_rows(data, kit)
	assert_eq(rows[0]["faces"], [2, 3, 3, 4, 4, 5] as Array[int])
	assert_eq(rows[0]["changed"], [true, true, false, false, true, true] as Array[bool],
		"1→2, 2→3, 5→4, 6→5; the 3 and the 4 stay")
	assert_eq(rows[0]["source"], "Net shed")
	assert_false(KitSheet.is_changed(rows[1]), "only die 0 changes")


func test_the_spare_die_is_added_last_and_marked_added() -> void:
	var kit: Kit = Kit.fresh(data, [{"perk": "spare_die", "source": "boat_shed"}] as Array[Dictionary])
	var rows: Array[Dictionary] = KitSheet.dice_rows(data, kit)
	assert_eq(rows.size(), 5)
	assert_true(rows[4]["added"])
	assert_eq(rows[4]["faces"], [1, 2, 3, 4] as Array[int])
	assert_eq(rows[4]["changed"], [false, false, false, false] as Array[bool], "an added die is marked whole, not by face")
	assert_true(KitSheet.is_changed(rows[4]))
	assert_eq(rows[4]["source"], "Boat shed")
	assert_eq(KitSheet.summary(data, kit), "Your kit: 5 dice, 1 changed · 1 perk")


func test_every_perk_line_has_its_gain_and_a_shop_its_cost() -> void:
	var kit: Kit = Kit.fresh(data, [
		{"perk": "brace", "source": "shipwright"},
		{"perk": "chum", "source": "bait_shop"},
	] as Array[Dictionary])
	var lines: Array[Dictionary] = KitSheet.perk_lines(data, _state(["shipwright"] as Array[String]), kit)
	assert_eq(lines[0], {"kind": "perk", "source": "Shipwright", "source_id": "shipwright", "perk": "Brace",
		"gain": "Start every turn with 2 block", "cost": ""})
	assert_eq(lines[1]["kind"], "ghost", "a homeless villager's bonus is a ghost")
	assert_eq(lines[1]["text"], "If a home: +1 block, so 3 a turn")
	assert_eq(lines[2]["kind"], "perk")
	assert_eq([lines[2]["source"], lines[2]["perk"], lines[2]["gain"], lines[2]["cost"]],
		["Bait shop", "Chum", "+1 of each resource from treasure rooms", "Every enemy hits 1 harder"])
	assert_eq(lines.size(), 3, "a shop has no happy bonus")


func test_a_happy_villager_gets_a_happy_line_and_an_unhappy_one_a_ghost() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 6))
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.UNHAPPY)
	var lines: Array[Dictionary] = KitSheet.perk_lines(data, state, Kit.build(data, state))
	assert_eq(lines[1], {"kind": "ghost", "text": "If their home suited them: twice a turn"})
	assert_eq(state.move_building(data, state.town.placed[0]["uid"], Vector2i(0, 7)), "")
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.HAPPY)
	lines = KitSheet.perk_lines(data, state, Kit.build(data, state))
	assert_eq(lines[1], {"kind": "happy", "text": "Happy · Twice a turn"})


func test_a_shop_card_says_what_it_adds_to_the_kit() -> void:
	assert_eq(KitSheet.shop_perk(data, "net_shed"), {"perk": "Weighted die",
		"kit": "Kit: + Weighted die (2 3 3 4 4 5)", "gain": "Your first die never rolls a 1",
		"cost": "It never rolls a 6 either"})
	assert_eq(KitSheet.shop_perk(data, "boat_shed")["kit"], "Kit: + Spare die (1 2 3 4)")
	assert_eq(KitSheet.shop_perk(data, "tea_stall")["kit"], "Kit: + Slow pour", "no die, no faces")
	assert_eq(KitSheet.shop_perk(data, "cottage"), {})
	assert_eq(KitSheet.shop_perk(data, "cafe"), {})


func test_every_perk_reads_cleanly() -> void:
	for perk_id: String in data.ids("perks"):
		var row: Dictionary = data.row("perks", perk_id)
		assert_false(str(row["gain"]).is_empty(), "%s says what it gives" % perk_id)
		assert_false(str(row["gain"]).ends_with("."), "%s: a mark line has no full stop" % perk_id)
		assert_false(str(row["cost"]).ends_with("."), "%s: a mark line has no full stop" % perk_id)
