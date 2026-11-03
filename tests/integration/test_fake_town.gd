extends GutTest
## The M3 exit check's fake town: a real town reached through the sim's
## own moves, with a full budget, things to spend it on and a landmark
## waiting, in a save slot of its own.

var _state: GameState
var _store: SaveStore
var _problem: String


func before_each() -> void:
	_state = Game.state
	_store = Game.store
	_problem = Game.save_problem


func after_each() -> void:
	SaveStore.new(FakeTown.SAVE_PATH).erase()
	Game.state = _state
	Game.store = _store
	Game.save_problem = _problem


func test_the_fake_town_is_a_town_the_game_could_reach() -> void:
	var data: GameData = Game.data
	var state: GameState = FakeTown.build(data)
	assert_not_null(state, "every sim move it makes is allowed")
	assert_eq(state.phase, GameState.Phase.TOWN)
	assert_eq(state.town.actions_left, 5, "four fresh actions and one kept")
	assert_eq(state.town.kept, 1)
	assert_eq(state.landmarks_waiting(), ["hot_spring"] as Array[String], "a landmark to place for free")
	assert_eq(state.homeless().size(), 1, "one villager on the dock, for the Cottage shortcut")
	assert_true(state.town_problems(data).is_empty())
	var buildable: int = 0
	for entry: Dictionary in BuildList.entries(data, state):
		buildable += 1 if entry["can_place"] else 0
	assert_gt(buildable, 2, "several things to spend the visit on")
	assert_true(GameState.from_dict(state.to_dict()) != null, "and it saves")


func test_it_plays_in_its_own_slot_and_starts_fresh() -> void:
	var real: SaveStore = Game.store
	var scene: String = Game.load_or_new(true)
	assert_eq(scene, Game.TOWN_SCENE)
	assert_ne(Game.store, real, "the real slot is never touched")
	assert_eq(Game.store.path, FakeTown.SAVE_PATH)
	assert_eq(Game.save_problem, FakeTown.NOTICE, "the notice board says it's a test town")
	Game.state.add_resource("driftwood", 50)
	Game.save()
	Game.load_or_new(true)
	assert_eq(Game.state.resource("driftwood"), FakeTown.HAUL_RESOURCES["driftwood"], "fresh on every launch")


func test_it_needs_the_flag() -> void:
	assert_false(FakeTown.requested(), "a plain launch is the real game")
