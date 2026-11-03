class_name TownDiorama
extends Node3D
## The town as a little 3D diorama (Vanta's HD-2D pick, Nov 3): greybox
## blocks for the ground and buildings, flat pixel villagers that face the
## camera, warm sun and bloom. It only draws: TownView holds the camera and
## the picking, and the sim holds the town. Mood bubbles, names and
## selection marks sit on TownBoard's overlay, after the lens, so they stay
## sharp (Mara's #41 review).
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
## World units per sprite pixel: a 16 × 24 villager stands one cell tall.
const PIXEL: float = 0.042

var camera: Camera3D
## Rebuilt when the layout or the villagers change.
var _pieces: Node3D
var _materials: Dictionary[String, StandardMaterial3D] = {}
## The building being carried, see-through, where it would go.
var _ghost: Node3D
## Set while drawing the ghost: every material comes out see-through.
var _ghost_alpha: float = 0.0
## Each villager's sprite, so a walk can move it.
var _villagers: Dictionary[String, Sprite3D] = {}


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
	_ghost = Node3D.new()
	add_child(_ghost)


func sync_camera(view: TownView) -> void:
	camera.transform = view.camera_transform()


## Redraws the buildings and villagers from the sim. `lifted_uid` is a
## building being moved: it's drawn as the ghost instead.
func show_town(data: GameData, view: TownView, state: GameState, lifted_uid: int = 0) -> void:
	for child: Node in _pieces.get_children():
		child.queue_free()
	for building: Dictionary in state.town.placed:
		if building["uid"] != lifted_uid:
			_add_building(data, building, _pieces)
	var spots: Dictionary[String, Vector3] = view.villager_spots(data, state)
	_villagers.clear()
	for villager: String in spots:
		_villagers[villager] = _sprite(PixelArt.villager(villager), spots[villager])


## Moves a villager's sprite without rebuilding the town, for a walk,
## `opacity` see-through (below 1 only across a hop with no way round).
func move_villager(villager: String, spot: Vector3, opacity: float = 1.0) -> void:
	var sprite: Sprite3D = _villagers.get(villager)
	if sprite != null and is_instance_valid(sprite):
		sprite.position = spot
		sprite.modulate.a = opacity
		# The alpha cut would drop a half-faded sprite all at once.
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD if opacity >= 1.0 else SpriteBase3D.ALPHA_CUT_DISABLED


## Shows `building_id` see-through with its top-left corner at `cell`:
## fainter where it can't go. The overlay draws its outline and the reason.
func show_ghost(data: GameData, building_id: String, cell: Vector2i, fits: bool) -> void:
	hide_ghost()
	_ghost_alpha = 0.7 if fits else 0.35
	_add_building(data, {"uid": 0, "building": building_id, "x": cell.x, "y": cell.y}, _ghost)
	_ghost_alpha = 0.0


func has_ghost() -> bool:
	return _ghost.get_child_count() > 0


func hide_ghost() -> void:
	for child: Node in _ghost.get_children():
		child.free()


# --- Pieces -----------------------------------------------------------------------------

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s|%s|%s" % [color, emission, _ghost_alpha]
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	if _ghost_alpha > 0.0:
		material.albedo_color.a = _ghost_alpha
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	var sea: MeshInstance3D = _box(ground, Vector3(width + 80.0, 0.1, 40.0), Vector3(width / 2.0, -0.22, land + 20.3), SEA)
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


func _add_building(data: GameData, building: Dictionary, parent: Node3D) -> void:
	var kind: String = TownView.kind_of(data, building)
	var box: AABB = TownView.block_box(data, building)
	var center: Vector3 = Vector3(box.get_center().x, 0.05, box.get_center().z)
	var foot: Vector2 = Vector2(box.size.x, box.size.z)
	var body: float = TownView.BODY_HEIGHT.get(kind, 0.7)
	if kind == "decor":
		# A lantern post: a pole and a glowing lamp, with a real light.
		_box(parent, Vector3(0.1, body, 0.1), center + Vector3(0, body / 2.0, 0), DARK_WOOD.darkened(0.3))
		_box(parent, Vector3(0.26, 0.3, 0.26), center + Vector3(0, body + 0.12, 0), LAMP, 3.0)
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.7, 0.4)
		lamp.light_energy = 1.2
		lamp.omni_range = 2.2
		lamp.position = center + Vector3(0, body + 0.1, 0)
		parent.add_child(lamp)
		return
	_box(parent, Vector3(foot.x, body, foot.y), center + Vector3(0, body / 2.0, 0), WALL)
	# A door and windows on the sea side, so a box reads as a house.
	_box(parent, Vector3(0.22, 0.34, 0.04), center + Vector3(0, 0.17, foot.y / 2.0 + 0.01), DARK_WOOD)
	if foot.x > 1.2:
		for side: float in [-1.0, 1.0]:
			_box(parent, Vector3(0.24, 0.16, 0.04), center + Vector3(side * foot.x * 0.3, body * 0.62, foot.y / 2.0 + 0.01),
				LAMP, 0.6)
	var roof: PrismMesh = PrismMesh.new()
	var roof_height: float = TownView.ROOF_HEIGHT.get(kind, 0.5)
	roof.size = Vector3(foot.y + 0.2, roof_height, foot.x + 0.2)
	var roof_node: MeshInstance3D = _mesh(parent, roof, center + Vector3(0, body + roof_height / 2.0, 0), ROOF.get(kind, ROOF["shop"]))
	roof_node.rotation_degrees = Vector3(0, 90, 0)
	if building["building"] == "hot_spring":
		_box(parent, Vector3(1.0, 0.06, 0.6), center + Vector3(0.9, 0.04, foot.y / 2.0 + 0.35),
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
