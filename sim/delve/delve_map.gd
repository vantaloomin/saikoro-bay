class_name DelveMap
extends RefCounted
## One delve's map (specs/delve-map.md sections 2 and 8a): floors of rows of
## rooms, linked downward without crossings, with a landing after each floor
## and Koban's vault at the bottom.
##
## The whole map is drawn when the delve starts, from the MAP stream, so a
## landing's peek can never show something that changes later. Generation
## is a pipeline: links, then constrained rooms, then fill by weight, then
## one validator (map_errors). A map that fails is redrawn from a fresh
## sub-seed, a bounded number of times, and a fixed template is the last
## resort. Maps are never saved: a delve rebuilds its map from the seed.

const FIGHT: String = "fight"
const ELITE: String = "elite"
const TREASURE: String = "treasure"
const REST: String = "rest"
const RESCUE: String = "rescue"
const VAULT: String = "vault"

## The floor (0-based) that holds the rescue, and the one that holds the elite.
const RESCUE_FLOOR: int = 1
const ELITE_FLOOR: int = 2


class Room:
	extends RefCounted
	var floor_index: int
	var row: int
	var col: int
	var type: String = ""
	## Columns this room links to in the next row of the same floor. The
	## last row of a floor links to the landing instead (empty here).
	var links: Array[int] = []

	func _init(f: int, r: int, c: int) -> void:
		floor_index = f
		row = r
		col = c


## floors[f][r] is an Array of Room, left to right.
var floors: Array[Array] = []
## The villager waiting in the rescue room, or "" when nobody is left.
var rescue_villager: String = ""
## The vault's prize: {"landmark": id} or {"resources": {id: amount}}.
var vault_prize: Dictionary = {}
## Which attempt produced this map (0 = first draw), or -1 for the template.
var attempt: int = 0
var max_fight_streak: int = 3


## Every room-to-room link a row of `from_width` may send to a row of
## `to_width` (spec 8a), as [from, to] pairs.
const CANDIDATES: Dictionary[String, Array] = {
	"2>2": [[0, 0], [0, 1], [1, 0], [1, 1]],
	"2>3": [[0, 0], [0, 1], [1, 1], [1, 2]],
	"3>2": [[0, 0], [1, 0], [1, 1], [2, 1]],
	"3>3": [[0, 0], [0, 1], [1, 0], [1, 1], [1, 2], [2, 1], [2, 2]],
}

## Every valid link set per width pair, built once: no crossings, every
## room has 1 or 2 links out and at least 1 in.
static var _link_sets: Dictionary[String, Array] = {}


## Draws the map for a delve. `villagers_left` and `landmarks_left` are the
## ones not yet in town, in a fixed order (data order).
static func generate(data: GameData, delve_seed: int, villagers_left: Array[String], landmarks_left: Array[String], config_id: String = "slice") -> DelveMap:
	var config: Dictionary = data.row("delve", config_id)
	var attempts: int = maxi(1, config["redraw_attempts"] as int)
	for attempt_index: int in attempts:
		var rng: RngStreams = RngStreams.new(sub_seed(delve_seed, attempt_index))
		var map: DelveMap = _draw(config, rng, villagers_left, landmarks_left)
		map.attempt = attempt_index
		if map.map_errors().is_empty():
			return map
	var fallback: DelveMap = template(config, RngStreams.new(sub_seed(delve_seed, attempts)), villagers_left, landmarks_left)
	fallback.attempt = -1
	return fallback


## Each attempt's own seed, so a redraw never depends on how much an
## earlier attempt drew.
static func sub_seed(delve_seed: int, attempt_index: int) -> int:
	return ("saikoro-bay:map:%d:%d" % [delve_seed, attempt_index]).sha256_text().substr(0, 15).hex_to_int()


func room(floor_index: int, row: int, col: int) -> Room:
	return (floors[floor_index][row] as Array)[col] as Room


func rows_in_floor(floor_index: int) -> int:
	return (floors[floor_index] as Array).size()


func width(floor_index: int, row: int) -> int:
	return (floors[floor_index][row] as Array).size()


func all_rooms() -> Array[Room]:
	var out: Array[Room] = []
	for f: Array in floors:
		for r: Variant in f:
			for rm: Variant in r as Array:
				out.append(rm as Room)
	return out


# --- Validation -----------------------------------------------------------

## Everything wrong with this map, or an empty list. Generation redraws
## until this is empty; the CI property test runs it on many seeds.
func map_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if floors.is_empty():
		errors.append("no floors")
		return errors
	for f: int in floors.size():
		_link_errors(f, errors)
		_floor_room_errors(f, errors)
	if rescue_villager.is_empty() == (_count(RESCUE) > 0):
		errors.append("rescue room and rescue villager disagree")
	if vault_prize.is_empty():
		errors.append("vault has no prize")
	return errors


func _link_errors(f: int, errors: PackedStringArray) -> void:
	for r: int in rows_in_floor(f):
		var w: int = width(f, r)
		if w < 2 or w > 3:
			errors.append("floor %d row %d: width %d" % [f, r, w])
		var last: bool = r == rows_in_floor(f) - 1
		var incoming: Dictionary[int, bool] = {}
		for c: int in w:
			var rm: Room = room(f, r, c)
			if last:
				if not rm.links.is_empty():
					errors.append("floor %d row %d: last row links onward" % [f, r])
				continue
			if rm.links.is_empty() or rm.links.size() > 2:
				errors.append("floor %d row %d col %d: %d links out" % [f, r, c, rm.links.size()])
			var allowed: Array = CANDIDATES.get("%d>%d" % [w, width(f, r + 1)], [])
			for to: int in rm.links:
				if not allowed.has([c, to]):
					errors.append("floor %d row %d: link %d>%d not allowed" % [f, r, c, to])
				incoming[to] = true
			# No crossings: a link a>b and c>d with a < c needs b <= d.
			for other: int in range(c + 1, w):
				for to: int in rm.links:
					for other_to: int in room(f, r, other).links:
						if to > other_to:
							errors.append("floor %d row %d: links cross" % [f, r])
		if r > 0:
			var above: Array = floors[f][r - 1] as Array
			var into: Dictionary[int, bool] = {}
			for rm_above: Variant in above:
				for to: int in (rm_above as Room).links:
					into[to] = true
			for c: int in w:
				if not into.has(c):
					errors.append("floor %d row %d col %d: no way in" % [f, r, c])


func _floor_room_errors(f: int, errors: PackedStringArray) -> void:
	var counts: Dictionary[String, int] = {}
	for r: int in rows_in_floor(f):
		for c: int in width(f, r):
			var rm: Room = room(f, r, c)
			counts[rm.type] = counts.get(rm.type, 0) + 1
			if not rm.type in [FIGHT, ELITE, TREASURE, REST, RESCUE]:
				errors.append("floor %d: room type \"%s\"" % [f, rm.type])
			if rm.type == REST:
				for to: int in rm.links:
					if room(f, r + 1, to).type == REST:
						errors.append("floor %d: two rests linked" % f)
	if f == 0:
		for rm: Variant in floors[0][0] as Array:
			if (rm as Room).type != FIGHT:
				errors.append("floor 1 must open on fights")
	if counts.get(REST, 0) < 1:
		errors.append("floor %d: no rest" % f)
	if counts.get(TREASURE, 0) < 1:
		errors.append("floor %d: no treasure" % f)
	var rescues: int = counts.get(RESCUE, 0)
	if f != RESCUE_FLOOR and rescues > 0:
		errors.append("floor %d: rescue off its floor" % f)
	if f == RESCUE_FLOOR:
		if rescues > 1:
			errors.append("more than one rescue")
		if rescues == 1 and not _rescue_reachable_from_every_start(f):
			errors.append("rescue not reachable from every start")
	var elites: int = counts.get(ELITE, 0)
	if f == ELITE_FLOOR:
		if elites != 1:
			errors.append("floor %d: %d elites" % [f, elites])
		elif not _type_avoidable(f, ELITE):
			errors.append("elite can't be avoided")
	elif elites > 0:
		errors.append("floor %d: elite off its floor" % f)
	if _longest_fight_streak(f) > max_fight_streak:
		errors.append("floor %d: more than %d fights in a row" % [f, max_fight_streak])


func _count(type: String) -> int:
	var n: int = 0
	for rm: Room in all_rooms():
		if rm.type == type:
			n += 1
	return n


## Columns of row `r` reachable from column `c` of row 0, per row.
func _reachable_from(f: int, start_col: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{start_col: true}]
	for r: int in range(1, rows_in_floor(f)):
		var next: Dictionary = {}
		for c: Variant in out[r - 1]:
			for to: int in room(f, r - 1, c as int).links:
				next[to] = true
		out.append(next)
	return out


func _rescue_reachable_from_every_start(f: int) -> bool:
	for start: int in width(f, 0):
		var reach: Array[Dictionary] = _reachable_from(f, start)
		var found: bool = false
		for r: int in rows_in_floor(f):
			for c: Variant in reach[r]:
				if room(f, r, c as int).type == RESCUE:
					found = true
		if not found:
			return false
	return true


## True if some path from row 0 to the last row avoids every room of `type`.
func _type_avoidable(f: int, type: String) -> bool:
	var ok: Dictionary = {}
	for c: int in width(f, 0):
		if room(f, 0, c).type != type:
			ok[c] = true
	for r: int in range(1, rows_in_floor(f)):
		var next: Dictionary = {}
		for c: Variant in ok:
			for to: int in room(f, r - 1, c as int).links:
				if room(f, r, to).type != type:
					next[to] = true
		ok = next
	return not ok.is_empty()


## The most fights (regular or elite) in a row on any path through the
## floor. Counts reset at each landing, so floors are independent.
func _longest_fight_streak(f: int) -> int:
	var best: int = 0
	var streak: Dictionary = {}
	for c: int in width(f, 0):
		streak[c] = 1 if _is_fight(room(f, 0, c)) else 0
		best = maxi(best, streak[c] as int)
	for r: int in range(1, rows_in_floor(f)):
		var next: Dictionary = {}
		for c: Variant in streak:
			for to: int in room(f, r - 1, c as int).links:
				var s: int = (streak[c] as int) + 1 if _is_fight(room(f, r, to)) else 0
				next[to] = maxi(next.get(to, 0) as int, s)
				best = maxi(best, s)
		streak = next
	return best


## True if a room linked to or from `rm` has `type`.
func _next_to(rm: Room, type: String) -> bool:
	var f: int = rm.floor_index
	for to: int in rm.links:
		if room(f, rm.row + 1, to).type == type:
			return true
	if rm.row > 0:
		for c: int in width(f, rm.row - 1):
			var above: Room = room(f, rm.row - 1, c)
			if above.type == type and above.links.has(rm.col):
				return true
	return false


static func _is_fight(rm: Room) -> bool:
	return rm.type == FIGHT or rm.type == ELITE


# --- Drawing --------------------------------------------------------------

static func _draw(config: Dictionary, rng: RngStreams, villagers_left: Array[String], landmarks_left: Array[String]) -> DelveMap:
	var map: DelveMap = DelveMap.new()
	map.max_fight_streak = config["max_fight_streak"] as int
	var width_weights: PackedInt32Array = [config["width_two_weight"] as int, config["width_three_weight"] as int]
	# 1. Shape and links.
	for f: int in config["floors"] as int:
		var rows: Array = []
		for r: int in config["rows_per_floor"] as int:
			var w: int = 2 + rng.weighted_index(RngStreams.Stream.MAP, width_weights)
			var row_rooms: Array = []
			for c: int in w:
				row_rooms.append(Room.new(f, r, c))
			rows.append(row_rooms)
		map.floors.append(rows)
		_draw_links(rows, rng)
	# The rescue floor needs a room every start can reach. If its links
	# don't give one, redraw that floor's links (bounded; the validator
	# rejects the map if they never do).
	if not villagers_left.is_empty() and map.floors.size() > RESCUE_FLOOR:
		for _try: int in 8:
			if not map._rescue_candidates().is_empty():
				break
			_draw_links(map.floors[RESCUE_FLOOR] as Array, rng)
	# 2. Constrained rooms.
	for rm: Variant in map.floors[0][0] as Array:
		(rm as Room).type = FIGHT
	if not villagers_left.is_empty():
		map.rescue_villager = villagers_left[rng.index(RngStreams.Stream.MAP, villagers_left.size())]
		map._place_rescue(rng)
	if map.floors.size() > ELITE_FLOOR:
		map._place_in_floor(rng, ELITE_FLOOR, ELITE, 1)
	for f: int in map.floors.size():
		map._place_in_floor(rng, f, REST, 0)
		map._place_in_floor(rng, f, TREASURE, 0)
	# 3. Fill the rest by weight.
	var fill_types: Array[String] = [FIGHT, TREASURE, REST]
	var fill_weights: PackedInt32Array = [config["fight_weight"] as int, config["treasure_weight"] as int, config["rest_weight"] as int]
	var no_rest_weights: PackedInt32Array = fill_weights.duplicate()
	no_rest_weights[2] = 0
	for rm: Room in map.all_rooms():
		if rm.type.is_empty():
			# Rests are never linked to each other, so a room next to one
			# draws from the other types only.
			var weights: PackedInt32Array = no_rest_weights if map._next_to(rm, REST) else fill_weights
			rm.type = fill_types[rng.weighted_index(RngStreams.Stream.MAP, weights)]
	# The prize is drawn now too, so the landing's peek shows what's paid.
	map.vault_prize = _draw_prize(config, rng, landmarks_left)
	return map


static func _draw_links(rows: Array, rng: RngStreams) -> void:
	for row_rooms: Variant in rows:
		for rm: Variant in row_rooms as Array:
			(rm as Room).links.clear()
	for r: int in rows.size() - 1:
		var sets: Array = _valid_link_sets((rows[r] as Array).size(), (rows[r + 1] as Array).size())
		var chosen: Array = sets[rng.index(RngStreams.Stream.MAP, sets.size())]
		for link: Variant in chosen:
			((rows[r] as Array)[(link as Array)[0] as int] as Room).links.append((link as Array)[1] as int)


## Puts the rescue in a floor-2 room that every row-1 room can reach.
func _place_rescue(rng: RngStreams) -> void:
	var candidates: Array[Room] = _rescue_candidates()
	if candidates.is_empty():
		return  # map_errors() rejects the map and it's redrawn.
	candidates[rng.index(RngStreams.Stream.MAP, candidates.size())].type = RESCUE


## Empty rooms of the rescue floor that every row-1 room can reach. Row 0
## can't qualify (rows are at least 2 wide), so it looks from row 1 down.
func _rescue_candidates() -> Array[Room]:
	var f: int = RESCUE_FLOOR
	var candidates: Array[Room] = []
	if floors.size() <= f:
		return candidates
	var reach: Array = []
	for start: int in width(f, 0):
		reach.append(_reachable_from(f, start))
	for r: int in range(1, rows_in_floor(f)):
		for c: int in width(f, r):
			var everyone: bool = true
			for start_reach: Variant in reach:
				if not ((start_reach as Array)[r] as Dictionary).has(c):
					everyone = false
			if everyone and room(f, r, c).type.is_empty():
				candidates.append(room(f, r, c))
	return candidates


## Puts one `type` room in an empty room of floor `f`, from row `min_row`
## down. Does nothing if the floor already has one.
func _place_in_floor(rng: RngStreams, f: int, type: String, min_row: int) -> void:
	var empty: Array[Room] = []
	for r: int in range(min_row, rows_in_floor(f)):
		for c: int in width(f, r):
			var rm: Room = room(f, r, c)
			if rm.type == type:
				return
			if rm.type.is_empty() and not (f == 0 and r == 0):
				empty.append(rm)
	if not empty.is_empty():
		empty[rng.index(RngStreams.Stream.MAP, empty.size())].type = type


static func _draw_prize(config: Dictionary, rng: RngStreams, landmarks_left: Array[String]) -> Dictionary:
	if not landmarks_left.is_empty():
		return {"landmark": landmarks_left[rng.index(RngStreams.Stream.MAP, landmarks_left.size())]}
	return {"resources": {"koban_coins": config["fallback_koban_coins"] as int, "driftwood": config["fallback_driftwood"] as int}}


static func _valid_link_sets(from_width: int, to_width: int) -> Array:
	var key: String = "%d>%d" % [from_width, to_width]
	if _link_sets.has(key):
		return _link_sets[key]
	var candidates: Array = CANDIDATES[key]
	var sets: Array = []
	for mask: int in range(1, 1 << candidates.size()):
		var chosen: Array = []
		for i: int in candidates.size():
			if mask & (1 << i):
				chosen.append(candidates[i])
		if _link_set_ok(chosen, from_width, to_width):
			sets.append(chosen)
	_link_sets[key] = sets
	return sets


static func _link_set_ok(links: Array, from_width: int, to_width: int) -> bool:
	var out_count: Array[int] = []
	out_count.resize(from_width)
	var in_count: Array[int] = []
	in_count.resize(to_width)
	for link: Variant in links:
		out_count[(link as Array)[0]] += 1
		in_count[(link as Array)[1]] += 1
	for n: int in out_count:
		if n < 1 or n > 2:
			return false
	for n: int in in_count:
		if n < 1:
			return false
	for a: Variant in links:
		for b: Variant in links:
			if ((a as Array)[0] as int) < ((b as Array)[0] as int) and ((a as Array)[1] as int) > ((b as Array)[1] as int):
				return false
	return true


## The last-resort map: fixed widths and links that always pass, with
## types placed by the same rules. Only the rescue villager and the prize
## are drawn.
static func template(config: Dictionary, rng: RngStreams, villagers_left: Array[String], landmarks_left: Array[String]) -> DelveMap:
	var map: DelveMap = DelveMap.new()
	map.max_fight_streak = config["max_fight_streak"] as int
	# Every floor: 2 > 3 > 2, all straight-and-diagonal links.
	var plan: Array = [
		[[FIGHT, FIGHT], [TREASURE, FIGHT, REST], [FIGHT, TREASURE]],
		[[FIGHT, TREASURE], [FIGHT, RESCUE, REST], [TREASURE, FIGHT]],
		[[FIGHT, TREASURE], [REST, ELITE, FIGHT], [FIGHT, TREASURE]],
	]
	var links_2_3: Array = [[0, 1], [1, 2]]
	var links_3_2: Array = [[0], [0, 1], [1]]
	for f: int in config["floors"] as int:
		var types: Array = plan[mini(f, plan.size() - 1)]
		var rows: Array = []
		for r: int in types.size():
			var row_rooms: Array = []
			for c: int in (types[r] as Array).size():
				var rm: Room = Room.new(f, r, c)
				rm.type = (types[r] as Array)[c]
				if r == 0:
					rm.links.assign(links_2_3[c])
				elif r == 1:
					rm.links.assign(links_3_2[c])
				row_rooms.append(rm)
			rows.append(row_rooms)
		map.floors.append(rows)
	if villagers_left.is_empty():
		map.room(RESCUE_FLOOR, 1, 1).type = TREASURE
	else:
		map.rescue_villager = villagers_left[rng.index(RngStreams.Stream.MAP, villagers_left.size())]
	map.vault_prize = _draw_prize(config, rng, landmarks_left)
	return map


## A compact text form for tests and bot reports: one line per row.
func describe() -> String:
	var lines: PackedStringArray = []
	for f: int in floors.size():
		for r: int in rows_in_floor(f):
			var cells: PackedStringArray = []
			for c: int in width(f, r):
				var rm: Room = room(f, r, c)
				cells.append("%s>%s" % [rm.type, ",".join(PackedStringArray(rm.links.map(func(x: int) -> String: return str(x))))])
			lines.append("%d.%d %s" % [f, r, "  ".join(cells)])
		lines.append("-- landing")
	lines.append("vault %s" % JSON.stringify(vault_prize))
	return "\n".join(lines)
