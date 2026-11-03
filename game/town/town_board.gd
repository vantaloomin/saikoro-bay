class_name TownBoard
extends Control
## The town map on screen: the diorama rendered into a viewport, through the
## tilt-shift lens, filling the screen under the HUD. Free pan and zoom
## (two-halves section 1): drag with the right or middle mouse button, wheel
## to zoom; on a controller the left stick moves a free cursor, the right
## stick pans and the triggers zoom. Left click or A picks what's under the
## pointer and emits `picked`; right click (without a drag) or B clears it.
##
## Everything the player has to read sits on an overlay after the lens, so
## the blur never touches it (Mara's #41 review): mood bubbles, villager
## names (always shown), building names (on hover, or all of them while Alt
## or the left stick click is held), selection brackets in ink, and a leader
## line to the card.

signal picked(hit: Dictionary)

const TILT_SHIFT: Shader = preload("res://game/town/tilt_shift.gdshader")
const STICK_DEADZONE: float = 0.2
const CURSOR_SPEED: float = 900.0
const STICK_PAN_SPEED: float = 900.0
const KEY_STEP: float = 40.0
## A right-button press that moves less than this is a click, not a drag.
const DRAG_SLOP: float = 6.0
const WHEEL_ZOOM: float = 1.12
const TRIGGER_ZOOM: float = 1.8

var view: TownView
var diorama: TownDiorama
var selected: Dictionary = {}
var hovered: Dictionary = {}
var _data: GameData
var _state: GameState
var _viewport: SubViewport
var _screen: TextureRect
var _bubbles: Control
var _overlay: Control
## Where the card's edge is, in board pixels, for the leader line; INF for none.
var leader_target: Vector2 = Vector2.INF
var show_all_names: bool = false
## Grows the map's name tags with the HUD on small screens.
var text_scale: float = 1.0
var _bubble_textures: Dictionary[Town.Mood, ImageTexture] = {}
var _font: Font = ThemeDB.fallback_font
var _cursor: Vector2 = Vector2.ZERO
## Shown once a controller or the arrow keys move it; the mouse hides it.
var _cursor_shown: bool = false
var _dragging: bool = false
var _drag_moved: float = 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_viewport = SubViewport.new()
	_viewport.msaa_3d = Viewport.MSAA_4X
	# HDR keeps the glow to the lamps; without it the sky blooms white.
	_viewport.use_hdr_2d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_screen = TextureRect.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.texture = _viewport.get_texture()
	var lens: ShaderMaterial = ShaderMaterial.new()
	lens.shader = TILT_SHIFT
	_screen.material = lens
	add_child(_screen)
	# Pixel bubbles scale with nearest filtering; text stays smooth.
	_bubbles = Control.new()
	_bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubbles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubbles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bubbles.draw.connect(_draw_bubbles)
	add_child(_bubbles)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	for mood: Town.Mood in [Town.Mood.HAPPY, Town.Mood.UNHAPPY, Town.Mood.HOMELESS]:
		_bubble_textures[mood] = ImageTexture.create_from_image(PixelArt.mood(mood))
	resized.connect(_on_resized)


## Builds the world for this town's map. Call once, before show_state.
func setup(data: GameData, map: TownMap) -> void:
	_data = data
	diorama = TownDiorama.new()
	_viewport.add_child(diorama)
	diorama.setup(map)
	var screen_size: Vector2 = size if size.x > 0.0 and size.y > 0.0 else Vector2(1920, 1080)
	_viewport.size = Vector2i(screen_size)
	view = TownView.make(map, screen_size)
	_cursor = screen_size / 2.0
	_view_changed()


## Redraws the town from the sim, keeping the selection if it still exists.
func show_state(state: GameState) -> void:
	_state = state
	diorama.show_town(_data, view, state)
	if not _still_there(selected):
		selected = {}
	if not _still_there(hovered):
		hovered = {}
	redraw_marks()


func select(hit: Dictionary) -> void:
	selected = hit if hit.get("kind", "none") in ["building", "villager"] else {}
	if _state != null and not selected.is_empty():
		view.ensure_visible(anchor_of(selected))
		_view_changed()
	redraw_marks()


## The part of the board the HUD leaves clear. Reframes the whole town.
func set_safe_area(area: Rect2) -> void:
	view.safe = area
	view.frame_town()
	_view_changed()


func _still_there(hit: Dictionary) -> bool:
	match str(hit.get("kind", "none")):
		"building":
			return not _state.town.entry(hit["uid"]).is_empty()
		"villager":
			return _state.villagers().has(str(hit["villager"]))
	return false


func _on_resized() -> void:
	if view == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_viewport.size = Vector2i(size)
	view.size = size
	_view_changed()


func _view_changed() -> void:
	diorama.sync_camera(view)
	redraw_marks()


func redraw_marks() -> void:
	_bubbles.queue_redraw()
	_overlay.queue_redraw()


# --- Input --------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if view == null or _state == null:
		return
	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse_motion != null:
		_cursor_shown = false
		if _dragging:
			_drag_moved += mouse_motion.relative.length()
			view.pan(mouse_motion.relative)
			_view_changed()
		_hover_at(mouse_motion.position)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		accept_event()
		return
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed and joy_button.button_index == JOY_BUTTON_A:
		_pick_at(_cursor)
		accept_event()
		return
	if event is InputEventJoypadMotion:
		# The sticks are read in _process; don't let them also step focus.
		accept_event()
		return
	for direction: StringName in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		if event.is_action_pressed(direction, true):
			_move_cursor(_direction_of(direction) * KEY_STEP)
			accept_event()
			return
	if event.is_action_pressed(&"ui_accept"):
		_pick_at(_cursor)
		accept_event()
	elif event.is_action_pressed(&"ui_cancel") and not selected.is_empty():
		_pick_result({})
		accept_event()


static func _direction_of(action: StringName) -> Vector2:
	match action:
		&"ui_left":
			return Vector2.LEFT
		&"ui_right":
			return Vector2.RIGHT
		&"ui_up":
			return Vector2.UP
	return Vector2.DOWN


func _on_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			if button.pressed:
				_cursor_shown = false
				_pick_at(button.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if button.button_index == MOUSE_BUTTON_RIGHT and _drag_moved < DRAG_SLOP:
					_pick_result({})
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				view.zoom_at(button.position, WHEEL_ZOOM if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM)
				_keep_selection_in_view()
				_view_changed()


func _process(delta: float) -> void:
	if view == null or _state == null:
		return
	var all_names: bool = Input.is_key_pressed(KEY_ALT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
	if all_names != show_all_names:
		show_all_names = all_names
		_overlay.queue_redraw()
	if not has_focus():
		return
	var left: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if left.length() > STICK_DEADZONE:
		_move_cursor(left * CURSOR_SPEED * delta)
	var right: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if right.length() > STICK_DEADZONE:
		view.pan(-right * STICK_PAN_SPEED * delta)
		_view_changed()
	var zoom: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(zoom) > STICK_DEADZONE:
		view.zoom_at(_cursor if _cursor_shown else size / 2.0, pow(TRIGGER_ZOOM, zoom * delta))
		_keep_selection_in_view()
		_view_changed()


func _keep_selection_in_view() -> void:
	if not selected.is_empty():
		view.ensure_visible(anchor_of(selected))


func _move_cursor(by: Vector2) -> void:
	_cursor = (_cursor + by).clamp(Vector2.ZERO, size)
	_cursor_shown = true
	_hover_at(_cursor)


func _hover_at(point: Vector2) -> void:
	var hit: Dictionary = view.pick(point, _data, _state)
	if hit.get("kind", "none") not in ["building", "villager"]:
		hit = {}
	if hit != hovered:
		hovered = hit
	_overlay.queue_redraw()


func _pick_at(point: Vector2) -> void:
	_pick_result(view.pick(point, _data, _state))


func _pick_result(hit: Dictionary) -> void:
	select(hit)
	picked.emit(hit)


# --- Overlay ------------------------------------------------------------------------------

## The point a selection's leader line and keep-in-view aim at: a
## building's roof, or a villager's middle.
func anchor_of(hit: Dictionary) -> Vector3:
	match str(hit.get("kind", "none")):
		"building":
			var box: AABB = TownView.block_box(_data, _state.town.entry(hit["uid"]))
			return Vector3(box.get_center().x, box.end.y, box.get_center().z)
		"villager":
			var spot: Vector3 = view.villager_spots(_data, _state).get(str(hit["villager"]), Vector3.ZERO)
			return spot + Vector3(0.0, TownView.VILLAGER_SIZE.y / 2.0, 0.0)
	return Vector3.ZERO


## Building names on screen right now: the hovered one, or all of them
## while the show-all input is held.
func building_names() -> Array[int]:
	var out: Array[int] = []
	for building: Dictionary in _state.town.placed:
		if show_all_names or (hovered.get("kind", "") == "building" and hovered["uid"] == building["uid"]):
			out.append(building["uid"])
	return out


## Screen pixels per world unit at a point, for sizing marks with distance.
func _scale_at(world: Vector3) -> float:
	return view.to_screen(world).distance_to(view.to_screen(world + Vector3.UP))


func _draw_bubbles() -> void:
	if _state == null:
		return
	var spots: Dictionary[String, Vector3] = view.villager_spots(_data, _state)
	for villager: String in spots:
		var middle: Vector3 = TownView.bubble_point(spots[villager])
		var side: float = TownView.BUBBLE_SIZE * _scale_at(middle)
		var at: Vector2 = view.to_screen(middle)
		_bubbles.draw_texture_rect(_bubble_textures[_state.mood(_data, villager)],
			Rect2(at - Vector2(side, side) / 2.0, Vector2(side, side)), false)


func _draw_overlay() -> void:
	if _state == null:
		return
	var spots: Dictionary[String, Vector3] = view.villager_spots(_data, _state)
	if not hovered.is_empty() and hovered != selected:
		_draw_brackets(hovered, TownStyle.WASHI, 3.0, false)
	if not selected.is_empty():
		_draw_brackets(selected, TownStyle.INK, 4.0, true)
		if leader_target != Vector2.INF:
			var from: Vector2 = view.to_screen(anchor_of(selected))
			_overlay.draw_line(from, leader_target, TownStyle.WASHI, 6.0, true)
			_overlay.draw_line(from, leader_target, TownStyle.INK, 2.5, true)
			_overlay.draw_circle(from, 6.0, TownStyle.INK)
			_overlay.draw_circle(leader_target, 5.0, TownStyle.INK)
	for tag: Dictionary in villager_tags(spots):
		_draw_tag_in(tag["text"], tag["rect"], 0.85)
	for uid: int in building_names():
		var building: Dictionary = _state.town.entry(uid)
		var box: AABB = TownView.block_box(_data, building)
		var roof: Vector3 = Vector3(box.get_center().x, box.end.y, box.get_center().z)
		_draw_tag(str(_data.row("buildings", building["building"]).get("name", building["building"])),
			view.to_screen(roof) + Vector2(0, -12), true, 1.0)
	if _cursor_shown:
		_overlay.draw_arc(_cursor, 16.0, 0.0, TAU, 32, TownStyle.WASHI, 6.0)
		_overlay.draw_arc(_cursor, 16.0, 0.0, TAU, 32, TownStyle.INK, 3.0)
		_overlay.draw_circle(_cursor, 3.0, TownStyle.INK)


func _tag_font_size() -> int:
	return roundi(TownStyle.MAP_LABEL * text_scale)


## Villager name tags under their feet, nudged down past each other so
## two neighbors' names never cover one another: [{"text", "rect"}].
func villager_tags(spots: Dictionary[String, Vector3]) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	for villager: String in spots:
		var role: String = str(_data.row("villagers", villager).get("role", villager))
		tags.append({"text": role, "rect": _tag_rect(role, view.to_screen(spots[villager]) + Vector2(0, 6), false)})
	tags.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["rect"] as Rect2).position.y < (b["rect"] as Rect2).position.y)
	for i: int in tags.size():
		var rect: Rect2 = tags[i]["rect"]
		for j: int in i:
			var placed: Rect2 = tags[j]["rect"]
			if rect.grow(2.0).intersects(placed):
				rect.position.y = placed.end.y + 2.0
		tags[i]["rect"] = rect
	return tags


func _tag_rect(text: String, at: Vector2, above: bool) -> Rect2:
	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size())
	var box_size: Vector2 = text_size + Vector2(20, 8)
	var top: float = at.y - box_size.y if above else at.y
	return Rect2(Vector2(at.x - box_size.x / 2.0, top), box_size)


## A small washi name tag, centered on `at`: hanging above it, or sitting
## below it.
func _draw_tag(text: String, at: Vector2, above: bool, opacity: float) -> void:
	_draw_tag_in(text, _tag_rect(text, at, above), opacity)


func _draw_tag_in(text: String, box: Rect2, opacity: float) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(TownStyle.WASHI, opacity)
	style.border_color = Color(TownStyle.LOT_LINE, opacity)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_overlay.draw_style_box(style, box)
	_overlay.draw_string(_font, Vector2(box.position.x + 10, box.end.y - 4 - _font.get_descent(_tag_font_size()) * 0.5),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size(), TownStyle.INK)


## Corner brackets around a pick: around a building's block, or around a
## villager standing up. Ink over a washi edge, so they read on any ground.
func _draw_brackets(hit: Dictionary, color: Color, width: float, selected_mark: bool) -> void:
	var corners: PackedVector2Array = []
	match str(hit.get("kind", "none")):
		"building":
			# Around the whole block as it stands on screen: ground marks
			# would hide behind its walls.
			var box: AABB = TownView.block_box(_data, _state.town.entry(hit["uid"]))
			var bounds: Rect2 = Rect2(view.to_screen(box.position), Vector2.ZERO)
			for i: int in 8:
				bounds = bounds.expand(view.to_screen(box.get_endpoint(i)))
			bounds = bounds.grow(6.0)
			corners = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end,
				Vector2(bounds.position.x, bounds.end.y)]
		"villager":
			var spot: Vector3 = view.villager_spots(_data, _state).get(str(hit["villager"]), Vector3.ZERO)
			var feet: Vector2 = view.to_screen(spot)
			var head: Vector2 = view.to_screen(spot + Vector3(0.0, TownView.VILLAGER_SIZE.y, 0.0))
			var half: float = (feet.y - head.y) * 0.4
			corners = [Vector2(feet.x - half, head.y - 6), Vector2(feet.x + half, head.y - 6),
				Vector2(feet.x + half, feet.y + 4), Vector2(feet.x - half, feet.y + 4)]
		_:
			return
	for i: int in corners.size():
		var corner: Vector2 = corners[i]
		for other: Vector2 in [corners[(i + 1) % 4], corners[(i + 3) % 4]]:
			var end: Vector2 = corner.lerp(other, 0.28)
			if selected_mark:
				_overlay.draw_line(corner, end, TownStyle.WASHI, width + 4.0, true)
			_overlay.draw_line(corner, end, color, width, true)
