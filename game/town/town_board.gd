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
##
## Two more modes for PR 5b. Carrying a building shows it as a see-through
## ghost under the pointer, with the lot outlines, the spots that would
## make someone happier lit, and why it can't go where it is ("On a path");
## a click on a good spot emits `spot_chosen`. Picking a home for a
## villager frames every other home; a click on one emits `home_chosen`.
## Right click, B or Esc emits `cancelled` in either mode.

signal picked(hit: Dictionary)
signal spot_chosen(cell: Vector2i)
signal home_chosen(uid: int)
signal cancelled

enum Mode { LOOK, CARRY, PICK_HOME }

const TILT_SHIFT: Shader = preload("res://game/town/tilt_shift.gdshader")
const STICK_DEADZONE: float = 0.2
const CURSOR_SPEED: float = 900.0
const STICK_PAN_SPEED: float = 900.0
const KEY_STEP: float = 40.0
## A right-button press that moves less than this is a click, not a drag.
const DRAG_SLOP: float = 6.0
const WHEEL_ZOOM: float = 1.12
const TRIGGER_ZOOM: float = 1.8
const PARTY_SECONDS: float = 1.6
## Teal for "this would make someone happy": the happy bubble's color.
const WISH_FILL: Color = Color(0.25, 0.6, 0.5, 0.35)
const SWAP_MOOD: Dictionary[Town.Mood, String] = {
	Town.Mood.HAPPY: "happy", Town.Mood.UNHAPPY: "unhappy", Town.Mood.HOMELESS: "on the dock",
}

var view: TownView
var diorama: TownDiorama
var selected: Dictionary = {}
var hovered: Dictionary = {}
var _data: GameData
var _state: GameState
var _viewport: SubViewport
var _screen: TextureRect
## Marks that lie on the ground while carrying or picking a home: under
## the bubbles, so a dash never crosses a face (Mara's #42 review).
var _ground: Control
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
var mode: Mode = Mode.LOOK
## While carrying: the building, the placed one being moved (0 for a new
## one), its top-left cell under the pointer, and why it can't go there.
var carry_building: String = ""
var carry_lifted: int = 0
var carry_cell: Vector2i = TownView.NO_CELL
var carry_problem: String = ""
## A spot already chosen and waiting on the stamp: the ghost stays put.
var carry_held: bool = false
## Where the pointer can go to make someone happier (the sim's wish spots,
## moved from top-left corners to the cell the ghost hangs from).
var wish_cells: Array[Vector2i] = []
## While picking a home: whose.
var home_villager: String = ""
## A little paper burst over a new landmark: seconds left, and where.
var _party_left: float = 0.0
var _party_at: Vector3 = Vector3.ZERO


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
	_ground = Control.new()
	_ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
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
	diorama.show_town(_data, view, state, carry_lifted if mode == Mode.CARRY else 0)
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


## Where the HUD's panels sit on the board. Reframes the whole town clear
## of them.
func set_hud(rects: Array[Rect2]) -> void:
	view.obstacles = rects
	view.frame_town()
	_view_changed()


# --- Carrying and picking a home ---------------------------------------------------------

## Picks up `building_id` to place it, or placed building `lifted_uid` to
## move it. The ghost follows the pointer (or the cursor) from now on.
func start_carry(building_id: String, lifted_uid: int = 0) -> void:
	mode = Mode.CARRY
	carry_building = building_id
	carry_lifted = lifted_uid
	carry_held = false
	var offset: Vector2i = carry_offset(_data, building_id)
	wish_cells.clear()
	for spot: Vector2i in _state.wish_spots(_data, building_id, lifted_uid):
		wish_cells.append(spot + offset)
	if lifted_uid != 0:
		diorama.show_town(_data, view, _state, lifted_uid)
		var building: Dictionary = _state.town.entry(lifted_uid)
		_carry_to(Vector2i(building["x"], building["y"]) + offset)
	else:
		_carry_to(view.cell_at(_cursor) if _cursor_shown else TownView.NO_CELL)
	redraw_marks()


## Holds the ghost on its spot while the stamp is up, or lets it follow
## the pointer again.
func hold_carry(held: bool) -> void:
	carry_held = held
	redraw_marks()


## Back to looking: the ghost and the marks go, and a lifted building
## shows where it stands.
func stop_mode() -> void:
	var was_lifted: bool = mode == Mode.CARRY and carry_lifted != 0
	mode = Mode.LOOK
	carry_building = ""
	carry_lifted = 0
	carry_cell = TownView.NO_CELL
	carry_problem = ""
	carry_held = false
	wish_cells.clear()
	home_villager = ""
	diorama.hide_ghost()
	if was_lifted and _state != null:
		diorama.show_town(_data, view, _state)
	redraw_marks()


func start_home_pick(villager: String) -> void:
	stop_mode()
	mode = Mode.PICK_HOME
	home_villager = villager
	redraw_marks()


## Homes `home_villager` could move into: every home but their own.
func home_choices() -> Array[int]:
	var out: Array[int] = []
	for building: Dictionary in _state.town.placed:
		if TownView.kind_of(_data, building) == "home" and _state.town.homes.get(home_villager, 0) != building["uid"]:
			out.append(building["uid"])
	return out


## Where a footprint hangs from the pointer: its middle cell (the left or
## front one of two), so a big building sits around the pointer.
static func carry_offset(data: GameData, building_id: String) -> Vector2i:
	var row: Dictionary = data.row("buildings", building_id)
	return Vector2i((int(row.get("width", 1)) - 1) / 2, (int(row.get("height", 1)) - 1) / 2)


## Moves the ghost to hang from `cell`, and works out whether it fits.
func _carry_to(cell: Vector2i) -> void:
	if cell == TownView.NO_CELL:
		carry_cell = TownView.NO_CELL
		carry_problem = ""
		diorama.hide_ghost()
		return
	var top_left: Vector2i = cell - carry_offset(_data, carry_building)
	if top_left == carry_cell and diorama.has_ghost():
		return
	carry_cell = top_left
	carry_problem = _state.town.spot_problem(_data, view.map, carry_building, top_left, carry_lifted)
	diorama.show_ghost(_data, carry_building, top_left, carry_problem.is_empty())


## Paper scraps over a landmark just placed (LM-5); a still frame with
## reduce motion, since the notice board says it too.
func celebrate(uid: int) -> void:
	var building: Dictionary = _state.town.entry(uid)
	if building.is_empty() or Settings.reduce_motion:
		return
	var box: AABB = TownView.block_box(_data, building)
	_party_at = Vector3(box.get_center().x, box.end.y, box.get_center().z)
	_party_left = PARTY_SECONDS


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
	_ground.queue_redraw()
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
	elif event.is_action_pressed(&"ui_cancel") and mode != Mode.LOOK:
		cancelled.emit()
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
					if mode != Mode.LOOK:
						cancelled.emit()
					else:
						_pick_result({})
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				view.zoom_at(button.position, WHEEL_ZOOM if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM)
				_keep_selection_in_view()
				_view_changed()


func _process(delta: float) -> void:
	if view == null or _state == null:
		return
	if _party_left > 0.0:
		_party_left = maxf(_party_left - delta, 0.0)
		_overlay.queue_redraw()
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


## Shows the controller cursor at `point` (the middle of the view when
## carrying starts from a pad), as if it moved there.
func place_cursor(point: Vector2) -> void:
	_cursor = point.clamp(Vector2.ZERO, size)
	_cursor_shown = true
	_hover_at(_cursor)


func _move_cursor(by: Vector2) -> void:
	_cursor = (_cursor + by).clamp(Vector2.ZERO, size)
	_cursor_shown = true
	_hover_at(_cursor)


func _hover_at(point: Vector2) -> void:
	if mode == Mode.CARRY:
		if not carry_held:
			_carry_to(view.cell_at(point))
		_overlay.queue_redraw()
		return
	var hit: Dictionary = view.pick(point, _data, _state)
	if hit.get("kind", "none") not in ["building", "villager"]:
		hit = {}
	if hit != hovered:
		hovered = hit
	_overlay.queue_redraw()


func _pick_at(point: Vector2) -> void:
	match mode:
		Mode.CARRY:
			if carry_held:
				return
			_carry_to(view.cell_at(point))
			redraw_marks()
			if carry_cell != TownView.NO_CELL and carry_problem.is_empty():
				spot_chosen.emit(carry_cell)
		Mode.PICK_HOME:
			var hit: Dictionary = view.pick(point, _data, _state)
			if hit.get("kind", "") == "building" and home_choices().has(hit["uid"]):
				home_chosen.emit(hit["uid"])
		_:
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
		if show_all_names or (mode == Mode.LOOK and hovered.get("kind", "") == "building" and hovered["uid"] == building["uid"]):
			out.append(building["uid"])
	return out


## Screen pixels per world unit at a point, for sizing marks with distance.
func _scale_at(world: Vector3) -> float:
	return view.to_screen(world).distance_to(view.to_screen(world + Vector3.UP))


## Where a villager standing at `spot` is drawn on screen.
func sprite_rect(spot: Vector3) -> Rect2:
	var feet: Vector2 = view.to_screen(spot)
	var head: Vector2 = view.to_screen(spot + Vector3(0.0, TownView.VILLAGER_SIZE.y, 0.0))
	var half: float = (feet.y - head.y) * 0.3
	return Rect2(Vector2(feet.x - half, head.y), Vector2(half * 2.0, feet.y - head.y))


## Where each villager's mood bubble sits on screen.
func bubble_rects(spots: Dictionary[String, Vector3]) -> Dictionary[String, Rect2]:
	var out: Dictionary[String, Rect2] = {}
	for villager: String in spots:
		var middle: Vector3 = TownView.bubble_point(spots[villager])
		var side: float = TownView.BUBBLE_SIZE * _scale_at(middle)
		out[villager] = Rect2(view.to_screen(middle) - Vector2(side, side) / 2.0, Vector2(side, side))
	return out


func _draw_bubbles() -> void:
	if _state == null:
		return
	var rects: Dictionary[String, Rect2] = bubble_rects(view.villager_spots(_data, _state))
	for villager: String in rects:
		_bubbles.draw_texture_rect(_bubble_textures[_state.mood(_data, villager)], rects[villager], false)


func _draw_overlay() -> void:
	if _state == null:
		return
	var spots: Dictionary[String, Vector3] = view.villager_spots(_data, _state)
	if not hovered.is_empty() and hovered != selected and mode == Mode.LOOK:
		_draw_hover(hovered)
	if not selected.is_empty() and mode == Mode.LOOK:
		_draw_brackets(selected, TownStyle.INK, 4.0, true)
		if leader_target != Vector2.INF:
			var from: Vector2 = view.to_screen(anchor_of(selected))
			_overlay.draw_line(from, leader_target, TownStyle.WASHI, 6.0, true)
			_overlay.draw_line(from, leader_target, TownStyle.INK, 2.5, true)
			_overlay.draw_circle(from, 6.0, TownStyle.INK)
			_overlay.draw_circle(leader_target, 5.0, TownStyle.INK)
	var tags: Array[Dictionary] = map_tags(spots)
	for tag: Dictionary in tags:
		var rect: Rect2 = tag["rect"]
		var anchor: Vector2 = tag["anchor"]
		if absf(rect.position.y - anchor.y) > rect.size.y / 2.0:
			# Pushed off its owner: a tick says whose it is (Mara's #41
			# review). Ticks go first, so tags cover the ones that cross them.
			var top: Vector2 = Vector2(clampf(anchor.x, rect.position.x + 8.0, rect.end.x - 8.0), rect.position.y)
			_overlay.draw_line(anchor, top, TownStyle.WASHI, 4.0, true)
			_overlay.draw_line(anchor, top, TownStyle.INK, 2.0, true)
	for tag: Dictionary in tags:
		_draw_tag_in(tag["text"], tag["rect"], 0.85 if tag["kind"] == "villager" else 1.0)
	# What the pointer is about to do goes over every name.
	if mode == Mode.CARRY:
		_draw_carry_tag()
	elif mode == Mode.PICK_HOME:
		_draw_swap_tag()
	if _party_left > 0.0:
		_draw_party()
	if _cursor_shown:
		_overlay.draw_arc(_cursor, 16.0, 0.0, TAU, 32, TownStyle.WASHI, 6.0)
		_overlay.draw_arc(_cursor, 16.0, 0.0, TAU, 32, TownStyle.INK, 3.0)
		_overlay.draw_circle(_cursor, 3.0, TownStyle.INK)


## The ground marks while carrying: every lot's outline, the cells that
## would make someone happier (lit, with a small smile so it isn't color
## alone) and the ghost's footprint (solid where it fits, dashed where it
## doesn't). While picking a home, the homes to pick from are framed.
func _draw_ground() -> void:
	if _state == null:
		return
	if mode == Mode.PICK_HOME:
		for uid: int in home_choices():
			var hovering: bool = hovered.get("uid", 0) == uid
			_draw_brackets({"kind": "building", "uid": uid}, TownStyle.INK, 4.0 if hovering else 3.0, hovering, false, _ground)
		return
	if mode != Mode.CARRY:
		return
	for lot: Rect2i in view.map.lots:
		_draw_ground_rect(Rect2(lot.position, lot.size), Color(TownStyle.WASHI, 0.0), Color(TownStyle.WASHI, 0.9), 2.0, true)
	for cell: Vector2i in wish_cells:
		_draw_ground_rect(Rect2(cell, Vector2.ONE).grow(-0.06), WISH_FILL, Color(TownStyle.HAPPY, 0.9), 2.0, false)
		var middle: Vector2 = view.to_screen(Vector3(cell.x + 0.5, 0.0, cell.y + 0.5))
		var radius: float = 0.14 * _scale_at(Vector3(cell.x + 0.5, 0.0, cell.y + 0.5))
		_ground.draw_arc(middle, radius, 0.2, PI - 0.2, 12, TownStyle.WASHI, 3.0, true)
	if carry_cell != TownView.NO_CELL:
		var foot: Rect2i = Town.footprint(_data, carry_building, carry_cell)
		var fits: bool = carry_problem.is_empty()
		_draw_ground_rect(Rect2(foot.position, foot.size), Color(TownStyle.WASHI, 0.25 if fits else 0.0),
			TownStyle.INK, 3.0, not fits)


## The tag under the ghost: why it can't go here, or for a move, "Free"
## and anyone it would leave unhappy (with the rain cloud), so a free move
## never hides its cost (Mara's #42 review).
func _draw_carry_tag() -> void:
	if carry_cell == TownView.NO_CELL:
		return
	var foot: Rect2i = Town.footprint(_data, carry_building, carry_cell)
	var front: Vector2 = view.to_screen(Vector3(foot.end.x, 0.0, foot.end.y)) + Vector2(0, 10)
	if not carry_problem.is_empty():
		_draw_tag(carry_problem, front, false, 1.0)
	elif carry_lifted != 0:
		var losses: Array[String] = _state.wish_losses(_data, carry_building, carry_cell, carry_lifted)
		var words: PackedStringArray = [BuildList.FREE]
		for villager: String in losses:
			words.append("%s unhappy" % _data.row("villagers", villager).get("role", villager))
		_draw_mood_tag(" · ".join(words), front, Town.Mood.UNHAPPY if not losses.is_empty() else Town.Mood.HAPPY,
			not losses.is_empty())


## While picking a home: over the hovered home, how both villagers would
## feel after the swap.
func _draw_swap_tag() -> void:
	if hovered.get("kind", "") != "building" or not home_choices().has(hovered["uid"]):
		return
	var moods: Dictionary[String, Town.Mood] = _state.swap_moods(_data, home_villager, hovered["uid"])
	var words: PackedStringArray = []
	var any_unhappy: bool = false
	for villager: String in moods:
		var role: String = str(_data.row("villagers", villager).get("role", villager))
		words.append("%s %s" % [role, SWAP_MOOD[moods[villager]]])
		any_unhappy = any_unhappy or moods[villager] != Town.Mood.HAPPY
	var box: AABB = TownView.block_box(_data, _state.town.entry(hovered["uid"]))
	var front: Vector2 = view.to_screen(Vector3(box.end.x, 0.0, box.end.z)) + Vector2(0, 10)
	_draw_mood_tag(" · ".join(words), front, Town.Mood.UNHAPPY, any_unhappy)


## A tag with a mood bubble at its left when `show_icon`.
func _draw_mood_tag(text: String, at: Vector2, mood: Town.Mood, show_icon: bool) -> void:
	var rect: Rect2 = _keep_on_screen(_tag_rect(text, at, false))
	if not show_icon:
		_draw_tag_in(text, rect, 1.0)
		return
	var side: float = rect.size.y
	rect = _keep_on_screen(Rect2(rect.position - Vector2(side / 2.0, 0), rect.size + Vector2(side, 0)))
	_draw_tag_in("", rect, 1.0)
	_overlay.draw_texture_rect(_bubble_textures[mood], Rect2(rect.position + Vector2(6, 2), Vector2(side - 4, side - 4)), false)
	var text_rect: Rect2 = Rect2(rect.position + Vector2(side, 0), rect.size - Vector2(side, 0))
	_draw_tag_in(text, text_rect, 0.0)


## A rectangle of ground (in cells) as it lies on screen.
func _draw_ground_rect(rect: Rect2, fill: Color, line: Color, width: float, dashed: bool) -> void:
	var y: float = 0.03
	var corners: PackedVector2Array = [
		view.to_screen(Vector3(rect.position.x, y, rect.position.y)), view.to_screen(Vector3(rect.end.x, y, rect.position.y)),
		view.to_screen(Vector3(rect.end.x, y, rect.end.y)), view.to_screen(Vector3(rect.position.x, y, rect.end.y)),
	]
	if fill.a > 0.0:
		_ground.draw_colored_polygon(corners, fill)
	for i: int in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if dashed:
			_ground.draw_dashed_line(a, b, line, width, 10.0, true, true)
		else:
			_ground.draw_line(a, b, line, width, true)


func _draw_party() -> void:
	var at: Vector2 = view.to_screen(_party_at)
	var t: float = 1.0 - _party_left / PARTY_SECONDS
	var colors: Array[Color] = [TownStyle.WASHI, TownStyle.SAND, TownStyle.SEA, TownStyle.VERMILION]
	for i: int in 24:
		var angle: float = TAU * i / 24.0 + i * 0.37
		var speed: float = 120.0 + (i * 53) % 90
		var drift: Vector2 = Vector2(cos(angle), sin(angle) - 0.6) * speed * t + Vector2(0, 260.0 * t * t)
		var scrap: Rect2 = Rect2(at + drift - Vector2(5, 3), Vector2(10, 6))
		_overlay.draw_rect(scrap, Color(colors[i % colors.size()], 1.0 - t * t))


func _tag_font_size() -> int:
	return roundi(TownStyle.MAP_LABEL * text_scale)


## The name tags on the map, in drawing order, each {"text", "rect",
## "anchor", "kind"}: villager names under their feet, then building names
## (hovered, or all of them) under the building's front corner. They're
## pushed down past each other by priority (Mara's #41 and #42 reviews):
## mood bubbles and villager sprites never get covered, villager tags go
## around them, and building tags go around all of those. Every tag stays
## on screen.
func map_tags(spots: Dictionary[String, Vector3]) -> Array[Dictionary]:
	var taken: Array[Rect2] = []
	for rect: Rect2 in bubble_rects(spots).values():
		taken.append(rect)
	for villager: String in spots:
		taken.append(sprite_rect(spots[villager]))
	var villagers: Array[Dictionary] = []
	for villager: String in spots:
		var role: String = str(_data.row("villagers", villager).get("role", villager))
		var feet: Vector2 = view.to_screen(spots[villager])
		villagers.append({"text": role, "anchor": feet, "kind": "villager",
			"rect": _tag_rect(role, feet + Vector2(0, 6), false)})
	var buildings: Array[Dictionary] = []
	for uid: int in building_names():
		var building: Dictionary = _state.town.entry(uid)
		var foot: Rect2i = Town.rect_of(_data, building)
		var front: Vector2 = view.to_screen(Vector3(foot.end.x - TownView.INSET, 0.0, foot.end.y - TownView.INSET))
		var name: String = str(_data.row("buildings", building["building"]).get("name", building["building"]))
		buildings.append({"text": name, "anchor": front, "kind": "building", "rect": _tag_rect(name, front + Vector2(0, 4), false)})
	var out: Array[Dictionary] = []
	for group: Array[Dictionary] in [villagers, buildings]:
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["rect"] as Rect2).position.y < (b["rect"] as Rect2).position.y)
		for tag: Dictionary in group:
			var rect: Rect2 = _keep_on_screen(tag["rect"])
			for attempt: int in 12:
				var blocker: Rect2 = Rect2()
				for other: Rect2 in taken:
					if rect.grow(2.0).intersects(other):
						blocker = other
						break
				if blocker.size == Vector2.ZERO:
					break
				rect.position.y = blocker.end.y + 2.0
			rect = _keep_on_screen(rect)
			tag["rect"] = rect
			taken.append(rect)
			out.append(tag)
	return out


func _keep_on_screen(rect: Rect2) -> Rect2:
	rect.position = rect.position.clamp(Vector2(4, 4), size - rect.size - Vector2(4, 4))
	return rect


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
func _draw_brackets(hit: Dictionary, color: Color, width: float, selected_mark: bool, dashed: bool = false,
		canvas: Control = null) -> void:
	if canvas == null:
		canvas = _overlay
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
				canvas.draw_line(corner, end, TownStyle.WASHI, width + 4.0, true)
			if dashed:
				canvas.draw_dashed_line(corner, end, color, width, 5.0, true, true)
			else:
				canvas.draw_line(corner, end, color, width, true)


## Hover is lighter than a selection (Mara's #41 review): thin dashed
## corners at half strength, so a big hovered building never outweighs a
## small selected villager.
func _draw_hover(hit: Dictionary) -> void:
	_draw_brackets(hit, Color(TownStyle.INK, 0.5), 2.0, false, true)
