extends GutTest
## The action budget's lifecycle (specs/town.md section 4, PR 3): arrival
## sets it once, "Go down" keeps one and loses the rest in the same state
## change, and an abandoned delve gives back what you had.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _arrived() -> GameState:
	var state: GameState = GameState.new(21)
	assert_true(state.arrive(data))
	return state


func _come_up(state: GameState, outcome: String = Haul.SURFACED) -> void:
	assert_true(state.finish_delve(data, outcome, Haul.new()))


func test_a_new_campaign_arrives_with_the_base_budget_once() -> void:
	var state: GameState = GameState.new(21)
	assert_true(state.town.needs_budget)
	assert_true(state.arrive(data))
	assert_eq([state.town.actions_left, state.town.kept, state.town.needs_budget], [4, 0, false])
	state.town.actions_left = 1
	assert_false(state.arrive(data), "arriving twice changes nothing")
	assert_eq(state.town.actions_left, 1)


func test_go_down_keeps_one_and_the_rest_are_lost() -> void:
	var state: GameState = _arrived()
	state.town.actions_left = 3
	assert_eq(state.go_down_label(data), "Go down · keep 1, 2 are lost")
	assert_true(state.start_delve(data))
	assert_eq([state.town.actions_left, state.town.kept, state.town.held_at_go_down], [0, 1, 3])
	_come_up(state)
	assert_eq([state.town.actions_left, state.town.kept], [5, 1], "4 fresh and the kept one")
	assert_eq(state.town.held_at_go_down, 0)


func test_go_down_with_nothing_left_keeps_nothing() -> void:
	var state: GameState = _arrived()
	state.town.actions_left = 0
	assert_eq(state.go_down_label(data), "Go down")
	state.start_delve(data)
	_come_up(state, Haul.WASHED_UP)
	assert_eq([state.town.actions_left, state.town.kept], [4, 0])


func test_the_go_down_label_says_what_is_lost() -> void:
	var state: GameState = _arrived()
	var labels: Array[String] = []
	for left: int in [1, 2, 4]:
		state.town.actions_left = left
		labels.append(state.go_down_label(data))
	assert_eq(labels, ["Go down · keep 1", "Go down · keep 1, 1 is lost", "Go down · keep 1, 3 are lost"] as Array[String])


func test_an_abandoned_delve_gives_back_the_actions_and_the_map() -> void:
	var state: GameState = _arrived()
	state.town.actions_left = 3
	state.start_delve(data)
	var seed_down: int = state.current_delve_seed()
	_come_up(state, Haul.ABANDONED)
	assert_eq([state.town.actions_left, state.town.kept], [3, 1], "what you had at Go down, no more")
	assert_eq(state.last_delve["outcome"], Haul.ABANDONED)
	assert_eq(state.delve_count, 0)
	state.start_delve(data)
	assert_eq(state.current_delve_seed(), seed_down, "the same delve again")
	_come_up(state)
	assert_eq([state.town.actions_left, state.delve_count], [5, 1], "a real delve counts")


func test_an_abandon_before_any_budget_arrives_normally() -> void:
	var state: GameState = GameState.new(21)
	state.start_delve(data)
	_come_up(state, Haul.ABANDONED)
	assert_eq(state.town.actions_left, 4, "a save from before the town gets one budget")
	assert_false(state.town.needs_budget)


func test_the_budget_survives_a_save_mid_delve() -> void:
	var state: GameState = _arrived()
	state.town.actions_left = 2
	state.start_delve(data)
	var loaded: GameState = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(loaded.town_problems(data), PackedStringArray())
	assert_eq([loaded.town.kept, loaded.town.held_at_go_down], [1, 2])
	assert_true(loaded.finish_delve(data, Haul.SURFACED, Haul.new()))
	assert_eq(loaded.town.actions_left, 5)


func test_impossible_budgets_are_caught_on_load() -> void:
	var state: GameState = _arrived()
	state.town.kept = 1
	state.town.actions_left = 0
	assert_gt(state.town_problems(data).size(), 0, "more kept than left in town")
	state = _arrived()
	state.start_delve(data)
	state.town.actions_left = 2
	assert_gt(state.town_problems(data).size(), 0, "actions left during a delve")


## Imogen's #39 audit: a retry after an abandon has the same map, but the
## rolls, enemies and loot are fresh, so quitting can't show what's coming.
func test_a_retry_keeps_the_map_but_rolls_afresh() -> void:
	var state: GameState = _arrived()
	state.start_delve(data)
	var first: DelveRun = DelveRun.create(data, state.current_delve_seed(), [], state.villagers_left(data),
		state.landmarks_left(data), state.delve_attempt)
	_come_up(state, Haul.ABANDONED)
	assert_eq(state.delve_attempt, 1)
	var saved: GameState = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(saved.delve_attempt, 1, "the attempt is saved")
	state.start_delve(data)
	var retry: DelveRun = DelveRun.create(data, state.current_delve_seed(), [], state.villagers_left(data),
		state.landmarks_left(data), state.delve_attempt)
	assert_eq(retry.map.describe(), first.map.describe(), "the same map")
	assert_eq(retry.map.inputs(), first.map.inputs())
	var first_rolls: Array[int] = []
	var retry_rolls: Array[int] = []
	for i: int in 20:
		first_rolls.append(first._rng.die_index(i % 4, 6))
		retry_rolls.append(retry._rng.die_index(i % 4, 6))
	assert_ne(retry_rolls, first_rolls, "different rolls")
	assert_ne(DelveRun.run_seed(first.delve_seed, 1), DelveRun.run_seed(first.delve_seed, 2))
	_come_up(state)
	assert_eq(state.delve_attempt, 0, "a real outcome starts the count again")


func test_a_retry_replays_from_its_attempt() -> void:
	var run: DelveRun = DelveRun.create(data, 99, [], ["pearl_diver"] as Array[String], ["cafe"] as Array[String], 2)
	assert_eq(run.attempt, 2)
	assert_true(run.choose(run.reachable()[0]))
	var again: DelveRun = DelveRun.replay(data, 99, [], ["pearl_diver"] as Array[String], ["cafe"] as Array[String],
		run.choices, 2)
	assert_not_null(again)
	assert_eq(again._rng.to_dict(), run._rng.to_dict(), "same seed, same attempt, same streams")
