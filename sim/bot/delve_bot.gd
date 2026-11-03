class_name DelveBot
extends RefCounted
## Picks the path through a delve (specs/delve-map.md section 7). It reads
## only a RunView, the same filtered view the map screen shows, so it can't
## use a room type or prize the player hasn't seen.
##
## Rooms: from the next rooms it can walk into, it prefers a rest when HP
## is under half, otherwise a treasure, then the rescue. It avoids the elite
## unless HP is over 70%. Unrevealed rooms count as fights. Ties go to the
## room whose linked rooms below look best, then to the leftmost.
##
## Landings: it surfaces under 30% HP, or under 50% when the peeked row has
## no rest or treasure; otherwise it goes deeper.

const LOW_HP_PERCENT: int = 50
const ELITE_HP_PERCENT: int = 70
const SURFACE_HP_PERCENT: int = 30


## The column of the next room to walk into, or -1 if there's none.
func choose_room(view: RunView) -> int:
	var rows: Array = view.rows()
	var best_col: int = -1
	var best_key: int = -1
	for r: int in rows.size():
		for room: Dictionary in rows[r] as Array:
			if room["state"] != "next":
				continue
			var below: int = 0
			if r + 1 < rows.size():
				for linked: Variant in room["links"] as Array:
					for other: Dictionary in rows[r + 1] as Array:
						if other["col"] == linked:
							below = maxi(below, _worth(view, str(other["type"])))
			var key: int = _worth(view, str(room["type"])) * 100 + below
			if key > best_key:
				best_key = key
				best_col = room["col"] as int
	return best_col


## "surface" or "deeper" at a landing.
func at_landing(view: RunView) -> String:
	var hp_percent: int = view.hp() * 100 / maxi(1, view.max_hp())
	if hp_percent < SURFACE_HP_PERCENT:
		return "surface"
	var peek: Dictionary = view.peek()
	var safe_ahead: bool = false
	if not (peek.get("rows", []) as Array).is_empty():
		for type: Variant in (peek["rows"] as Array)[0] as Array:
			if type == DelveMap.REST or type == DelveMap.TREASURE:
				safe_ahead = true
	if hp_percent < LOW_HP_PERCENT and not safe_ahead:
		return "surface"
	return "deeper"


## How much the bot wants a room of `type` now (higher is better).
func _worth(view: RunView, type: String) -> int:
	var hp_percent: int = view.hp() * 100 / maxi(1, view.max_hp())
	var low: bool = hp_percent < LOW_HP_PERCENT
	match type:
		DelveMap.REST:
			return 6 if low else 3
		DelveMap.TREASURE:
			return 5
		DelveMap.RESCUE:
			return 4
		DelveMap.ELITE:
			return 2 if hp_percent > ELITE_HP_PERCENT else 0
	return 1
