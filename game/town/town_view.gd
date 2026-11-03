class_name TownView
extends RefCounted
## The town seen as a diorama at an angle (Vanta's picks, Nov 3: the angled
## camera, then the HD-2D look): where things stand in the 3D world, the
## camera, pan and zoom, and what a click lands on. Pure math with no nodes,
## so tests check it headless; TownDiorama copies the camera from here.
##
## World units: one cell is 1 × 1, x runs along the map's columns, z along
## its rows (the sea is at high z), and y is up. The camera looks from the
## sea-side corner, so the shore runs across the front of the screen.

const NO_CELL: Vector2i = Vector2i(-1, -1)
const YAW_DEGREES: float = 45.0
const PITCH_DEGREES: float = 33.0
const FOV_DEGREES: float = 32.0
const NEAR: float = 0.1
const FAR: float = 200.0
## Walls, then roofs, by kind. A lantern post has no roof.
const BODY_HEIGHT: Dictionary[String, float] = {"home": 0.55, "shop": 0.7, "decor": 0.9, "landmark": 1.0}
const ROOF_HEIGHT: Dictionary[String, float] = {"home": 0.5, "shop": 0.5, "decor": 0.35, "landmark": 0.75}
## Gap between a building and its lot lines, per side.
const INSET: float = 0.09
## A villager sprite's size in world units, and the mood bubble above it.
const VILLAGER_SIZE: Vector2 = Vector2(0.5, 1.0)
const BUBBLE_SIZE: float = 0.6
## How far from the map's middle the camera may wander, in cells past the edge.
const PAN_SLACK: float = 1.0

var map: TownMap
var size: Vector2 = Vector2(1920, 1080)
## The ground point the camera looks at.
var target: Vector3 = Vector3.ZERO
var distance: float = 20.0
var min_distance: float = 8.0
var max_distance: float = 30.0
## The HUD's panels on screen; the land is framed clear of them.
var obstacles: Array[Rect2] = []
## Villagers standing somewhere other than their usual spot for now: the
## town gathered round a new landmark, or walking there and back.
var walking: Dictionary[String, Vector3] = {}


## A view that fits the whole town on a `screen_size` screen, clear of the
## HUD's `obstacles` (screen rects): the panels may cover blurred sky, sea
## and scenery, but never the land (Mara's #41 review, for the Deck).
static func make(town_map: TownMap, screen_size: Vector2, hud: Array[Rect2] = []) -> TownView:
	var view: TownView = TownView.new()
	view.map = town_map
	view.size = screen_size
	view.obstacles = hud
	view.frame_town()
	return view


func middle() -> Vector3:
	return Vector3(map.width / 2.0, 0.0, map.land_rows / 2.0)


## The land as it sits on screen, down to the dock: its ground corners, with the back
## edge raised so roofs, villagers and bubbles along it count too.
func land_outline() -> PackedVector2Array:
	var lift: float = BODY_HEIGHT["landmark"] + ROOF_HEIGHT["landmark"]
	var land: float = map.land_rows
	var points: Array[Vector3] = [
		Vector3(0, 0, land + 1.1), Vector3(map.width, 0, land + 1.1), Vector3(map.width, 0, 0),
		Vector3(map.width, lift, 0), Vector3(0, lift, 0), Vector3(0, 0, 0),
	]
	var screen: PackedVector2Array = []
	for point: Vector3 in points:
		screen.append(to_screen(point))
	return Geometry2D.convex_hull(screen)


func _land_is_clear(margin: float) -> bool:
	var outline: PackedVector2Array = land_outline()
	var screen: Rect2 = Rect2(Vector2.ZERO, size).grow(-margin)
	for point: Vector2 in outline:
		if not screen.has_point(point):
			return false
	for rect: Rect2 in obstacles:
		var grown: Rect2 = rect.grow(margin)
		var corners: PackedVector2Array = [grown.position, Vector2(grown.end.x, grown.position.y), grown.end,
			Vector2(grown.position.x, grown.end.y)]
		if not Geometry2D.intersect_polygons(outline, corners).is_empty():
			return false
	return true


## Where the land's middle should sit: halfway between the HUD on the
## left and the HUD on the right, at mid height.
func _free_center() -> Vector2:
	var left: float = 0.0
	var right: float = size.x
	for rect: Rect2 in obstacles:
		# Only side panels steer the middle; a button up top only costs size.
		if rect.position.x < size.x * 0.25:
			left = maxf(left, rect.end.x)
		elif rect.end.x > size.x * 0.75:
			right = minf(right, rect.position.x)
	return Vector2((left + right) / 2.0, size.y / 2.0)


func _outline_center() -> Vector2:
	var outline: PackedVector2Array = land_outline()
	var bounds: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		bounds = bounds.expand(point)
	return bounds.get_center()


## Fits the land as large as it goes with nothing of it under the HUD, and
## sets the zoom limits around that.
func frame_town() -> void:
	distance = 6.0
	while distance < 80.0:
		# Start from the middle each time: up close, centering can run away.
		target = middle()
		for i: int in 3:
			_pan_unclamped(_free_center() - _outline_center())
		if _land_is_clear(12.0):
			break
		distance += 0.25
	max_distance = distance * 1.25
	min_distance = distance * 0.45


## Pans just enough to bring a world point onto the screen and out from
## under the HUD, so a selection never hides behind a panel.
func ensure_visible(world: Vector3, margin: float = 48.0) -> void:
	var at: Vector2 = to_screen(world)
	var goal: Vector2 = at.clamp(Vector2(margin, margin), size - Vector2(margin, margin))
	for rect: Rect2 in obstacles:
		if rect.grow(margin).has_point(goal):
			goal.x = rect.end.x + margin if rect.get_center().x < size.x / 2.0 else rect.position.x - margin
	if goal != at:
		pan(goal - at)


# --- Camera -------------------------------------------------------------------------------

func camera_transform() -> Transform3D:
	var yaw: float = deg_to_rad(YAW_DEGREES)
	var pitch: float = deg_to_rad(PITCH_DEGREES)
	var offset: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	return Transform3D(Basis(), target + offset).looking_at(target, Vector3.UP)


func projection() -> Projection:
	return Projection.create_perspective(FOV_DEGREES, size.x / size.y, NEAR, FAR)


## Where a world point lands on screen.
func to_screen(world: Vector3) -> Vector2:
	var local: Vector3 = camera_transform().affine_inverse() * world
	var clip: Vector4 = projection() * Vector4(local.x, local.y, local.z, 1.0)
	var ndc: Vector2 = Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * size.x, (1.0 - ndc.y) * 0.5 * size.y)


## The direction a screen point looks along, from the camera.
func ray_direction(point: Vector2) -> Vector3:
	var ndc: Vector2 = Vector2(point.x / size.x * 2.0 - 1.0, 1.0 - point.y / size.y * 2.0)
	var half: float = tan(deg_to_rad(FOV_DEGREES) / 2.0)
	var local: Vector3 = Vector3(ndc.x * half * size.x / size.y, ndc.y * half, -1.0)
	return (camera_transform().basis * local).normalized()


## Where a screen point meets the ground (y = 0), or null if it looks at the sky.
func ground_at(point: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera_transform().origin, ray_direction(point))


## The ground cell under a screen point, or NO_CELL off the map.
func cell_at(point: Vector2) -> Vector2i:
	var hit: Variant = ground_at(point)
	if hit == null:
		return NO_CELL
	var cell: Vector2i = Vector2i(floori((hit as Vector3).x), floori((hit as Vector3).z))
	return cell if map.in_bounds(cell) else NO_CELL


# --- Pan and zoom -------------------------------------------------------------------------

## Drags the town by a screen distance, so the ground under the pointer
## follows it.
func pan(by: Vector2) -> void:
	_pan_unclamped(by)
	_clamp_target()


func _pan_unclamped(by: Vector2) -> void:
	var from: Variant = ground_at(size / 2.0)
	var to: Variant = ground_at(size / 2.0 + by)
	if from != null and to != null:
		target += (from as Vector3) - (to as Vector3)


## Zooms by `factor` (above 1 is closer) around a screen point, so the
## ground under it stays put.
func zoom_at(point: Vector2, factor: float) -> void:
	var before: Variant = ground_at(point)
	distance = clampf(distance / factor, min_distance, max_distance)
	var after: Variant = ground_at(point)
	if before != null and after != null:
		target += (before as Vector3) - (after as Vector3)
	_clamp_target()


func _clamp_target() -> void:
	target.x = clampf(target.x, -PAN_SLACK, map.width + PAN_SLACK)
	target.z = clampf(target.z, -PAN_SLACK, map.height + PAN_SLACK)
	target.y = 0.0


# --- Where things stand -------------------------------------------------------------------

static func kind_of(data: GameData, building: Dictionary) -> String:
	return str(data.row("buildings", building["building"]).get("kind", "shop"))


## A placed building's solid box, roof included: what a click can hit.
static func block_box(data: GameData, building: Dictionary) -> AABB:
	var rect: Rect2i = Town.rect_of(data, building)
	var kind: String = kind_of(data, building)
	var height: float = BODY_HEIGHT.get(kind, 0.7) + ROOF_HEIGHT.get(kind, 0.5)
	return AABB(Vector3(rect.position.x + INSET, 0.0, rect.position.y + INSET),
		Vector3(rect.size.x - INSET * 2.0, height, rect.size.y - INSET * 2.0))


## Where the `index`th villager with nowhere to live waits: along the dock.
func dock_spot(index: int) -> Vector3:
	return Vector3(0.8 + index * 1.1, 0.06, map.land_rows + 0.75)


## Where a villager with a home stands: just outside it, on the first open
## side (the sea side first, so they face the camera), never inside another
## building.
func home_spot(data: GameData, town: Town, villager: String) -> Vector3:
	var rect: Rect2i = Town.rect_of(data, town.entry(town.homes[villager]))
	var center: Vector3 = Vector3(rect.position.x + rect.size.x / 2.0, 0.0, rect.position.y + rect.size.y / 2.0)
	var mid: Vector2i = rect.position + rect.size / 2
	var sides: Dictionary[Vector2i, Vector2i] = {
		Vector2i(0, 1): Vector2i(mid.x, rect.end.y), Vector2i(1, 0): Vector2i(rect.end.x, mid.y),
		Vector2i(-1, 0): Vector2i(rect.position.x - 1, mid.y), Vector2i(0, -1): Vector2i(mid.x, rect.position.y - 1),
	}
	for side: Vector2i in sides:
		var cell: Vector2i = sides[side]
		if map.in_bounds(cell) and map.ground(cell) != TownMap.Ground.SEA and town.building_at(data, cell).is_empty():
			return center + Vector3(side.x * (rect.size.x / 2.0 + 0.2), 0.0, side.y * (rect.size.y / 2.0 + 0.2))
	# Walled in on every side: stand on the doorstep anyway.
	return center + Vector3(0.0, 0.0, rect.size.y / 2.0 + 0.2)


## Every villager in town and where they stand: housed ones by their home,
## the rest along the dock.
func villager_spots(data: GameData, state: GameState) -> Dictionary[String, Vector3]:
	var out: Dictionary[String, Vector3] = {}
	for villager: String in state.town.homes:
		out[villager] = home_spot(data, state.town, villager)
	var homeless: Array[String] = state.homeless()
	for i: int in homeless.size():
		out[homeless[i]] = dock_spot(i)
	for villager: String in walking:
		if out.has(villager):
			out[villager] = walking[villager]
	return out


## Where the town stands to see a new landmark, best spot first (Mara's
## #46 review): every open spot within a step or two of it, on land or a
## path, never in a building; spots where a building would hide the
## villager or their bubble go last, and the rest run nearest the camera
## first. No two spots stand closer than a villager's width.
func gather_spots(data: GameData, town: Town, building: Dictionary, count: int) -> Array[Vector3]:
	var rect: Rect2i = Town.rect_of(data, building)
	var candidates: Array[Vector3] = []
	for ring: float in [0.45, 1.35]:
		for x: int in range(-1, rect.size.x + 1):
			candidates.append(Vector3(rect.position.x + x + 0.5, 0.06, rect.end.y + ring))
			candidates.append(Vector3(rect.position.x + x + 0.5, 0.06, rect.position.y - ring))
		for y: int in rect.size.y:
			candidates.append(Vector3(rect.position.x - ring, 0.06, rect.position.y + y + 0.5))
			candidates.append(Vector3(rect.end.x + ring, 0.06, rect.position.y + y + 0.5))
	var eye: Vector3 = camera_transform().origin
	var boxes: Array[AABB] = []
	for placed: Dictionary in town.placed:
		boxes.append(block_box(data, placed))
	var ranked: Array[Dictionary] = []
	for spot: Vector3 in candidates:
		var cell: Vector2i = Vector2i(floori(spot.x), floori(spot.z))
		if not map.in_bounds(cell) or map.ground(cell) == TownMap.Ground.SEA or not town.building_at(data, cell).is_empty():
			continue
		ranked.append({"spot": spot, "hidden": _hidden_by(spot, boxes, eye), "depth": eye.distance_to(spot)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["hidden"] != b["hidden"]:
			return not a["hidden"]
		return a["depth"] < b["depth"])
	var out: Array[Vector3] = []
	for entry: Dictionary in ranked:
		var spot: Vector3 = entry["spot"]
		if out.any(func(other: Vector3) -> bool: return other.distance_to(spot) < VILLAGER_SIZE.x * 1.6):
			continue
		out.append(spot)
		if out.size() == count:
			return out
	# Crowded in: whoever is left stands in a second row at the front.
	var i: int = 0
	while out.size() < count:
		out.append(Vector3(rect.position.x + 0.3 + (i % maxi(rect.size.x, 1)) * 0.9, 0.06, rect.end.y + 2.2))
		i += 1
	return out


## Whether a building nearer the camera than `spot` covers a villager
## standing there, bubble included, on screen.
func _hidden_by(spot: Vector3, boxes: Array[AABB], eye: Vector3) -> bool:
	var standing: Rect2 = screen_rect(villager_box(spot))
	var depth: float = eye.distance_to(spot)
	for box: AABB in boxes:
		var nearest: Vector3 = box.get_center().clamp(box.position, box.end)
		# The box's corner nearest the eye decides whether it's in front.
		for corner: int in 8:
			if eye.distance_to(box.get_endpoint(corner)) < eye.distance_to(nearest):
				nearest = box.get_endpoint(corner)
		if eye.distance_to(nearest) < depth and screen_rect(box).intersects(standing):
			return true
	return false


## A world box as it covers the screen: the bounds of its eight corners.
func screen_rect(box: AABB) -> Rect2:
	var out: Rect2 = Rect2(to_screen(box.get_endpoint(0)), Vector2.ZERO)
	for corner: int in range(1, 8):
		out = out.expand(to_screen(box.get_endpoint(corner)))
	return out


## Where a villager's mood bubble floats: its middle, above their head.
static func bubble_point(spot: Vector3) -> Vector3:
	return spot + Vector3(0.0, VILLAGER_SIZE.y + 0.12 + BUBBLE_SIZE / 2.0, 0.0)


## A villager's box, bubble included.
static func villager_box(spot: Vector3) -> AABB:
	var height: float = VILLAGER_SIZE.y + 0.12 + BUBBLE_SIZE
	return AABB(spot - Vector3(VILLAGER_SIZE.x / 2.0, 0.0, VILLAGER_SIZE.x / 2.0),
		Vector3(VILLAGER_SIZE.x, height, VILLAGER_SIZE.x))


# --- Picking ------------------------------------------------------------------------------

## What a click lands on: the nearest villager or building along the ray,
## then the ground.
## {"kind": "villager", "villager": id} | {"kind": "building", "uid": n}
## | {"kind": "cell", "cell": Vector2i} | {"kind": "none"}.
## `ground_only` looks through everything to the ground, for carrying.
func pick(point: Vector2, data: GameData, state: GameState, ground_only: bool = false) -> Dictionary:
	if not ground_only:
		var from: Vector3 = camera_transform().origin
		var direction: Vector3 = ray_direction(point)
		var best: Dictionary = {}
		var best_distance: float = INF
		var spots: Dictionary[String, Vector3] = villager_spots(data, state)
		for villager: String in spots:
			# Villagers are small, so they win ties with the house behind them.
			var hit: Variant = villager_box(spots[villager]).grow(0.05).intersects_ray(from, direction)
			if hit != null and from.distance_to(hit as Vector3) - 0.5 < best_distance:
				best_distance = from.distance_to(hit as Vector3) - 0.5
				best = {"kind": "villager", "villager": villager}
		for building: Dictionary in state.town.placed:
			var hit: Variant = block_box(data, building).intersects_ray(from, direction)
			if hit != null and from.distance_to(hit as Vector3) < best_distance:
				best_distance = from.distance_to(hit as Vector3)
				best = {"kind": "building", "uid": building["uid"]}
		if not best.is_empty():
			return best
	var cell: Vector2i = cell_at(point)
	if cell != NO_CELL:
		return {"kind": "cell", "cell": cell}
	return {"kind": "none"}
