class_name TownBoard
extends Control
## The town map on screen: the diorama rendered into a viewport, through the
## tilt-shift lens, filling the screen under the HUD. Free pan and zoom
## (two-halves section 1): drag with the right or middle mouse button, wheel
## to zoom; on a controller the left stick moves a free cursor, the right
## stick pans and the triggers zoom. Left click or A picks what's under the
## pointer and emits `picked`; right click (without a drag) or B clears it.

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
var _overlay: Control
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
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
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
	diorama.frame(_data, state, selected, true)
	diorama.frame(_data, state, hovered, false)
	_overlay.queue_redraw()


func select(hit: Dictionary) -> void:
	selected = hit if hit.get("kind", "none") in ["building", "villager"] else {}
	if _state != null:
		diorama.frame(_data, _state, selected, true)


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
				_view_changed()


func _process(delta: float) -> void:
	if view == null or _state == null or not has_focus():
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
		_view_changed()


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
		diorama.frame(_data, _state, hovered, false)
	_overlay.queue_redraw()


func _pick_at(point: Vector2) -> void:
	_pick_result(view.pick(point, _data, _state))


func _pick_result(hit: Dictionary) -> void:
	select(hit)
	picked.emit(hit)
	_overlay.queue_redraw()


# --- Overlay ------------------------------------------------------------------------------

## What the hovered thing is called, so names never need a click.
func hover_name() -> String:
	match str(hovered.get("kind", "none")):
		"building":
			var building: Dictionary = _state.town.entry(hovered["uid"])
			return str(_data.row("buildings", building["building"]).get("name", building["building"]))
		"villager":
			return str(_data.row("villagers", str(hovered["villager"])).get("role", hovered["villager"]))
	return ""


func _hover_anchor() -> Vector3:
	match str(hovered.get("kind", "none")):
		"building":
			var box: AABB = TownView.block_box(_data, _state.town.entry(hovered["uid"]))
			return Vector3(box.get_center().x, box.end.y, box.get_center().z)
		"villager":
			var spot: Vector3 = view.villager_spots(_data, _state).get(str(hovered["villager"]), Vector3.ZERO)
			return spot + Vector3(0.0, TownView.VILLAGER_SIZE.y + 0.12 + TownView.BUBBLE_SIZE, 0.0)
	return Vector3.ZERO


func _draw_overlay() -> void:
	if _state == null:
		return
	var label: String = hover_name()
	if not label.is_empty():
		var at: Vector2 = view.to_screen(_hover_anchor()) + Vector2(0, -18)
		var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TownStyle.MAP_LABEL)
		var box: Rect2 = Rect2(at - Vector2(text_size.x / 2.0 + 12, text_size.y + 10), text_size + Vector2(24, 14))
		var style: StyleBoxFlat = TownStyle.panel()
		style.set_content_margin_all(0)
		style.shadow_size = 4
		style.set_corner_radius_all(10)
		_overlay.draw_style_box(style, box)
		_overlay.draw_string(_font, Vector2(box.position.x + 12, box.end.y - 10), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TownStyle.MAP_LABEL, TownStyle.INK)
	if _cursor_shown:
		_overlay.draw_arc(_cursor, 16.0, 0.0, TAU, 32, TownStyle.WASHI, 6.0)
		_overlay.draw_arc(_cursor, 16.0, 0.0, TAU, 32, TownStyle.INK, 3.0)
		_overlay.draw_circle(_cursor, 3.0, TownStyle.INK)
