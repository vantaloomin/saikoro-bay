class_name MapPaths
extends RefCounted
## Reads paths off the floor the player can see (RunView.rows()), for the
## map screen's hover (Mara's review #4): which rooms and links a path
## through a room uses, and what it holds ("Through here: 2 fights · 1 rest
## · 1 ?"). It only reads the view, so a "?" stays a "?".

## Summary order and names: [type, one, many].
const KINDS: Array[Array] = [
	[DelveMap.FIGHT, "fight", "fights"],
	[DelveMap.ELITE, "elite", "elites"],
	[DelveMap.REST, "rest", "rests"],
	[DelveMap.TREASURE, "treasure", "treasures"],
	[DelveMap.RESCUE, "rescue", "rescues"],
	[RunView.HIDDEN, "?", "?"],
]


## Every path from the rooms you can walk into now down to the floor's last
## row. Each path is an Array of Vector2i(row, col), top to bottom. Empty
## when no room is "next" (you're in a room or at a landing).
static func all_paths(rows: Array) -> Array[Array]:
	var out: Array[Array] = []
	for r: int in rows.size():
		for room: Dictionary in rows[r] as Array:
			if room["state"] == "next":
				_walk(rows, Vector2i(r, room["col"] as int), [], out)
		if not out.is_empty():
			break
	return out


## The paths that pass through `cell`.
static func through(paths: Array[Array], cell: Vector2i) -> Array[Array]:
	var out: Array[Array] = []
	for p: Array in paths:
		if p.has(cell):
			out.append(p)
	return out


## Every room on `paths`, as {Vector2i: true}.
static func cells(paths: Array[Array]) -> Dictionary:
	var out: Dictionary = {}
	for p: Array in paths:
		for cell: Vector2i in p:
			out[cell] = true
	return out


## Every link on `paths`, as {[from, to]: true} with Vector2i ends.
static func links(paths: Array[Array]) -> Dictionary:
	var out: Dictionary = {}
	for p: Array in paths:
		for i: int in p.size() - 1:
			out[[p[i], p[i + 1]]] = true
	return out


## What the paths hold, counted per path: "2 fights · 1 rest · 1 ?". When
## paths differ it gives the range ("1-2 fights"). Empty for no paths.
static func summary(rows: Array, paths: Array[Array]) -> String:
	if paths.is_empty():
		return ""
	var parts: PackedStringArray = []
	for kind: Array in KINDS:
		var low: int = 1 << 30
		var high: int = 0
		for p: Array in paths:
			var n: int = 0
			for cell: Vector2i in p:
				if (rows[cell.x] as Array)[cell.y]["type"] == kind[0]:
					n += 1
			low = mini(low, n)
			high = maxi(high, n)
		if high == 0 and not (kind[0] == DelveMap.FIGHT and paths.size() == 1):
			continue
		var count: String = str(high) if low == high else "%d-%d" % [low, high]
		parts.append("%s %s" % [count, kind[1] if high == 1 else kind[2]])
	return " · ".join(parts)


## For the hover when paths through a room differ (Mara, #29): the safest
## and the riskiest of them, as {"safest": summary, "riskiest": summary},
## or {"only": summary} when every path holds the same rooms. Safest has
## the fewest fights (an elite counts as two), then the most rests;
## riskiest the most fights. Unseen rooms count as neither.
static func extremes(rows: Array, paths: Array[Array]) -> Dictionary:
	if paths.is_empty():
		return {}
	var safest: Array = paths[0]
	var riskiest: Array = paths[0]
	var distinct: Dictionary = {}
	for p: Array in paths:
		var single: Array[Array] = [p]
		distinct[summary(rows, single)] = true
		if _risk(rows, p) < _risk(rows, safest) or (_risk(rows, p) == _risk(rows, safest) and _count(rows, p, DelveMap.REST) > _count(rows, safest, DelveMap.REST)):
			safest = p
		if _risk(rows, p) > _risk(rows, riskiest):
			riskiest = p
	var safe_only: Array[Array] = [safest]
	if distinct.size() == 1:
		return {"only": summary(rows, safe_only)}
	var risky_only: Array[Array] = [riskiest]
	return {"safest": summary(rows, safe_only), "riskiest": summary(rows, risky_only)}


## Fights on a path, an elite counting as two.
static func _risk(rows: Array, p: Array) -> int:
	return _count(rows, p, DelveMap.FIGHT) + 2 * _count(rows, p, DelveMap.ELITE)


static func _count(rows: Array, p: Array, type: String) -> int:
	var n: int = 0
	for cell: Vector2i in p:
		if (rows[cell.x] as Array)[cell.y]["type"] == type:
			n += 1
	return n


static func _walk(rows: Array, cell: Vector2i, so_far: Array, out: Array[Array]) -> void:
	var path: Array = so_far.duplicate()
	path.append(cell)
	if cell.x == rows.size() - 1:
		out.append(path)
		return
	for to: Variant in (rows[cell.x] as Array)[cell.y]["links"] as Array:
		_walk(rows, Vector2i(cell.x + 1, int(to)), path, out)
