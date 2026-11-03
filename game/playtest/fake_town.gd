class_name FakeTown
extends RefCounted
## A town with made-up resources, for the M3 exit check: "a tester can
## spend a town visit with fake resources and understand every action's
## cost without help" (vertical slice plan, M3).
##
## Debug builds only: run the project with `-- --fake-town`. It plays in
## its own save slot, so the real campaign is never touched, and it starts
## fresh on every launch so each tester gets the same town. It's built
## through the sim's real moves (a first visit, one delve cleared), not by
## writing fields, so it's a town the game could really reach.

const ARG: String = "--fake-town"
const SAVE_PATH: String = "user://saves/fake_town.save"
const NOTICE: String = "Test town: made-up resources, saved apart from your real game."
const SEED: int = 3031
## The first visit: two Cottages on the sea-side lots.
const FIRST_HOMES: Array[Vector2i] = [Vector2i(0, 7), Vector2i(2, 5)]
## What the cleared delve brought up.
const HAUL_RESOURCES: Dictionary[String, int] = {"driftwood": 20, "pearls": 4, "koban_coins": 2}
const HAUL_VILLAGERS: Array[String] = ["pearl_diver", "shipwright", "onsen_keeper"]
const HAUL_LANDMARK: String = "hot_spring"


## Whether this launch asked for the fake town, in a build that allows it.
static func requested() -> bool:
	return OS.is_debug_build() and ARG in OS.get_cmdline_user_args()


## The fake town, standing in town after its second arrival: three
## villagers (two housed, one on the dock), the Hot Spring waiting, and a
## full budget with one action kept from the first visit. Null if a sim
## move refused, which a test catches.
static func build(data: GameData) -> GameState:
	var state: GameState = GameState.new(SEED)
	state.arrive(data)
	state.add_resource("driftwood", 4 * FIRST_HOMES.size())
	for cell: Vector2i in FIRST_HOMES:
		if not state.build(data, "cottage", cell).is_empty():
			return null
	if not state.start_delve(data):
		return null
	var haul: Haul = Haul.new()
	for id: String in HAUL_RESOURCES:
		haul.add_resource(id, HAUL_RESOURCES[id])
	haul.villagers.assign(HAUL_VILLAGERS)
	haul.landmark = HAUL_LANDMARK
	if not state.finish_delve(data, Haul.CLEARED, haul):
		return null
	return state
