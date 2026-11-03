class_name DelveRun
extends RefCounted
## One delve in progress (specs/delve-map.md sections 1, 4 and 8a): where
## you are on the map, your HP and your haul, and the room being played.
##
## The flow is a few moves, each returning false and changing nothing when
## it isn't allowed:
##   choose(col)    walk into a room in the next row (CHOOSE_ROOM)
##   finish_room()  once the room's own play is over (IN_ROOM)
##   surface()      leave with the whole haul (LANDING)
##   go_deeper()    on to the next floor (LANDING)
## After the last row of the last floor the run waits at Koban's vault.
##
## Screens and bots read a RunView, never the map: the view hides what the
## player can't see yet.
##
## Randomness: the map comes from its own seed (DelveMap). The run's streams
## are seeded with the delve seed: ENEMIES picks who's in a fight room when
## you walk in, ROLLS rolls the dice, and LOOT pays out when a room is
## cleared. `choices` records every choice and each room's moves, so the seed,
## the perks, the pools and the choices replay a whole delve (replay()).
##
## Not built yet: treasure, rest and rescue rooms are placeholders that pay
## nothing (the rooms PR), and the vault is a stop (the vault PR).

enum Step { CHOOSE_ROOM, IN_ROOM, LANDING, VAULT, SURFACED, WASHED_UP, CLEARED }

const LOADOUT: String = "fresh"
const FORESIGHT_PERK: String = "foresight"

var map: DelveMap
var step: Step = Step.CHOOSE_ROOM
var floor_index: int = 0
## The row of the last room played on this floor, or -1 before the first.
var row: int = -1
var col: int = -1
var hp: int = 0
var max_hp: int = 0
var haul: Haul = Haul.new()
## The room being played: its type, and the fight for fight and elite rooms.
var room_type: String = ""
var fight: Fight
## Rooms walked into, in order, as [floor, row, col].
var path: Array[Array] = []
## What the last cleared room paid: {resource id: amount}.
var last_loot: Dictionary[String, int] = {}
## Every choice in order: {"choose": col}, {"room": [moves]}, {"landing": "surface" | "deeper"}.
var choices: Array[Dictionary] = []
## Rows of room types the player sees ahead of the current row.
var reveal_rows: int = 2
## The Foresight perk: one more row revealed, and a deeper landing peek.
var foresight: bool = false

var delve_seed: int = 0
var perks: Array[Dictionary] = []
var _data: GameData
var _rng: RngStreams


## Starts a delve with full HP and an empty haul. `perks` is the list Fight
## takes ({"perk": id, "source": id}). Returns null if the data is missing.
static func create(data: GameData, seed_value: int, with_perks: Array[Dictionary],
		villagers_left: Array[String], landmarks_left: Array[String]) -> DelveRun:
	if not data.has_row("loadouts", LOADOUT) or not data.has_row("delve", "slice"):
		return null
	var run: DelveRun = DelveRun.new()
	run._data = data
	run.delve_seed = seed_value
	run.perks = with_perks.duplicate(true)
	run._rng = RngStreams.new(seed_value)
	run.map = DelveMap.generate(data, seed_value, villagers_left, landmarks_left)
	run.max_hp = data.row("loadouts", LOADOUT)["hp"] as int
	run.hp = run.max_hp
	run.reveal_rows = data.row("delve", "slice")["reveal_rows"] as int
	for entry: Dictionary in with_perks:
		if str(entry.get("perk", "")) == FORESIGHT_PERK and not run.foresight:
			run.foresight = true
			run.reveal_rows += 1
	return run


## Rebuilds a delve from its inputs and log. Returns null if any logged
## move is refused (a log that doesn't match the seed, data or pools).
static func replay(data: GameData, seed_value: int, with_perks: Array[Dictionary],
		villagers_left: Array[String], landmarks_left: Array[String], moves: Array[Dictionary]) -> DelveRun:
	var run: DelveRun = create(data, seed_value, with_perks, villagers_left, landmarks_left)
	if run == null:
		return null
	for entry: Dictionary in moves:
		var ok: bool = false
		if entry.has("choose"):
			ok = run.choose(int(entry["choose"]))
		elif entry.has("room"):
			var room_moves: Array[Dictionary] = []
			room_moves.assign(entry["room"] as Array)
			ok = (run.fight == null or run.fight.apply_moves(room_moves)) and run.finish_room()
		elif entry.has("landing"):
			ok = run.surface() if str(entry["landing"]) == "surface" else run.go_deeper()
		if not ok:
			return null
	return run


## Regular enemies or the elite, in data order.
static func enemy_pool(data: GameData, tier: String) -> Array[String]:
	var pool: Array[String] = []
	for id: String in data.ids("enemies"):
		if data.row("enemies", id)["tier"] == tier:
			pool.append(id)
	return pool


func is_over() -> bool:
	return step in [Step.SURFACED, Step.WASHED_UP, Step.CLEARED]


## Columns in the next row you can walk into now.
func reachable() -> Array[int]:
	var out: Array[int] = []
	if step != Step.CHOOSE_ROOM:
		return out
	if row < 0:
		for c: int in map.width(floor_index, 0):
			out.append(c)
	else:
		out.assign(map.room(floor_index, row, col).links)
	return out


## Rooms left before the landing (or the vault), counting the next one.
func rooms_to_landing() -> int:
	return map.rows_in_floor(floor_index) - 1 - row


## Walks into a room. A fight room whose fight can't be built (no enemy of
## its tier in the data) is refused with an error, never entered empty.
func choose(next_col: int) -> bool:
	if not reachable().has(next_col):
		return false
	var next_type: String = map.room(floor_index, row + 1, next_col).type
	var entry: Dictionary = {"choose": next_col}
	var next_fight: Fight = null
	if is_fight_room(next_type):
		var tier: String = "elite" if next_type == DelveMap.ELITE else "regular"
		var pool: Array[String] = enemy_pool(_data, tier)
		if pool.is_empty():
			push_error("DelveRun: no %s enemy for a %s room" % [tier, next_type])
			return false
		var enemy_id: String = pool[_rng.index(RngStreams.Stream.ENEMIES, pool.size())]
		next_fight = Fight.create(_data, LOADOUT, enemy_id, _rng, perks, hp)
		if next_fight == null:
			push_error("DelveRun: can't build a fight against \"%s\" at %d HP" % [enemy_id, hp])
			return false
		# Who you meet depends on the path, so logs name them (replay ignores it).
		entry["enemy"] = enemy_id
	row += 1
	col = next_col
	path.append([floor_index, row, col])
	choices.append(entry)
	step = Step.IN_ROOM
	room_type = next_type
	fight = next_fight
	last_loot = {}
	return true


static func is_fight_room(type: String) -> bool:
	return type == DelveMap.FIGHT or type == DelveMap.ELITE


## Ends the room once its play is over: a fight room needs its fight won or
## lost. A win pays loot and moves on; a loss washes up in the barrel.
func finish_room() -> bool:
	if step != Step.IN_ROOM:
		return false
	if is_fight_room(room_type):
		if fight == null or fight.state == Fight.State.PLAYER_TURN:
			return false
		choices.append({"room": fight.moves.duplicate(true)})
		hp = fight.player_hp
		var won: bool = fight.state == Fight.State.WON
		fight = null
		if not won:
			step = Step.WASHED_UP
			return true
	else:
		choices.append({"room": []})
	_pay_loot(room_type)
	if row < map.rows_in_floor(floor_index) - 1:
		step = Step.CHOOSE_ROOM
	elif floor_index < map.floors.size() - 1:
		step = Step.LANDING
	else:
		step = Step.VAULT
	return true


## Leaves from a landing with the whole haul.
func surface() -> bool:
	if step != Step.LANDING:
		return false
	choices.append({"landing": "surface"})
	step = Step.SURFACED
	return true


func go_deeper() -> bool:
	if step != Step.LANDING:
		return false
	choices.append({"landing": "deeper"})
	floor_index += 1
	row = -1
	col = -1
	step = Step.CHOOSE_ROOM
	return true


## How the delve ended, as a Haul outcome, or "" while it's still going.
func outcome() -> String:
	match step:
		Step.SURFACED:
			return Haul.SURFACED
		Step.CLEARED:
			return Haul.CLEARED
		Step.WASHED_UP:
			return Haul.WASHED_UP
	return ""


## What the town gets (Haul.kept): nothing while the delve is still going.
func kept_haul() -> Haul:
	return haul.kept(outcome())


func _pay_loot(paid_room: String) -> void:
	for id: String in _data.ids("loot"):
		var loot: Dictionary = _data.row("loot", id)
		if loot["room"] != paid_room:
			continue
		if _rng.range_int(RngStreams.Stream.LOOT, 1, 100) > (loot["chance_percent"] as int):
			continue
		var amount: int = _rng.range_int(RngStreams.Stream.LOOT, loot["min"] as int, loot["max"] as int)
		if haul.add_resource(loot["resource"], amount):
			last_loot[loot["resource"] as String] = last_loot.get(loot["resource"], 0) + amount
