extends GutTest
## The kit (specs/bridge.md sections 2 and 4): built from the town at Go
## down, a replay input through the strict from_dict, and the source of every
## die and perk a delve takes down.

const VILLAGERS: Array[String] = ["shipwright", "onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _state(villagers: Array[String]) -> GameState:
	var state: GameState = GameState.new(11)
	state.town.actions_left = 5
	state.town.needs_budget = false
	state.add_resource("driftwood", 60)
	state.add_resource("pearls", 10)
	for villager: String in villagers:
		state._villagers.append(villager)
	return state


func test_a_fresh_kit_is_the_loadout() -> void:
	var kit: Kit = Kit.fresh(data)
	assert_eq(kit.dice.size(), 4)
	for entry: Dictionary in kit.dice:
		assert_eq(entry["type"], "d6")
		assert_eq(entry["faces"], [1, 2, 3, 4, 5, 6] as Array[int])
		assert_eq(entry["source"], "")
	assert_true(kit.perks.is_empty())


func test_the_town_gives_each_villager_s_perk() -> void:
	var kit: Kit = Kit.build(data, _state(["pearl_diver", "shipwright"] as Array[String]))
	assert_eq(kit.perks.map(func(entry: Dictionary) -> Array: return [entry["perk"], entry["source"]]),
		[["nudge", "pearl_diver"], ["brace", "shipwright"]])
	assert_eq(kit.perk("brace")["amount"], 2, "no home yet, no bonus")
	assert_false(kit.perk("brace")["happy"])


func test_a_happy_villager_s_perk_gets_its_bonus() -> void:
	var state: GameState = _state(["pearl_diver"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 6))
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.UNHAPPY)
	var plain: Dictionary = Kit.build(data, state).perk("nudge")
	assert_eq([plain["amount"], plain["uses_per_turn"], plain["happy"]], [1, 1, false])
	assert_eq(state.move_building(data, state.town.placed[0]["uid"], Vector2i(0, 7)), "")
	assert_eq(state.mood(data, "pearl_diver"), Town.Mood.HAPPY)
	var happy: Dictionary = Kit.build(data, state).perk("nudge")
	assert_eq([happy["amount"], happy["uses_per_turn"], happy["happy"]], [1, 2, true],
		"a happy pearl diver nudges twice a turn, still by 1")


func test_happy_amounts_reach_the_rooms() -> void:
	var kit: Kit = Kit.fresh(data, [
		{"perk": "nudge", "source": "pearl_diver", "happy": true},
		{"perk": "brace", "source": "shipwright", "happy": true},
		{"perk": "mend", "source": "onsen_keeper", "happy": true},
	] as Array[Dictionary])
	var fight: Fight = Fight.create(data, Kit.LOADOUT, "card_shark", RngStreams.new(5), kit.perks, -1, kit.die_specs())
	assert_eq(fight.table.nudge_uses_per_turn, 2)
	assert_eq(fight.player_block, 3, "Brace gives 3 block when the shipwright is happy")
	var room: DiceRoom = DiceRoom.create(data, Kit.LOADOUT, "treasure", RngStreams.new(5), kit.perks, 30, kit.die_specs())
	assert_eq(room.table.nudge_uses_per_turn, 2)


func test_foresight_shows_more_when_the_shrine_keeper_is_happy() -> void:
	var plain: DelveRun = DelveRun.create(data, 9, Kit.fresh(data), VILLAGERS, LANDMARKS, 0)
	var seer: DelveRun = DelveRun.create(data, 9, Kit.fresh(data, [{"perk": "foresight", "source": "shrine_keeper"}] as Array[Dictionary]),
		VILLAGERS, LANDMARKS, 0)
	var happy: DelveRun = DelveRun.create(data, 9, Kit.fresh(data,
		[{"perk": "foresight", "source": "shrine_keeper", "happy": true}] as Array[Dictionary]), VILLAGERS, LANDMARKS, 0)
	assert_eq(seer.reveal_rows, plain.reveal_rows + 1)
	assert_eq(happy.reveal_rows, plain.reveal_rows + 2)


func test_a_changed_die_rolls_its_own_faces_and_leaves_the_others_alone() -> void:
	var fresh: Kit = Kit.fresh(data)
	var changed: Kit = Kit.fresh(data)
	changed.dice[0]["faces"] = [2, 3, 3, 4, 4, 5] as Array[int]
	changed.dice[0]["source"] = "net_shed"
	var a: Fight = Fight.create(data, Kit.LOADOUT, "card_shark", RngStreams.new(21), [], -1, fresh.die_specs())
	var b: Fight = Fight.create(data, Kit.LOADOUT, "card_shark", RngStreams.new(21), [], -1, changed.die_specs())
	assert_eq(b.hand[0].faces, [2, 3, 3, 4, 4, 5] as Array[int])
	assert_eq(b.hand[0].type_id, "d6", "it's still drawn as the table's die")
	assert_true(b.hand[0].value in [2, 3, 4, 5])
	for i: int in range(1, 4):
		assert_eq(b.hand[i].value, a.hand[i].value, "die %d rolls the same with or without the change" % i)


func test_a_kit_survives_json_exactly() -> void:
	var state: GameState = _state(["pearl_diver", "shipwright"] as Array[String])
	state.build(data, "cottage", Vector2i(0, 7))
	var kit: Kit = Kit.build(data, state)
	kit.dice[0]["faces"] = [2, 3, 3, 4, 4, 5] as Array[int]
	var again: Kit = Kit.from_dict(data, JSON.parse_string(JSON.stringify(kit.to_dict())))
	assert_not_null(again)
	assert_eq(again.to_dict(), kit.to_dict())
	assert_eq(again.dice[0]["faces"], [2, 3, 3, 4, 4, 5] as Array[int], "faces come back as ints")


func test_from_dict_is_strict() -> void:
	var good: Dictionary = JSON.parse_string(JSON.stringify(Kit.fresh(data,
		[{"perk": "brace", "source": "shipwright"}] as Array[Dictionary]).to_dict()))
	assert_not_null(Kit.from_dict(data, good))
	var cases: Dictionary[String, Callable] = {
		"no dice": func(d: Dictionary) -> void: d["dice"] = [],
		"unknown die type": func(d: Dictionary) -> void: d["dice"][0]["type"] = "d99",
		"a zero face": func(d: Dictionary) -> void: d["dice"][0]["faces"][0] = 0,
		"a fractional face": func(d: Dictionary) -> void: d["dice"][0]["faces"][0] = 2.5,
		"no faces": func(d: Dictionary) -> void: d["dice"][0]["faces"] = [],
		"missing source": func(d: Dictionary) -> void: (d["dice"][0] as Dictionary).erase("source"),
		"unknown perk": func(d: Dictionary) -> void: d["perks"][0]["perk"] = "ghost",
		"negative amount": func(d: Dictionary) -> void: d["perks"][0]["amount"] = -1,
		"missing happy": func(d: Dictionary) -> void: (d["perks"][0] as Dictionary).erase("happy"),
		"perks not a list": func(d: Dictionary) -> void: d["perks"] = {},
	}
	for name: String in cases:
		var bad: Dictionary = good.duplicate(true)
		cases[name].call(bad)
		assert_null(Kit.from_dict(data, bad), name)


func test_a_delve_replays_from_its_logged_kit() -> void:
	var kit: Kit = Kit.fresh(data, [{"perk": "brace", "source": "shipwright", "happy": true}] as Array[Dictionary])
	kit.dice[2]["faces"] = [2, 3, 3, 4, 4, 5] as Array[int]
	var run: DelveRun = DelveRun.create(data, 31, kit, VILLAGERS, LANDMARKS, 0)
	assert_true(run.choose(run.reachable()[0]))
	var logged: Dictionary = JSON.parse_string(JSON.stringify(run.kit.to_dict()))
	var again: DelveRun = DelveRun.replay(data, 31, Kit.from_dict(data, logged), VILLAGERS, LANDMARKS, run.choices, 0)
	assert_not_null(again)
	assert_eq(again._rng.to_dict(), run._rng.to_dict())
	if run.fight != null:
		assert_eq(again.fight.hand.map(func(d: DiceTable.Die) -> int: return d.value),
			run.fight.hand.map(func(d: DiceTable.Die) -> int: return d.value))
		assert_eq(again.fight.player_block, 3)


func test_a_delve_needs_a_kit() -> void:
	assert_null(DelveRun.create(data, 1, null, VILLAGERS, LANDMARKS, 0))
