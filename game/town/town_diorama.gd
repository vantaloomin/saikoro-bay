class_name TownDiorama
extends Node3D
## The town as a little 3D diorama (Vanta's HD-2D pick, Nov 3): greybox
## blocks for the ground and buildings, flat pixel villagers that face the
## camera with their mood above them, warm sun and bloom. It only draws:
## TownView holds the camera and the picking, and the sim holds the town.
## Placeholder shapes and colors until the town art lands.

const WALL: Color = Color(0.95, 0.91, 0.82)
const ROOF: Dictionary[String, Color] = {
	"home": Color(0.33, 0.4, 0.5), "shop": Color(0.55, 0.38, 0.25),
	"decor": Color(0.3, 0.27, 0.24), "landmark": Color(0.82, 0.27, 0.2),
}
const LOT: Color = Color(0.5, 0.66, 0.36)
const PATH: Color = Color(0.86, 0.78, 0.62)
const BEACH: Color = Color(0.93, 0.85, 0.66)
const SEA: Color = Color(0.16, 0.45, 0.52)
const EARTH: Color = Color(0.45, 0.33, 0.24)
const WOOD: Color = Color(0.6, 0.45, 0.3)
const DARK_WOOD: Color = Color(0.42, 0.3, 0.2)
const PINE: Color = Color(0.22, 0.42, 0.3)
const HILL: Color = Color(0.42, 0.6, 0.4)
const LAMP: Color = Color(1.0, 0.75, 0.4)
const HOVER: Color = Color(1.0, 0.98, 0.9)
## World units per sprite pixel: a 16 × 24 villager stands one cell tall.
const PIXEL: float = 0.042

var camera: Camera3D
## Rebuilt when the layout or the villagers change.
var _pieces: Node3D
var _hover_frame: Node3D
var _select_frame: Node3D
var _materials: Dictionary[String, StandardMaterial3D] = {}
var _spots: Dictionary[String, Vector3] = {}


## Builds the fixed parts once: light, sky, ground, sea and scenery.
func setup(map: TownMap) -> void:
	camera = Camera3D.new()
	camera.fov = TownView.FOV_DEGREES
	camera.near = TownView.NEAR
	camera.far = TownView.FAR
	add_child(camera)
	camera.current = true
	_add_light()
	_add_ground(map)
	_add_scenery(map)
	_pieces = Node3D.new()
	add_child(_pieces)
	_hover_frame = Node3D.new()
	add_child(_hover_frame)
	_select_frame = Node3D.new()
	add_child(_select_frame)


func sync_camera(view: TownView) -> void:
	camera.transform = view.camera_transform()


## Redraws the buildings and villagers from the sim.
func show_town(data: GameData, view: TownView, state: GameState) -> void:
	for child: Node in _pieces.get_children():
		child.queue_free()
	for building: Dictionary in state.town.placed:
		_add_building(data, building)
	_spots = view.villager_spots(data, state)
	for villager: String in _spots:
		_add_villager(villager, _spots[villager], state.mood(data, villager))


## Frames a pick result on the ground: thin and pale for hover, thick and
## vermilion for the selection. Brackets, not only color (two-halves 3).
func frame(data: GameData, state: GameState, hit: Dictionary, selected: bool) -> void:
	var holder: Node3D = _select_frame if selected else _hover_frame
	for child: Node in holder.get_children():
		child.queue_free()
	var area: Rect2 = Rect2()
	match str(hit.get("kind", "none")):
		"building":
			area = Rect2(Town.rect_of(data, state.town.entry(hit["uid"])))
		"villager":
			if not _spots.has(str(hit["villager"])):
				return
			var spot: Vector3 = _spots[str(hit["villager"])]
			area = Rect2(spot.x - 0.35, spot.z - 0.35, 0.7, 0.7)
		_:
			return
	var color: Color = TownStyle.SELECTED if selected else HOVER
	var thick: float = 0.09 if selected else 0.05
	var arm: float = minf(area.size.x, area.size.y) * 0.35
	var corners: Array[Vector2] = [area.position, Vector2(area.end.x, area.position.y), area.end,
		Vector2(area.position.x, area.end.y)]
	for i: int in corners.size():
		var corner: Vector2 = corners[i]
		var inward: Vector2 = (area.get_center() - corner).sign()
		var along_x: Vector3 = Vector3(corner.x + inward.x * arm / 2.0, 0.08, corner.y)
		var along_z: Vector3 = Vector3(corner.x, 0.08, corner.y + inward.y * arm / 2.0)
		holder.add_child(_glow_box(Vector3(arm, 0.03, thick), along_x, color))
		holder.add_child(_glow_box(Vector3(thick, 0.03, arm), along_z, color))


# --- Pieces -----------------------------------------------------------------------------

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s|%s" % [color, emission]
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material


func _box(parent: Node3D, box_size: Vector3, at: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	return _mesh(parent, mesh, at, color, emission)


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color, emission)
	instance.position = at
	parent.add_child(instance)
	return instance


## An unshaded bar that ignores the light, for selection frames.
func _glow_box(box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	return instance


func _add_light() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.8, 0.9)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.82, 0.92)
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.82
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.1
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	add_child(sun)


## A cheap per-cell shade so the ground reads as a grid. No RNG.
static func shade(cell: Vector2i) -> float:
	return float(((cell.x * 73856093) ^ (cell.y * 19349663)) & 7) / 7.0


func _add_ground(map: TownMap) -> void:
	var ground: Node3D = Node3D.new()
	add_child(ground)
	var width: float = map.width
	var land: float = map.land_rows
	# The diorama's base: a slab with earthy sides under the land.
	_box(ground, Vector3(width + 0.6, 0.9, land + 0.3), Vector3(width / 2.0, -0.5, land / 2.0 - 0.15), EARTH)
	for y: int in map.land_rows:
		for x: int in map.width:
			var cell: Vector2i = Vector2i(x, y)
			var lot: bool = map.ground(cell) == TownMap.Ground.LOT
			var color: Color = (LOT if lot else PATH).darkened(0.06 * shade(cell))
			_box(ground, Vector3(1.0, 0.1, 1.0), Vector3(x + 0.5, 0.0 if lot else -0.02, y + 0.5), color)
	_box(ground, Vector3(width + 0.6, 0.12, 0.45), Vector3(width / 2.0, -0.04, land + 0.1), BEACH)
	var sea: MeshInstance3D = _box(ground, Vector3(width + 14.0, 0.1, 8.0), Vector3(width / 2.0, -0.22, land + 4.3), SEA)
	sea.material_override = _material(SEA).duplicate() as StandardMaterial3D
	(sea.material_override as StandardMaterial3D).roughness = 0.15
	(sea.material_override as StandardMaterial3D).metallic_specular = 0.9
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The dock, where villagers with no home wait.
	_box(ground, Vector3(5.0, 0.08, 0.7), Vector3(2.8, 0.02, land + 0.75), WOOD)
	for post: float in [0.5, 2.0, 3.5, 5.1]:
		_box(ground, Vector3(0.12, 0.6, 0.12), Vector3(post, -0.2, land + 1.05), DARK_WOOD)


func _add_scenery(map: TownMap) -> void:
	var scenery: Node3D = Node3D.new()
	add_child(scenery)
	for x: int in range(-1, map.width + 2, 2):
		_tree(scenery, Vector3(x + 0.5 + 0.3 * shade(Vector2i(x, 1)), 0.0, -0.9 - 0.4 * shade(Vector2i(x, 2))))
	for y: int in range(1, map.land_rows, 2):
		_tree(scenery, Vector3(-0.9, 0.0, y + 0.3))
		_tree(scenery, Vector3(map.width + 0.9, 0.0, y + 0.6))
	for hill: Vector4 in [Vector4(-1.0, -5.5, 6.0, 2.6), Vector4(5.5, -6.5, 7.0, 3.4), Vector4(12.5, -5.5, 6.5, 2.8)]:
		var dome: SphereMesh = SphereMesh.new()
		dome.radius = hill.z
		dome.height = hill.w * 2.0
		dome.radial_segments = 24
		dome.rings = 12
		_mesh(scenery, dome, Vector3(hill.x, -0.4, hill.y), HILL)


func _tree(parent: Node3D, at: Vector3) -> void:
	_box(parent, Vector3(0.14, 0.4, 0.14), at + Vector3(0, 0.2, 0), DARK_WOOD)
	var crown: CylinderMesh = CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 0.42
	crown.height = 1.1
	crown.radial_segments = 8
	_mesh(parent, crown, at + Vector3(0, 0.9, 0), PINE)


func _add_building(data: GameData, building: Dictionary) -> void:
	var kind: String = TownView.kind_of(data, building)
	var box: AABB = TownView.block_box(data, building)
	var center: Vector3 = Vector3(box.get_center().x, 0.05, box.get_center().z)
	var foot: Vector2 = Vector2(box.size.x, box.size.z)
	var body: float = TownView.BODY_HEIGHT.get(kind, 0.7)
	if kind == "decor":
		# A lantern post: a pole and a glowing lamp, with a real light.
		_box(_pieces, Vector3(0.1, body, 0.1), center + Vector3(0, body / 2.0, 0), DARK_WOOD.darkened(0.3))
		_box(_pieces, Vector3(0.26, 0.3, 0.26), center + Vector3(0, body + 0.12, 0), LAMP, 3.0)
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.7, 0.4)
		lamp.light_energy = 1.2
		lamp.omni_range = 2.2
		lamp.position = center + Vector3(0, body + 0.1, 0)
		_pieces.add_child(lamp)
		return
	_box(_pieces, Vector3(foot.x, body, foot.y), center + Vector3(0, body / 2.0, 0), WALL)
	# A door and windows on the sea side, so a box reads as a house.
	_box(_pieces, Vector3(0.22, 0.34, 0.04), center + Vector3(0, 0.17, foot.y / 2.0 + 0.01), DARK_WOOD)
	if foot.x > 1.2:
		for side: float in [-1.0, 1.0]:
			_box(_pieces, Vector3(0.24, 0.16, 0.04), center + Vector3(side * foot.x * 0.3, body * 0.62, foot.y / 2.0 + 0.01),
				LAMP, 0.6)
	var roof: PrismMesh = PrismMesh.new()
	var roof_height: float = TownView.ROOF_HEIGHT.get(kind, 0.5)
	roof.size = Vector3(foot.y + 0.2, roof_height, foot.x + 0.2)
	var roof_node: MeshInstance3D = _mesh(_pieces, roof, center + Vector3(0, body + roof_height / 2.0, 0), ROOF.get(kind, ROOF["shop"]))
	roof_node.rotation_degrees = Vector3(0, 90, 0)
	if building["building"] == "hot_spring":
		_box(_pieces, Vector3(1.0, 0.06, 0.6), center + Vector3(0.9, 0.04, foot.y / 2.0 + 0.35),
			Color(0.55, 0.85, 0.9), 0.4)


func _sprite(image: Image, at: Vector3) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = PIXEL
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sprite.offset = Vector2(0, image.get_height() / 2.0)
	sprite.position = at
	_pieces.add_child(sprite)
	return sprite


func _add_villager(villager: String, spot: Vector3, mood: Town.Mood) -> void:
	_sprite(PixelArt.villager(villager), spot)
	var bubble: Sprite3D = _sprite(PixelArt.mood(mood), spot + Vector3(0, TownView.VILLAGER_SIZE.y + 0.12, 0))
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.shaded = false
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
