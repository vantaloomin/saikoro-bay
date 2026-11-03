extends GutTest
## A delve in progress (specs/delve-map.md sections 1, 4 and 8a): moving
## through the map, HP and haul, loot, landings, replay, and the view.

const VILLAGERS: Array[String] = ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]
const LANDMARKS: Array[String] = ["cafe", "hot_spring"]
const FORESIGHT: Array[Dictionary] = [{"perk": "foresight", "source": "shrine_keeper"}]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _run(seed_value: int = 11, perks: Array[Dictionary] = []) -> DelveRun:
	var run: DelveRun = DelveRun.create(data, seed_value, perks, VILLAGERS, LANDMARKS)
	assert_not_null(run)
	return run


## Plays with the greedy bot, taking the leftmost room and always going
## deeper, until the vault, a wash-up, or `stop_at` is reached.
func _play(run: DelveRun, stop_at: DelveRun.Step = DelveRun.Step.VAULT) -> void:
	var bot: GreedyBot = GreedyBot.new()
	for guard: int in 200:
		if run.is_over() or run.step == stop_at:
			return
		match run.step:
			DelveRun.Step.CHOOSE_ROOM:
				run.choose(run.reachable()[0])
			DelveRun.Step.IN_ROOM:
				if run.fight != null:
					bot.play_fight(run.fight)
				assert_true(run.finish_room())
			DelveRun.Step.LANDING:
				run.go_deeper()
			_:
				return


func test_a_delve_starts_at_full_hp_with_an_empty_haul() -> void:
	var run: DelveRun = _run()
	assert_eq(run.step, DelveRun.Step.CHOOSE_ROOM)
	assert_eq(run.hp, 30)
	assert_true(run.haul.is_empty())
	assert_eq(run.reachable().size(), run.map.width(0, 0), "any room of the first row")
	assert_eq(run.rooms_to_landing(), 3)


func test_you_can_only_walk_into_linked_rooms() -> void:
	var run: DelveRun = _run()
	assert_false(run.choose(5))
	assert_true(run.choose(0))
	assert_false(run.choose(0), "finish the room first")
	assert_eq(run.room_type, DelveMap.FIGHT, "the delve opens on a fight")
	assert_true(DelveRun.enemy_pool(data, "regular").has(run.fight.enemy_id))
	assert_false(run.finish_room(), "not while the fight is on")
	GreedyBot.new().play_fight(run.fight)
	assert_true(run.finish_room())
	assert_eq(run.reachable(), run.map.room(0, 0, 0).links)


func test_hp_carries_from_room_to_room() -> void:
	var run: DelveRun = _run()
	run.choose(0)
	GreedyBot.new().play_fight(run.fight)
	var left: int = run.fight.player_hp
	run.finish_room()
	assert_eq(run.hp, left)
	var next: int = run.reachable()[0]
	run.choose(next)
	if run.fight != null:
		assert_eq(run.fight.player_hp, left, "the next fight starts where the last one ended")


func test_won_fights_pay_loot_from_the_table() -> void:
	var paid: int = 0
	for s: int in range(1, 31):
		var run: DelveRun = _run(s)
		run.choose(0)
		GreedyBot.new().play_fight(run.fight)
		var won: bool = run.fight.state == Fight.State.WON
		run.finish_room()
		if not won:
			continue
		paid += 1
		assert_between(run.haul.resource("driftwood"), 3, 6, "seed %d" % s)
		assert_between(run.haul.resource("pearls"), 0, 1)
		assert_eq(run.last_loot, run.haul.resources)
	assert_gt(paid, 20)


func _without_the_elite() -> GameData:
	var texts: Dictionary[String, String] = {}
	for table: String in GameData.TABLES:
		texts[table] = FileAccess.get_file_as_string("res://data/%s.json" % table)
	var enemies: Dictionary = JSON.parse_string(texts["enemies"])
	enemies["items"] = (enemies["items"] as Array).filter(func(e: Dictionary) -> bool: return e["tier"] != "elite")
	texts["enemies"] = JSON.stringify(enemies)
	var broken: GameData = GameData.new()
	broken.load_texts(texts)
	return broken


func test_data_needs_an_enemy_of_every_tier() -> void:
	assert_has(_without_the_elite().errors, "enemies: needs at least one elite enemy")


func test_a_fight_room_without_a_fight_is_refused_not_paid() -> void:
	var run: DelveRun = DelveRun.create(_without_the_elite(), 11, [], VILLAGERS, LANDMARKS)
	run.map.room(0, 0, 0).type = DelveMap.ELITE
	assert_false(run.choose(0), "no elite to fight: the room isn't entered")
	assert_push_error("no elite enemy")
	assert_eq(run.step, DelveRun.Step.CHOOSE_ROOM)
	assert_eq(run.row, -1)
	assert_true(run.haul.is_empty())
	assert_eq(run.choices, [] as Array[Dictionary])


func test_a_fight_room_only_finishes_with_its_fight_over() -> void:
	var run: DelveRun = _run()
	run.choose(0)
	run.fight = null
	assert_false(run.finish_room(), "keyed on the room type, not on whether a fight exists")
	assert_true(run.haul.is_empty())


func test_choices_name_the_enemy_met() -> void:
	var run: DelveRun = _run()
	run.choose(0)
	assert_eq(run.choices[0], {"choose": 0, "enemy": run.fight.enemy_id})


func test_the_elite_pool_holds_only_the_elite() -> void:
	assert_eq(DelveRun.enemy_pool(data, "elite"), ["pit_boss_octopus"] as Array[String])
	assert_false(DelveRun.enemy_pool(data, "regular").has("pit_boss_octopus"))


func test_landings_come_after_each_floor_and_the_vault_after_the_last() -> void:
	var reached: Dictionary[DelveRun.Step, int] = {}
	for s: int in range(1, 41):
		var run: DelveRun = _run(s)
		_play(run, DelveRun.Step.LANDING)
		reached[run.step] = reached.get(run.step, 0) + 1
		if run.step == DelveRun.Step.LANDING:
			assert_eq(run.row, run.map.rows_in_floor(0) - 1)
			assert_eq(run.reachable(), [] as Array[int], "a landing is the only way on")
			assert_false(run.choose(0))
			assert_true(run.go_deeper())
			assert_eq(run.floor_index, 1)
			assert_eq(run.row, -1)
			_play(run)
			if not run.is_over():
				assert_eq(run.step, DelveRun.Step.VAULT)
				assert_eq(run.floor_index, run.map.floors.size() - 1)
	assert_gt(reached.get(DelveRun.Step.LANDING, 0), 0)


func test_surfacing_keeps_the_whole_haul() -> void:
	var run: DelveRun = _run(3)
	_play(run, DelveRun.Step.LANDING)
	if run.step != DelveRun.Step.LANDING:
		pass_test("washed up on floor 1 on this seed")
		return
	var carried: Dictionary = run.haul.to_dict()
	assert_true(run.kept_haul().is_empty(), "nothing is banked until you leave")
	assert_true(run.surface())
	assert_true(run.is_over())
	assert_eq(run.kept_haul().to_dict(), carried)
	assert_false(run.go_deeper())


func test_washing_up_keeps_half_of_each_resource_rounded_down() -> void:
	var haul: Haul = Haul.new()
	haul.add_resource("driftwood", 7)
	haul.add_resource("pearls", 1)
	haul.add_resource("koban_coins", 4)
	haul.villagers.append("pearl_diver")
	haul.landmark = "cafe"
	assert_eq(haul.halved().to_dict(), {"resources": {"driftwood": 3, "koban_coins": 2}, "villagers": [], "landmark": ""})
	for s: int in range(1, 200):
		var run: DelveRun = _run(s)
		_play(run)
		if run.step == DelveRun.Step.WASHED_UP:
			assert_eq(run.kept_haul().to_dict(), run.haul.halved().to_dict())
			assert_eq(run.hp, 0)
			return
	fail_test("no seed washed up")


func test_nothing_is_kept_mid_delve() -> void:
	var run: DelveRun = _run()
	run.choose(0)
	assert_true(run.kept_haul().is_empty())


func test_placeholder_rooms_pass_without_paying() -> void:
	for s: int in range(1, 60):
		var run: DelveRun = _run(s)
		_play(run, DelveRun.Step.LANDING)
		for i: int in run.path.size():
			var p: Array = run.path[i]
			var type: String = run.map.room(p[0], p[1], p[2]).type
			if type in [DelveMap.TREASURE, DelveMap.REST, DelveMap.RESCUE]:
				assert_eq(run.choices.filter(func(e: Dictionary) -> bool: return e.has("room"))[i]["room"], [], "no moves in a placeholder")
				return
	fail_test("no placeholder room reached")


func test_the_same_seed_plays_the_same_delve() -> void:
	var a: DelveRun = _run(21)
	var b: DelveRun = _run(21)
	_play(a)
	_play(b)
	assert_eq(a.choices, b.choices)
	assert_eq(a.haul.to_dict(), b.haul.to_dict())
	assert_eq(a.hp, b.hp)


func test_a_delve_replays_from_its_choices() -> void:
	for s: int in range(1, 16):
		var run: DelveRun = _run(s)
		_play(run, DelveRun.Step.LANDING)
		if run.step == DelveRun.Step.LANDING:
			run.go_deeper()
			_play(run)
		var again: DelveRun = DelveRun.replay(data, s, [], VILLAGERS, LANDMARKS, run.choices)
		assert_not_null(again, "seed %d replays" % s)
		assert_eq(again.step, run.step)
		assert_eq(again.hp, run.hp)
		assert_eq(again.path, run.path)
		assert_eq(again.haul.to_dict(), run.haul.to_dict())


func test_a_log_that_doesnt_match_is_refused() -> void:
	var bad: Array[Dictionary] = [{"choose": 0}, {"choose": 1}]
	assert_null(DelveRun.replay(data, 1, [], VILLAGERS, LANDMARKS, bad))


# --- The view --------------------------------------------------------------------

func test_the_view_hides_rows_beyond_the_reveal() -> void:
	var view: RunView = RunView.new(_run())
	var rows: Array = view.rows()
	for r: int in rows.size():
		for room: Dictionary in rows[r] as Array:
			if r < 2:
				assert_ne(room["type"], RunView.HIDDEN, "row %d shows" % r)
			else:
				assert_eq(room["type"], RunView.HIDDEN, "row %d is hidden" % r)
	var ahead: RunView = RunView.new(_run(11, FORESIGHT))
	assert_true(ahead.has_foresight())
	for room: Dictionary in ahead.rows()[2] as Array:
		assert_ne(room["type"], RunView.HIDDEN, "Foresight shows a third row")


func test_hidden_rooms_never_change_the_view() -> void:
	for s: int in range(1, 21):
		var run: DelveRun = _run(s)
		if s % 2 == 0:
			_play(run, DelveRun.Step.LANDING)
		_assert_hidden_rooms_dont_show(run, "seed %d" % s)
		var ahead: DelveRun = _run(s, FORESIGHT)
		if s % 2 == 0:
			_play(ahead, DelveRun.Step.LANDING)
		_assert_hidden_rooms_dont_show(ahead, "seed %d with Foresight" % s)


## Changes everything the player can't see yet (room types, and the rescue
## villager and vault prize where they aren't shown) and checks the view
## doesn't move.
func _assert_hidden_rooms_dont_show(run: DelveRun, label: String) -> void:
	var before: Dictionary = RunView.new(run).to_dict()
	var revealed_to: int = run.row + run.reveal_rows
	var peek_rows: int = 2 if run.foresight else 1
	var rescue_shown: bool = false
	for rm: DelveMap.Room in run.map.all_rooms():
		var hidden: bool = rm.floor_index > run.floor_index or (rm.floor_index == run.floor_index and rm.row > revealed_to)
		var peeked: bool = run.step == DelveRun.Step.LANDING and rm.floor_index == run.floor_index + 1 and rm.row < peek_rows
		if hidden and not peeked:
			rm.type = DelveMap.ELITE if rm.type != DelveMap.ELITE else DelveMap.REST
		elif rm.type == DelveMap.RESCUE:
			rescue_shown = true
	var rescue_peeked: bool = run.step == DelveRun.Step.LANDING and run.floor_index + 1 == DelveMap.RESCUE_FLOOR
	if not rescue_shown and not rescue_peeked:
		run.map.rescue_villager = "someone_else"
	var vault_peeked: bool = run.step == DelveRun.Step.LANDING and run.floor_index + 1 == run.map.floors.size() - 1
	if run.floor_index < run.map.floors.size() - 1 and not vault_peeked:
		run.map.vault_prize = {"landmark": "somewhere_else"}
	assert_eq(RunView.new(run).to_dict(), before, label)


func test_room_states_follow_the_paths() -> void:
	var run: DelveRun = _run(5)
	var view: RunView = RunView.new(run)
	for room: Dictionary in view.rows()[0] as Array:
		assert_eq(room["state"], "next")
	run.choose(0)
	assert_eq((view.rows()[0] as Array)[0]["state"], "current")
	if run.map.width(0, 0) > 1:
		assert_eq((view.rows()[0] as Array)[1]["state"], "closed", "the other first-row room is behind you")
	GreedyBot.new().play_fight(run.fight)
	run.finish_room()
	for room: Dictionary in view.rows()[1] as Array:
		var linked: bool = run.map.room(0, 0, 0).links.has(room["col"] as int)
		assert_eq(room["state"], "next" if linked else "closed", "row 1 col %d" % room["col"])


func test_the_landing_peeks_at_the_next_floor_and_its_prize() -> void:
	for s: int in range(1, 41):
		var run: DelveRun = _run(s, FORESIGHT)
		_play(run, DelveRun.Step.LANDING)
		if run.step != DelveRun.Step.LANDING:
			continue
		var peek: Dictionary = RunView.new(run).peek()
		assert_eq(peek["floor"], 1)
		assert_eq((peek["rows"] as Array).size(), 2, "Foresight peeks two rows")
		assert_eq(peek["prize"], {"rescue": "pearl_diver"})
		run.go_deeper()
		assert_eq(RunView.new(run).peek(), {}, "only at a landing")
		assert_eq(RunView.new(run).vault_prize(), {}, "not before the last floor")
		return
	fail_test("no seed reached a landing")


func test_the_enemy_shows_only_once_you_walk_in() -> void:
	var run: DelveRun = _run()
	var view: RunView = RunView.new(run)
	assert_eq(view.current_enemy(), "")
	run.choose(0)
	assert_eq(view.current_enemy(), run.fight.enemy_id)


func test_loot_rows_are_checked_at_load() -> void:
	var texts: Dictionary[String, String] = {}
	for table: String in GameData.TABLES:
		texts[table] = FileAccess.get_file_as_string("res://data/%s.json" % table)
	texts["loot"] = JSON.stringify({"schema": 1, "items": [
		{"id": "a", "room": "fight", "resource": "driftwood", "chance_percent": 150, "min": 1, "max": 2},
		{"id": "b", "room": "fight", "resource": "driftwood", "chance_percent": 50, "min": 3, "max": 2},
		{"id": "c", "room": "fight", "resource": "sand", "chance_percent": 50, "min": 1, "max": 2},
	]})
	var broken: GameData = GameData.new()
	broken.load_texts(texts)
	var all: String = "\n".join(broken.errors)
	assert_string_contains(all, "loot \"a\": chance_percent must be 0 to 100")
	assert_string_contains(all, "loot \"b\": needs 0 <= min <= max")
	assert_string_contains(all, "missing resources \"sand\"")
