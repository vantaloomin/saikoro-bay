class_name TownMap
extends RefCounted
## The town's ground (specs/town.md section 2): a grid of cells, cut into
## lots by the path columns and rows, with the sea along the bottom rows.
## Built from the one row in data/town.json. Pure geometry, no state.

enum Ground { LOT, PATH, SEA }

var width: int = 0
var height: int = 0
## Rows 0 to land_rows - 1 are land; the rest is sea.
var land_rows: int = 0
## The buildable rectangles between the paths, top row first, left to right.
var lots: Array[Rect2i] = []


static func from_row(town_row: Dictionary) -> TownMap:
	var map: TownMap = TownMap.new()
	map.width = town_row["width"]
	map.height = town_row["height"]
	map.land_rows = map.height - int(town_row["sea_rows"])
	var xs: Array[Vector2i] = _spans(town_row["path_columns"] as Array, map.width)
	var ys: Array[Vector2i] = _spans(town_row["path_rows"] as Array, map.land_rows)
	for y_span: Vector2i in ys:
		for x_span: Vector2i in xs:
			map.lots.append(Rect2i(x_span.x, y_span.x, x_span.y, y_span.y))
	return map


## [start, length] runs between the cuts, from 0 up to `size`.
static func _spans(cuts: Array, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start: int = 0
	for cut: Variant in cuts + [size]:
		if int(cut) > start:
			out.append(Vector2i(start, mini(int(cut), size) - start))
		start = int(cut) + 1
	return out


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func ground(cell: Vector2i) -> Ground:
	if cell.y >= land_rows:
		return Ground.SEA
	return Ground.LOT if lot_index(cell) >= 0 else Ground.PATH


## The lot a cell is in, or -1 on a path, in the sea or off the map.
func lot_index(cell: Vector2i) -> int:
	for index: int in lots.size():
		if lots[index].has_point(cell):
			return index
	return -1


## Whether a footprint fits inside a single lot.
func fits_one_lot(footprint: Rect2i) -> bool:
	for lot: Rect2i in lots:
		if lot.encloses(footprint):
			return true
	return false


## "resource:amount" entries as {resource: amount}, or null if any entry is
## malformed, repeats a resource, or isn't a whole number of at least 1.
static func parse_cost(entries: Array) -> Variant:
	var cost: Dictionary[String, int] = {}
	for entry: Variant in entries:
		var parts: PackedStringArray = str(entry).split(":")
		if parts.size() != 2 or parts[0].is_empty() or not parts[1].is_valid_int() or cost.has(parts[0]):
			return null
		var amount: int = parts[1].to_int()
		if amount < 1:
			return null
		cost[parts[0]] = amount
	return cost
