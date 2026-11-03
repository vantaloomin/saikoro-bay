class_name RunView
extends RefCounted
## What the player can see of a delve (specs/delve-map.md 8a, rule 4). The
## map screen, the landing and the bot read this, never the generated map,
## so nothing can show or use a room type the player hasn't seen.
##
## You see the shape of the floor you're on (every room and link), and room
## types only for rows already played and `reveal_rows` rows ahead (2, or 3
## with Foresight). At a landing, the peek shows the next floor's first row
## (two rows with Foresight) and that floor's prize. Who's in a fight room
## stays hidden until you walk in.

const HIDDEN: String = "?"

var _run: DelveRun


func _init(run: DelveRun) -> void:
	_run = run


func step() -> DelveRun.Step:
	return _run.step


func floor_index() -> int:
	return _run.floor_index


func floor_count() -> int:
	return _run.map.floors.size()


func hp() -> int:
	return _run.hp


func max_hp() -> int:
	return _run.max_hp


func haul() -> Haul:
	return _run.haul.copy()


func reachable() -> Array[int]:
	return _run.reachable()


func rooms_to_landing() -> int:
	return _run.rooms_to_landing()


func has_foresight() -> bool:
	return _run.foresight


## Who gives Foresight (a villager id), for its badge, or "" without it.
func foresight_source() -> String:
	if not _run.foresight:
		return ""
	for entry: Dictionary in _run.perks:
		if str(entry.get("perk", "")) == DelveRun.FORESIGHT_PERK:
			return str(entry.get("source", ""))
	return ""


## The enemy in the room being played, once you're in it, or "".
func current_enemy() -> String:
	return _run.fight.enemy_id if _run.fight != null else ""


## The floor you're on, row by row. Each room is a Dictionary:
##   col, links   its place and links to the next row
##   type         the room type, or "?" when it isn't revealed
##   state        "visited", "current", "next" (you can walk in now),
##                "open" (still reachable later) or "closed" (cut off)
##   villager     the villager in a revealed rescue room
func rows() -> Array:
	var f: int = _run.floor_index
	var open: Dictionary = _open_rooms()
	var out: Array = []
	for r: int in _run.map.rows_in_floor(f):
		var row_rooms: Array = []
		for c: int in _run.map.width(f, r):
			var rm: DelveMap.Room = _run.map.room(f, r, c)
			var entry: Dictionary = {"col": c, "links": rm.links.duplicate(), "type": HIDDEN, "state": _state(r, c, open)}
			if _revealed(r):
				entry["type"] = rm.type
				if rm.type == DelveMap.RESCUE:
					entry["villager"] = _run.map.rescue_villager
			row_rooms.append(entry)
		out.append(row_rooms)
	return out


## At a landing: the next floor's first rows and its prize, or {} anywhere
## else. Keys: floor, rows (as in rows(), types only), prize ({"rescue":
## villager} for the rescue floor, {"vault": prize} for the last floor).
func peek() -> Dictionary:
	if _run.step != DelveRun.Step.LANDING:
		return {}
	var f: int = _run.floor_index + 1
	var depth: int = 2 if has_foresight() else 1
	var peeked: Array = []
	for r: int in mini(depth, _run.map.rows_in_floor(f)):
		var row_types: Array = []
		for c: int in _run.map.width(f, r):
			row_types.append(_run.map.room(f, r, c).type)
		peeked.append(row_types)
	var prize: Dictionary = {}
	if f == DelveMap.RESCUE_FLOOR and not _run.map.rescue_villager.is_empty():
		prize = {"rescue": _run.map.rescue_villager}
	elif f == _run.map.floors.size() - 1:
		prize = {"vault": _run.map.vault_prize.duplicate(true)}
	return {"floor": f, "rows": peeked, "prize": prize}


## The vault's prize once you're on the last floor, or {} before. (The
## landing above it shows it in the peek.)
func vault_prize() -> Dictionary:
	if _run.floor_index < _run.map.floors.size() - 1:
		return {}
	return _run.map.vault_prize.duplicate(true)


## Everything above as one Dictionary, for tests and logs.
func to_dict() -> Dictionary:
	return {
		"step": _run.step, "floor": _run.floor_index, "hp": _run.hp, "max_hp": _run.max_hp,
		"haul": _run.haul.to_dict(), "reachable": reachable(), "rooms_to_landing": rooms_to_landing(),
		"rows": rows(), "peek": peek(), "vault_prize": vault_prize(), "enemy": current_enemy(),
	}


func _revealed(r: int) -> bool:
	return r <= _run.row + _run.reveal_rows


func _state(r: int, c: int, open: Dictionary) -> String:
	for p: Array in _run.path:
		if p[0] == _run.floor_index and p[1] == r and p[2] == c:
			return "current" if r == _run.row and _run.step == DelveRun.Step.IN_ROOM else "visited"
	if r == _run.row + 1 and _run.reachable().has(c):
		return "next"
	if open.has(Vector2i(r, c)):
		return "open"
	return "closed"


## Rooms below the current one that a path can still reach.
func _open_rooms() -> Dictionary:
	var f: int = _run.floor_index
	var open: Dictionary = {}
	var frontier: Array[int] = []
	if _run.row < 0:
		for c: int in _run.map.width(f, 0):
			frontier.append(c)
	else:
		frontier.assign(_run.map.room(f, _run.row, _run.col).links)
	for r: int in range(_run.row + 1, _run.map.rows_in_floor(f)):
		var below: Array[int] = []
		for c: int in frontier:
			open[Vector2i(r, c)] = true
			for to: int in _run.map.room(f, r, c).links:
				if not below.has(to):
					below.append(to)
		frontier = below
	return open
