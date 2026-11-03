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
	var lines: Array[Dictionary] = KitSheet.perk_lines(data, kit)
	assert_eq(lines[0], {"source": "Shipwright", "source_id": "shipwright", "perk": "Brace",
		"gain": "Start every turn with 2 block", "cost": "", "bonus": "+1 block, so 3 a turn", "happy": false})
	assert_eq(KitSheet.gain_text(lines[0]), "Start every turn with 2 block · if happy: +1 block, so 3 a turn",
		"a bonus not yet earned folds into the gain line")
	assert_eq([lines[1]["source"], lines[1]["perk"], lines[1]["gain"], lines[1]["cost"], lines[1]["bonus"]],
		["Bait shop", "Chum", "+1 of each resource from treasure rooms", "Every enemy hits 1 harder", ""])
	assert_eq(KitSheet.gain_text(lines[1]), "+1 of each resource from treasure rooms", "a shop has no happy bonus")
	assert_eq(lines.size(), 2)


func test_a_happy_villager_s_bonus_says_it_applies() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 6))
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.UNHAPPY)
	var line: Dictionary = KitSheet.perk_lines(data, Kit.build(data, state))[0]
	assert_eq(KitSheet.gain_text(line), "Raise one die by 1, once a turn · if happy: twice a turn")
	assert_eq(state.move_building(data, state.town.placed[0]["uid"], Vector2i(0, 7)), "")
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.HAPPY)
	line = KitSheet.perk_lines(data, Kit.build(data, state))[0]
	assert_eq(KitSheet.gain_text(line), "Raise one die by 1, once a turn · happy: twice a turn")


func test_plain_dice_group_and_a_changed_one_says_what_changed() -> void:
	var kit: Kit = Kit.fresh(data, [
		{"perk": "weighted_die", "source": "net_shed"},
		{"perk": "spare_die", "source": "boat_shed"},
	] as Array[Dictionary])
	var groups: Array = KitSheet.dice_groups(data, kit).map(
		func(row: Dictionary) -> Array: return [row["chip"], row["count"]])
	assert_eq(groups, [["Net shed · no 1s or 6s", 1], ["Standard × 3", 3], ["Boat shed · added", 1]])
	assert_eq(KitSheet.dice_groups(data, Kit.fresh(data)).map(
		func(row: Dictionary) -> String: return row["chip"]), ["Standard × 4"])


func test_a_change_names_the_numbers_a_die_lost() -> void:
	assert_eq(KitSheet.change_text([1, 2, 3, 4, 5, 6], [2, 3, 3, 4, 4, 5] as Array[int]), "no 1s or 6s")
	assert_eq(KitSheet.change_text([1, 2, 3, 4, 5, 6], [2, 2, 3, 4, 5, 6] as Array[int]), "no 1s")
	assert_eq(KitSheet.change_text([1, 2, 3, 4, 5, 6], [3, 3, 4, 4, 5, 5] as Array[int]), "no 1s, 2s or 6s")
	assert_eq(KitSheet.change_text([1, 2, 3, 4, 5, 6], [1, 1, 2, 3, 4, 5, 6] as Array[int]), "changed")
	assert_eq(KitSheet.change_text([1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6] as Array[int]), "")


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


func test_a_mood_change_names_what_the_perk_gains_or_loses() -> void:
	assert_eq(KitSheet.happy_change(data, "shipwright", true), "Brace 2 → 3")
	assert_eq(KitSheet.happy_change(data, "shipwright", false), "Brace 3 → 2")
	assert_eq(KitSheet.happy_change(data, "pearl_diver", true), "Nudge 1 → 2 a turn")
	assert_eq(KitSheet.happy_change(data, "onsen_keeper", true), "Mend 5 → 6")
	assert_eq(KitSheet.happy_change(data, "shrine_keeper", true), "Foresight 1 → 2")
	assert_eq(KitSheet.happy_change(data, "bait_shop", true), "", "only villagers turn happy")
