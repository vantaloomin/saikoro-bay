class_name SpikeTown
extends RefCounted
## Camera spike for M3 (vertical slice plan section 10): one small greybox
## town, drawn looking straight down or at an isometric angle. Testers run
## the same three tasks in each view, and the view with fewer misclicks
## wins. Throwaway tooling: it lives in tools/ and never ships.
##
## This file holds the layout, both projections and click picking, with no
## nodes, so the tests can check them headless.

enum Ground { LOT, PATH, WATER }
enum View { TOP_DOWN, ISOMETRIC }
enum Task { EMPTY_LOT, UNHAPPY, PLACE }

const WIDTH: int = 10
const HEIGHT: int = 8
## Rows 0 to 6 are land. Row 7 is the sea.
const LAND_ROWS: int = 7
const PATH_COLUMNS: Array[int] = [3, 7]
const PATH_ROW: int = 3
const NO_CELL: Vector2i = Vector2i(-1, -1)

## Pixel sizes at 1080p.
const TOP_CELL: float = 96.0
const ISO_HALF_W: float = 80.0
const ISO_HALF_H: float = 40.0
const MARKER_RADIUS: float = 26.0
## How tall each kind of block stands in the isometric view.
const BLOCK_HEIGHT: Dictionary[String, float] = {"home": 52.0, "shop": 68.0, "landmark": 116.0}

const VILLAGER_NAMES: Dictionary[String, String] = {
	"pearl_diver": "Pearl diver", "shipwright": "Shipwright",
	"onsen_keeper": "Onsen keeper", "shrine_keeper": "Shrine keeper",
}
const VILLAGER_INITIALS: Dictionary[String, String] = {
	"pearl_diver": "P", "shipwright": "S", "onsen_keeper": "O", "shrine_keeper": "K",
}

## The plots buildings stand on, between the paths (variant A).
const LOTS_A: Array[Rect2i] = [
	Rect2i(0, 0, 3, 3), Rect2i(4, 0, 3, 3), Rect2i(8, 0, 2, 3),
	Rect2i(0, 4, 3, 3), Rect2i(4, 4, 3, 3), Rect2i(8, 4, 2, 3),
]
## Variant A. Variant B turns the land half a circle, so the second view
## doesn't reward memory, and picks other targets.
const BUILDINGS_A: Array[Dictionary] = [
	{"id": "cafe", "name": "Café", "kind": "landmark", "rect": Rect2i(0, 0, 3, 2), "villager": ""},
	{"id": "shrine", "name": "Shrine", "kind": "landmark", "rect": Rect2i(8, 0, 2, 2), "villager": ""},
	{"id": "net_shed", "name": "Net shed", "kind": "shop", "rect": Rect2i(4, 2, 2, 1), "villager": ""},
	{"id": "home_p", "name": "Home", "kind": "home", "rect": Rect2i(4, 0, 1, 1), "villager": "pearl_diver"},
	{"id": "home_s", "name": "Home", "kind": "home", "rect": Rect2i(6, 0, 1, 1), "villager": "shipwright"},
	{"id": "bait_shop", "name": "Bait shop", "kind": "shop", "rect": Rect2i(0, 6, 2, 1), "villager": ""},
	{"id": "home_o", "name": "Home", "kind": "home", "rect": Rect2i(0, 4, 1, 1), "villager": "onsen_keeper"},
	{"id": "home_k", "name": "Home", "kind": "home", "rect": Rect2i(2, 4, 1, 1), "villager": "shrine_keeper"},
	{"id": "boat_shed", "name": "Boat shed", "kind": "shop", "rect": Rect2i(8, 4, 2, 2), "villager": ""},
]
const VARIANTS: Array[Dictionary] = [
	{"empty_lot": Rect2i(4, 4, 3, 3), "unhappy": "shipwright", "neighbor": "net_shed"},
	{"empty_lot": Rect2i(4, 4, 3, 3), "unhappy": "onsen_keeper", "neighbor": "bait_shop"},
]

const TEA_STALL: Dictionary = {"id": "tea_stall", "name": "Tea stall", "kind": "shop", "villager": ""}

var view: View = View.TOP_DOWN
## Grid (0, 0)'s top corner on screen.
var origin: Vector2 = Vector2.ZERO
var lots: Array[Rect2i] = []
var buildings: Array[Dictionary] = []
var empty_lot: Rect2i
var unhappy: String = ""
var neighbor: String = ""


## Variant 0 or 1, in a view, framed inside `area` (screen pixels).
static func make(variant: int, in_view: View, area: Rect2) -> SpikeTown:
	var town: SpikeTown = SpikeTown.new()
	town.view = in_view
	var spec: Dictionary = VARIANTS[variant]
	var turned: bool = variant == 1
	for lot: Rect2i in LOTS_A:
		town.lots.append(_turn(lot) if turned else lot)
	for row: Dictionary in BUILDINGS_A:
		var copy: Dictionary = row.duplicate()
		if turned:
			copy["rect"] = _turn(row["rect"] as Rect2i)
		town.buildings.append(copy)
	town.empty_lot = _turn(spec["empty_lot"] as Rect2i) if turned else spec["empty_lot"] as Rect2i
	town.unhappy = str(spec["unhappy"])
	town.neighbor = str(spec["neighbor"])
	town._frame(area)
	return town


## Half a turn of the land, leaving the sea along the bottom.
static func _turn(rect: Rect2i) -> Rect2i:
	return Rect2i(WIDTH - rect.end.x, LAND_ROWS - rect.end.y, rect.size.x, rect.size.y)


## Centers the map in `area`, leaving headroom for the tallest blocks.
func _frame(area: Rect2) -> void:
	if view == View.TOP_DOWN:
		var size: Vector2 = Vector2(WIDTH, HEIGHT) * TOP_CELL
		origin = area.position + (area.size - size) / 2.0
	else:
		var headroom: float = BLOCK_HEIGHT["landmark"] + MARKER_RADIUS
		var size: Vector2 = Vector2((WIDTH + HEIGHT) * ISO_HALF_W, (WIDTH + HEIGHT) * ISO_HALF_H + headroom)
		var corner: Vector2 = area.position + (area.size - size) / 2.0
		origin = Vector2(corner.x + HEIGHT * ISO_HALF_W, corner.y + headroom)
	origin = origin.round()


# --- Projection ---------------------------------------------------------------------

## A point in grid units (cell corners are whole numbers) on screen.
func grid_point(grid: Vector2) -> Vector2:
	if view == View.TOP_DOWN:
		return origin + grid * TOP_CELL
	return origin + Vector2((grid.x - grid.y) * ISO_HALF_W, (grid.x + grid.y) * ISO_HALF_H)


func to_grid(point: Vector2) -> Vector2:
	var local: Vector2 = point - origin
	if view == View.TOP_DOWN:
		return local / TOP_CELL
	var a: float = local.x / ISO_HALF_W
	var b: float = local.y / ISO_HALF_H
	return Vector2((a + b) / 2.0, (b - a) / 2.0)


func cell_center(cell: Vector2i) -> Vector2:
	return grid_point(Vector2(cell) + Vector2(0.5, 0.5))


## The ground cell under a screen point, or NO_CELL off the map.
func cell_at(point: Vector2) -> Vector2i:
	var grid: Vector2 = to_grid(point)
	var cell: Vector2i = Vector2i(floori(grid.x), floori(grid.y))
	return cell if in_bounds(cell) else NO_CELL


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


## The four ground corners of a footprint: top, right, bottom, left in the
## isometric view (top-left, top-right, bottom-right, bottom-left top-down).
func footprint(rect: Rect2i) -> PackedVector2Array:
	return PackedVector2Array([
		grid_point(Vector2(rect.position)), grid_point(Vector2(rect.end.x, rect.position.y)),
		grid_point(Vector2(rect.end)), grid_point(Vector2(rect.position.x, rect.end.y)),
	])


# --- Ground and buildings ------------------------------------------------------------

func ground(cell: Vector2i) -> Ground:
	if cell.y >= LAND_ROWS:
		return Ground.WATER
	for lot: Rect2i in lots:
		if lot.has_point(cell):
			return Ground.LOT
	return Ground.PATH


## Variant buildings, minus the ones on the empty lot, plus anything placed.
func standing() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for building: Dictionary in buildings:
		if not empty_lot.intersects(building["rect"] as Rect2i):
			out.append(building)
	return out


func building_at(cell: Vector2i) -> Dictionary:
	for building: Dictionary in standing():
		if (building["rect"] as Rect2i).has_point(cell):
			return building
	return {}


func building(id: String) -> Dictionary:
	for row: Dictionary in standing():
		if row["id"] == id:
			return row
	return {}


func is_free_lot(cell: Vector2i) -> bool:
	return in_bounds(cell) and ground(cell) == Ground.LOT and building_at(cell).is_empty()


## Shares an edge with the building's footprint.
func touches(cell: Vector2i, building_id: String) -> bool:
	var row: Dictionary = building(building_id)
	if row.is_empty():
		return false
	var rect: Rect2i = row["rect"]
	if rect.has_point(cell):
		return false
	return rect.grow(1).has_point(cell) and not _is_diagonal(cell, rect)


static func _is_diagonal(cell: Vector2i, rect: Rect2i) -> bool:
	var outside_x: bool = cell.x < rect.position.x or cell.x >= rect.end.x
	var outside_y: bool = cell.y < rect.position.y or cell.y >= rect.end.y
	return outside_x and outside_y


func place_tea_stall(cell: Vector2i) -> void:
	var stall: Dictionary = TEA_STALL.duplicate()
	stall["rect"] = Rect2i(cell, Vector2i.ONE)
	buildings.append(stall)


## Back to front, so nearer blocks draw over farther ones.
func draw_order() -> Array[Dictionary]:
	var order: Array[Dictionary] = standing()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Rect2i = a["rect"]
		var rb: Rect2i = b["rect"]
		var ka: int = ra.end.x + ra.end.y
		var kb: int = rb.end.x + rb.end.y
		return ka < kb if ka != kb else ra.position.x < rb.position.x)
	return order


func block_height(row: Dictionary) -> float:
	return 0.0 if view == View.TOP_DOWN else BLOCK_HEIGHT[str(row["kind"])]


## Everything a block covers on screen: its footprint top-down, or the
## outline of the raised box in the isometric view.
func block_outline(row: Dictionary) -> PackedVector2Array:
	var ground_corners: PackedVector2Array = footprint(row["rect"] as Rect2i)
	if view == View.TOP_DOWN:
		return ground_corners
	var up: Vector2 = Vector2(0.0, -block_height(row))
	return PackedVector2Array([
		ground_corners[0] + up, ground_corners[1] + up, ground_corners[1],
		ground_corners[2], ground_corners[3], ground_corners[3] + up,
	])


## Where the block's name and its villager's marker sit.
func roof_center(row: Dictionary) -> Vector2:
	var rect: Rect2i = row["rect"]
	return grid_point(Vector2(rect.position) + Vector2(rect.size) / 2.0) + Vector2(0.0, -block_height(row))


func marker_center(row: Dictionary) -> Vector2:
	if view == View.TOP_DOWN:
		return roof_center(row)
	return roof_center(row) + Vector2(0.0, -MARKER_RADIUS - 6.0)


# --- Picking and tasks ---------------------------------------------------------------

## What a click lands on, front to back: a villager marker, a block, then the
## ground. {"kind": "villager" | "building" | "cell" | "none", ...}
## While carrying a building, `ground_only` looks through blocks to the
## ground, as isometric builders do, and the ghost draws on top instead.
func pick(point: Vector2, ground_only: bool = false) -> Dictionary:
	var order: Array[Dictionary] = []
	if not ground_only:
		order = draw_order()
		order.reverse()
	for row: Dictionary in order:
		if not str(row["villager"]).is_empty() and point.distance_to(marker_center(row)) <= MARKER_RADIUS:
			return {"kind": "villager", "villager": row["villager"], "id": row["id"]}
	for row: Dictionary in order:
		if Geometry2D.is_point_in_polygon(point, block_outline(row)):
			return {"kind": "building", "villager": row["villager"], "id": row["id"]}
	var cell: Vector2i = cell_at(point)
	if cell != NO_CELL:
		return {"kind": "cell", "cell": cell}
	return {"kind": "none"}


func task_text(task: Task) -> String:
	match task:
		Task.EMPTY_LOT:
			return "Find the empty lot and click it."
		Task.UNHAPPY:
			return "One villager is unhappy at home. Click them."
		_:
			return "Put the Tea stall next to the %s." % str(building(neighbor).get("name", neighbor))


func task_done(task: Task, hit: Dictionary) -> bool:
	match task:
		Task.EMPTY_LOT:
			return hit["kind"] == "cell" and empty_lot.has_point(hit["cell"] as Vector2i)
		Task.UNHAPPY:
			return hit["kind"] in ["villager", "building"] and hit["villager"] == unhappy
		_:
			return hit["kind"] == "cell" and is_free_lot(hit["cell"] as Vector2i) \
				and touches(hit["cell"] as Vector2i, neighbor)
