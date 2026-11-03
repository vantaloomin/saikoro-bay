extends GutTest
## The four shop perks (specs/bridge.md section 3, Vanta's pick): Weighted
## die, Slow pour, Chum and Spare die. Each is a trade-off, so each test
## checks the gain and the cost, and Imogen's rules for where they apply.

const VILLAGERS: Array[String] = ["onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]
const POUR: Array[Dictionary] = [{"perk": "slow_pour", "source": "tea_stall"}]
const CHUM: Array[Dictionary] = [{"perk": "chum", "source": "bait_shop"}]
const SPARE: Array[Dictionary] = [{"perk": "spare_die", "source": "boat_shed"}]
const WEIGHTED: Array[Dictionary] = [{"perk": "weighted_die", "source": "net_shed"}]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()
	assert_eq(data.errors, PackedStringArray())


func _state() -> GameState:
	var state: GameState = GameState.new(11)
	state.town.actions_left = 5
	state.town.needs_budget = false
	state.add_resource("driftwood", 60)
	state.add_resource("pearls", 10)
	state._villagers.append("shipwright")
	return state


## Builds `building_id` on the first spot that takes it.
func _build(state: GameState, building_id: String) -> void:
	for y: int in 12:
		for x: int in 12:
			if state.build(data, building_id, Vector2i(x, y)).is_empty():
				return
	fail_test("found no spot for %s" % building_id)


func _both(a: Array[Dictionary], b: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = a.duplicate()
	out.append_array(b)
	return out


func _fight(perks: Array[Dictionary], seed_value: int = 7, enemy: String = "card_shark") -> Fight:
	var kit: Kit = Kit.fresh(data, perks)
	var fight: Fight = Fight.create(data, Kit.LOADOUT, enemy, RngStreams.new(seed_value), kit.perks, -1, kit.die_specs())
	assert_not_null(fight)
	return fight


# --- The town gives them ---------------------------------------------------------

func test_each_standing_shop_gives_its_perk() -> void:
	var state: GameState = _state()
	assert_eq(Kit.build(data, state).perks.map(func(entry: Dictionary) -> String: return entry["perk"]),
		["brace"], "no shops, no shop perks")
	for shop: String in ["net_shed", "tea_stall", "bait_shop", "boat_shed"]:
		_build(state, shop)
	var kit: Kit = Kit.build(data, state)
	assert_eq(kit.perks.map(func(entry: Dictionary) -> Array: return [entry["perk"], entry["source"]]),
		[["brace", "shipwright"], ["weighted_die", "net_shed"], ["slow_pour", "tea_stall"],
			["chum", "bait_shop"], ["spare_die", "boat_shed"]], "villagers first, then shops in buildings.json order")
	assert_eq(kit.perk("chum")["cost"], 1, "Chum's cost travels in the kit")
	assert_eq(kit.dice.size(), 5)
	assert_eq(kit.dice[0], {"type": "weighted_d6", "faces": [2, 3, 3, 4, 4, 5] as Array[int],
		"source": "net_shed", "added": false}, "the Weighted die takes die 0")
	assert_eq(kit.dice[4], {"type": "d4", "faces": [1, 2, 3, 4] as Array[int], "source": "boat_shed",
		"added": true}, "the Spare die goes last, marked added")
	for i: int in range(1, 4):
		assert_eq(kit.dice[i]["source"], "", "die %d is the loadout's" % i)


func test_every_shop_names_a_perk_and_no_other_building_does() -> void:
	for id: String in data.ids("buildings"):
		var building: Dictionary = data.row("buildings", id)
		assert_eq(building["kind"] == "shop", not str(building["perk"]).is_empty(), id)


# --- Weighted die ----------------------------------------------------------------

func test_the_weighted_die_never_shows_a_one_or_a_six_and_leaves_the_rest_alone() -> void:
	var seen: Dictionary[int, bool] = {}
	for seed_value: int in 60:
		var plain: Fight = _fight([], seed_value)
		var weighted: Fight = _fight(WEIGHTED, seed_value)
		seen[weighted.hand[0].value] = true
		for i: int in range(1, 4):
			assert_eq(weighted.hand[i].value, plain.hand[i].value, "seed %d die %d" % [seed_value, i])
	assert_eq(seen.keys().filter(func(v: int) -> bool: return v < 2 or v > 5), [], "never a 1 or a 6")
	assert_eq(_fight(WEIGHTED).hand[0].max_face(), 5, "a nudge stops at 5 on it")


# --- Spare die -------------------------------------------------------------------

func test_the_spare_die_rolls_its_own_stream() -> void:
	for seed_value: int in 30:
		var plain: Fight = _fight([], seed_value)
		var spare: Fight = _fight(SPARE, seed_value)
		assert_eq(spare.hand.size(), 5)
		assert_true(spare.hand[4].value in [1, 2, 3, 4])
		for i: int in 4:
			assert_eq(spare.hand[i].value, plain.hand[i].value, "the d4 shifts no other die (seed %d)" % seed_value)


func test_koban_s_vault_plays_without_the_added_die() -> void:
	var kit: Kit = Kit.fresh(data, _both(SPARE, WEIGHTED))
	var vault: Vault = Vault.create(data, Kit.LOADOUT, DelveRun.VAULT_ID, RngStreams.new(3), kit.perks, Haul.new(),
		kit.die_specs())
	assert_eq(vault.table.hand.size(), 4, "best 3 of 5 would be a flat increase (Imogen's #49 audit)")
	assert_eq(vault.table.hand[0].faces, [2, 3, 3, 4, 4, 5] as Array[int], "a changed die still plays")
	for d: DiceTable.Die in vault.table.hand:
		assert_ne(d.type_id, "d4")


# --- Slow pour -------------------------------------------------------------------

func test_slow_pour_replaces_the_reroll() -> void:
	var fight: Fight = _fight(POUR)
	assert_eq(fight.rerolls_left, 0)
	assert_eq(fight.reroll_refusal(0), "Slow pour replaces the reroll: no die to spend.")
	assert_false(fight.reroll(0))
	assert_eq(_fight([]).pour_refusal(), "No Slow pour in this kit.")


func test_a_pour_rerolls_every_free_die_and_spends_none() -> void:
	var fight: Fight = _fight(POUR)
	for i: int in 4:
		fight.hand[i].value = 3
	fight.place(1, "strike")
	var expected_rng: RngStreams = RngStreams.new()
	expected_rng.load_dict(fight.table._rng.to_dict())
	var expected: Array[int] = []
	for die_id: int in [0, 2, 3]:
		expected.append(fight.hand[die_id].faces[expected_rng.die_index(die_id, 6)])
	assert_true(fight.pour())
	assert_eq([fight.hand[0].value, fight.hand[2].value, fight.hand[3].value] as Array[int], expected)
	assert_eq(fight.hand[1].value, 3, "placed dice stay")
	for d: Fight.Die in fight.hand:
		assert_false(d.discarded, "no die is spent")
	assert_eq(fight.table.pours_left, 1)
	assert_eq(fight.events.back(), {"type": "pour", "perk": "slow_pour", "source": "tea_stall", "dice": [0, 2, 3], "left": 1})


func test_two_pours_last_the_whole_fight() -> void:
	var fight: Fight = _fight(POUR, 3, "card_shark")
	assert_true(fight.pour())
	fight.end_turn()
	assert_eq(fight.table.pours_left, 1, "a new turn gives none back")
	assert_true(fight.pour())
	assert_eq(fight.pour_refusal(), "No pours left this fight.")
	assert_false(fight.pour())
	fight.end_turn()
	assert_eq(fight.table.pours_left, 0)
	assert_eq(fight.rerolls_left, 0, "and no reroll comes back either")


func test_a_planning_copy_keeps_the_pour_count_but_cant_pour() -> void:
	var fight: Fight = _fight(POUR)
	fight.pour()
	var copy: Fight = fight.planning_copy()
	assert_eq(copy.table.pours_left, 1)
	assert_eq(copy.table.pour_source, "tea_stall")
	assert_eq(copy.pour_refusal(), "Planning copies can't reroll.")


func test_a_pour_with_nothing_free_is_refused() -> void:
	var fight: Fight = _fight(POUR)
	for i: int in 4:
		fight.hand[i].value = 3
	fight.place(0, "strike")
	fight.place(1, "guard")
	fight.place(2, "pair_bet")
	fight.place(3, "pair_bet")
	assert_eq(fight.pour_refusal(), "Nothing left to reroll.")


func test_slow_pour_is_for_fights_only() -> void:
	var kit: Kit = Kit.fresh(data, POUR)
	var room: DiceRoom = DiceRoom.create(data, Kit.LOADOUT, "treasure", RngStreams.new(5), kit.perks, 30, kit.die_specs())
	assert_eq(room.table.rerolls_left, 1, "a treasure room keeps its reroll")
	assert_false(room.table.is_pouring())


func test_a_fight_with_pours_replays_from_its_moves() -> void:
	for seed_value: int in 10:
		var fight: Fight = _fight(POUR, seed_value)
		var bot: PlannerBot = PlannerBot.new()
		bot.play_fight(fight)
		var again: Fight = _fight(POUR, seed_value)
		assert_true(again.apply_moves(fight.moves), "seed %d" % seed_value)
		assert_eq(again.events, fight.events)


func test_the_planner_pours_when_it_helps() -> void:
	var pours: int = 0
	for seed_value: int in 20:
		var fight: Fight = _fight(POUR, seed_value)
		PlannerBot.new().play_fight(fight)
		pours += fight.moves.filter(func(m: Dictionary) -> bool: return m["move"] == "pour").size()
	assert_gt(pours, 0)


# --- Chum ------------------------------------------------------------------------

func test_chum_makes_every_attack_one_harder() -> void:
	var plain: Fight = _fight([])
	var chum: Fight = _fight(CHUM)
	assert_eq(chum.current_intent()["attack"], (plain.current_intent()["attack"] as int) + 1)
	assert_eq(chum.current_intent()["chum"], 1, "so the board can badge it")
	assert_eq(chum.next_intent()["attack"], (plain.next_intent()["attack"] as int) + 1)
	for fight: Fight in [plain, chum]:
		for i: int in 4:
			fight.hand[i].value = 6
		fight.place(0, "strike")
		fight.place(1, "strike")
		fight.end_turn()
	assert_eq(plain.player_hp - chum.player_hp, 1, "the extra point lands")


func test_chum_adds_to_rising_stakes() -> void:
	var enemy: String = ""
	for id: String in data.ids("enemies"):
		if data.row("enemies", id)["twist"] == "rising_stakes":
			enemy = id
	if enemy.is_empty():
		pass_test("no rising stakes enemy in the shipped data")
		return
	var chum: Fight = _fight(CHUM, 7, enemy)
	var plain: Fight = _fight([], 7, enemy)
	chum.intent_index = 2
	plain.intent_index = 2
	assert_eq(chum.current_intent()["attack"], (plain.current_intent()["attack"] as int) + 1)
	assert_eq(chum.current_intent()["raised"], 2)


func test_chum_pays_one_more_of_each_resource_a_treasure_room_pays() -> void:
	var kit: Kit = Kit.fresh(data, CHUM)
	var plain: DiceRoom = DiceRoom.create(data, Kit.LOADOUT, "treasure", RngStreams.new(5), [], 30)
	var chum: DiceRoom = DiceRoom.create(data, Kit.LOADOUT, "treasure", RngStreams.new(5), kit.perks, 30, kit.die_specs())
	for room: DiceRoom in [plain, chum]:
		for i: int in 4:
			room.hand[i].value = [5, 4, 4, 2][i]
		room.place(0, "small_lock")
		room.place(1, "pearl_lock")
		room.place(2, "pearl_lock")
		room.end_turn()
	assert_eq(plain.payout, {"driftwood": 5, "pearls": 2} as Dictionary[String, int])
	assert_eq(chum.payout, {"driftwood": 6, "pearls": 3} as Dictionary[String, int], "nothing for a lock that stayed shut")
	var badges: Array = chum.events.filter(func(e: Dictionary) -> bool: return e["type"] == "perk")
	assert_eq(badges, [
		{"type": "perk", "perk": "chum", "source": "bait_shop", "resource": "driftwood", "amount": 1},
		{"type": "perk", "perk": "chum", "source": "bait_shop", "resource": "pearls", "amount": 1}])


func test_chum_pays_nothing_more_outside_treasure_rooms() -> void:
	var kit: Kit = Kit.fresh(data, CHUM)
	for room_id: String in ["rest", "rescue"]:
		var room: DiceRoom = DiceRoom.create(data, Kit.LOADOUT, room_id, RngStreams.new(5), kit.perks, 20, kit.die_specs())
		assert_eq(room.chum_amount, 0, room_id)


# --- RoomBot with the biggest kit (Imogen's #49 audit) ---------------------------

## Five dice (the Spare die) and two nudges a turn (a happy pearl diver):
## the bot still only tries plans that complete slots.
func test_the_room_bot_stays_small_with_five_dice_and_two_nudges() -> void:
	var kit: Kit = Kit.fresh(data, _both(SPARE, [{"perk": "nudge", "source": "pearl_diver", "happy": true}]))
	for room_id: String in ["treasure", "rescue"]:
		var room: DiceRoom = DiceRoom.create(data, Kit.LOADOUT, room_id, RngStreams.new(3), kit.perks, 20, kit.die_specs())
		assert_eq(room.table.nudge_uses_per_turn, 2)
		for i: int in 5:
			room.hand[i].value = [3, 4, 5, 5, 4][i]
		var bot: RoomBot = RoomBot.new()
		bot.best_plan(room)
		assert_lt(bot.trials, 400, "%s: %d plans" % [room_id, bot.trials])
