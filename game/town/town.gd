class_name TownScreen
extends Control
## The town, above the tide (M3 PR 5a): the diorama fills the screen and
## the HUD hugs the corners like things in the world (two-halves section 1):
## a ledger of resources, a notice board, the tide-shell action tray, a card
## for whatever is selected, and "Go down". The town is framed in the space
## between the HUD columns, and the HUD grows on small screens (Mara's #41
## review).
##
## "Go down" is a hold, so it needs no confirm, and its words say what's
## kept and lost (spec section 1). It only moves when touched: a button that
## glows or pushes the player would spoil the "second delve unprompted"
## signal. Quit lives in the pause menu (Start or Esc), away from it.

## What the notice board says about the last delve. An abandoned delve is
## said plainly, so a player who quit mid-delve knows what it cost.
const ARRIVAL: Dictionary[String, String] = {
	Haul.SURFACED: "You surfaced with your whole haul.",
	Haul.CLEARED: "You beat Koban and came up with everything.",
	Haul.WASHED_UP: "You washed up in a barrel. You kept half your resources. Anyone you rescued went back below the tide.",
	Haul.ABANDONED: "The game closed mid-delve, so that delve doesn't count. Your actions are back, and the same delve is waiting with fresh rolls. What you found down there is lost.",
}
const FIRST_VISIT: String = "Your first visit to Saikoro Bay. Look around, then go down when you're ready."
const MOOD_WORDS: Dictionary[Town.Mood, String] = {
	Town.Mood.HAPPY: "Happy with their home",
	Town.Mood.UNHAPPY: "Not happy with their home yet",
	Town.Mood.HOMELESS: "Has nowhere to live, so they wait on the dock",
}
## The short form, after a resident's name on a home's card.
const MOOD_SHORT: Dictionary[Town.Mood, String] = {
	Town.Mood.HAPPY: "happy", Town.Mood.UNHAPPY: "not happy yet", Town.Mood.HOMELESS: "",
}
## The hint under "Go down", by the input last used. The button itself
## teaches the hold; the hint fades after the first real one.
const HOLD_HINT_MOUSE: String = "Hold to go down"
const HOLD_HINT_PAD: String = "Hold"
## Text below about 20 px is hard to read; past this canvas-to-screen scale
## the HUD grows to keep body text near 24 px (SA-6, the Deck at 1280 × 800).
const HUD_TARGET_SCALE: float = 0.92
const HUD_MAX_GROWTH: float = 1.3

@onready var _board: TownBoard = %Board
@onready var _ledger: PanelContainer = %Ledger
@onready var _right_column: VBoxContainer = $RightColumn
@onready var _notice: PanelContainer = %Notice
@onready var _card: PanelContainer = %Card
@onready var _tray_panel: PanelContainer = %Tray
@onready var _actions: VBoxContainer = $Actions
@onready var _go_down: HoldButton = %GoDown
@onready var _hold_hint: HBoxContainer = %HoldHint
@onready var _menu_button: Button = %MenuButton
@onready var _pause_menu: PauseMenu = %PauseMenu

var _shells: ShellTray
## Whether a controller was the last input, for the hint's wording.
var using_pad: bool = false
var hud_scale: float = 1.0


func _ready() -> void:
	for panel: PanelContainer in [_ledger, _notice, _card, _tray_panel]:
		panel.add_theme_stylebox_override("panel", TownStyle.panel())
	TownStyle.style_button(_go_down, TownStyle.TITLE)
	TownStyle.style_button(_menu_button, TownStyle.SMALL)
	_go_down.held.connect(_on_go_down_held)
	_menu_button.pressed.connect(_pause_menu.open)
	_menu_button.focus_mode = Control.FOCUS_NONE
	_pause_menu.closed.connect(SceneFlow.focus_default)
	_board.setup(Game.data, GameState.town_map(Game.data))
	_board.picked.connect(_on_picked)
	_card.resized.connect(_aim_leader)
	_card.visibility_changed.connect(_aim_leader)
	get_viewport().size_changed.connect(_fit_hud)
	_show_hint()
	refresh()
	_fit_hud.call_deferred()
	SceneFlow.focus_default()


## Redraws everything from the sim.
func refresh() -> void:
	_board.show_state(Game.state)
	_fill(_ledger, "Ledger", _ledger_rows())
	var notice: Array[Control] = []
	for line: String in notice_lines(Game.data, Game.state, Game.save_problem):
		notice.append(TownStyle.label(line))
	_fill(_notice, "Notice board", notice)
	_shells = ShellTray.new()
	_shells.show_state(Game.data, Game.state)
	_fill(_tray_panel, "Actions", [_shells])
	_go_down.text = Game.state.go_down_label(Game.data)
	_show_card(_board.selected)


func _input(event: InputEvent) -> void:
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if pad and (event as InputEventJoypadMotion == null or absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_pad(true)
	elif event is InputEventMouseButton or event is InputEventKey:
		_set_pad(false)
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button == null or _pause_menu.visible:
		return
	# Holding Y anywhere holds "Go down" (two-halves section 3).
	if button.button_index == JOY_BUTTON_Y:
		if button.pressed:
			_go_down.start_hold()
		else:
			_go_down.stop_hold()
		get_viewport().set_input_as_handled()
	elif button.button_index == JOY_BUTTON_START and button.pressed:
		_pause_menu.open()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_pause_menu.toggle()
		get_viewport().set_input_as_handled()


func _on_go_down_held() -> void:
	if Game.go_down():
		Settings.set_go_down_learned()
		_fade_hint()


func _on_picked(hit: Dictionary) -> void:
	_show_card(hit)


# --- Hint, HUD size and framing -------------------------------------------------------------

func _set_pad(pad: bool) -> void:
	if pad != using_pad:
		using_pad = pad
		_show_hint()


## "Hold to go down" with a mouse; a Y glyph and "Hold" on a controller.
func _show_hint() -> void:
	for old: Node in _hold_hint.get_children():
		old.free()
	_hold_hint.visible = not Settings.go_down_learned
	if using_pad:
		var glyph: PanelContainer = PanelContainer.new()
		var ring: StyleBoxFlat = StyleBoxFlat.new()
		ring.bg_color = TownStyle.INK
		ring.set_corner_radius_all(20)
		ring.set_content_margin_all(4)
		ring.content_margin_left = 12
		ring.content_margin_right = 12
		glyph.add_theme_stylebox_override("panel", ring)
		var letter: Label = TownStyle.label("Y", TownStyle.BODY, TownStyle.WASHI)
		letter.autowrap_mode = TextServer.AUTOWRAP_OFF
		glyph.add_child(letter)
		_hold_hint.add_child(glyph)
	var words: Label = TownStyle.label(hint_text(), TownStyle.BODY)
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hold_hint.add_child(words)


func hint_text() -> String:
	return HOLD_HINT_PAD if using_pad else HOLD_HINT_MOUSE


func _fade_hint() -> void:
	if Settings.reduce_motion or not is_inside_tree():
		_hold_hint.visible = false
		return
	create_tween().tween_property(_hold_hint, "modulate:a", 0.0, TownStyle.EASE_SECONDS)


## Grows the HUD on small screens, then frames the town in what's left.
func _fit_hud() -> void:
	var scale_now: float = get_viewport().get_final_transform().get_scale().x
	hud_scale = clampf(HUD_TARGET_SCALE / maxf(scale_now, 0.01), 1.0, HUD_MAX_GROWTH)
	_ledger.pivot_offset = Vector2.ZERO
	_right_column.pivot_offset = Vector2(_right_column.size.x, 0.0)
	_tray_panel.pivot_offset = Vector2(0.0, _tray_panel.size.y)
	_actions.pivot_offset = _actions.size
	for part: Control in [_ledger, _right_column, _tray_panel, _actions]:
		part.scale = Vector2(hud_scale, hud_scale)
	_board.text_scale = hud_scale
	_board.set_hud(hud_rects())
	_aim_leader()


## The HUD's panels in board pixels, for framing the town clear of them.
## The right column is reserved down to "Go down", so a card opening later
## never covers the land.
func hud_rects() -> Array[Rect2]:
	var to_board: Transform2D = _board.get_global_transform().affine_inverse() * get_global_transform()
	var column: Rect2 = _scaled_rect(_right_column)
	var actions: Rect2 = _scaled_rect(_actions)
	column.size.y = actions.position.y - column.position.y
	var out: Array[Rect2] = []
	for rect: Rect2 in [_scaled_rect(_ledger), _scaled_rect(_tray_panel), column, actions, _scaled_rect(_menu_button)]:
		out.append(to_board * rect)
	return out


static func _scaled_rect(part: Control) -> Rect2:
	var top_left: Vector2 = part.position + part.pivot_offset * (Vector2.ONE - part.scale)
	return Rect2(top_left, part.size * part.scale)


## Points the board's leader line at the card's left edge.
func _aim_leader() -> void:
	if not _card.visible:
		_board.leader_target = Vector2.INF
	else:
		var card: Rect2 = _card.get_global_rect()
		_board.leader_target = _board.get_global_transform().affine_inverse() * Vector2(card.position.x, card.position.y + 40.0 * hud_scale)
	_board.redraw_marks()


# --- Words ----------------------------------------------------------------------------------

## The notice board: how the last delve ended and what came back, who has
## nowhere to live, and any save trouble.
static func notice_lines(data: GameData, state: GameState, save_problem: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var last: Dictionary = state.last_delve
	var outcome: String = str(last.get("outcome", ""))
	if ARRIVAL.has(outcome):
		lines.append(ARRIVAL[outcome])
		var kept: Dictionary = (last.get("kept", {}) as Dictionary).get("resources", {}) as Dictionary
		var parts: PackedStringArray = []
		for id: Variant in kept:
			parts.append("%s %d" % [str(data.row("resources", str(id)).get("name", id)), int(kept[id])])
		if not parts.is_empty():
			lines.append("Brought back: " + ", ".join(parts))
	elif state.delve_count == 0:
		lines.append(FIRST_VISIT)
	var homeless: String = state.homeless_line(data)
	if not homeless.is_empty():
		lines.append(homeless)
	if not save_problem.is_empty():
		lines.append(save_problem)
	return lines


## What the card says about a pick: {"title", "lines", "chip", "quote"},
## or {} for nothing worth a card (the ground).
static func card_for(data: GameData, state: GameState, hit: Dictionary) -> Dictionary:
	match str(hit.get("kind", "none")):
		"building":
			var building: Dictionary = state.town.entry(hit["uid"])
			if building.is_empty():
				return {}
			var row: Dictionary = data.row("buildings", building["building"])
			var lines: PackedStringArray = [str(row.get("text", ""))]
			if row.get("kind", "") == "home":
				var resident: String = state.town.resident(hit["uid"])
				lines.append("Nobody lives here yet." if resident.is_empty()
					else "Home of the %s · %s" % [data.row("villagers", resident).get("role", resident),
						MOOD_SHORT[state.mood(data, resident)]])
			return {"title": str(row.get("name", building["building"])), "lines": lines, "chip": "", "quote": ""}
		"villager":
			var villager: String = str(hit["villager"])
			if not data.has_row("villagers", villager):
				return {}
			var row: Dictionary = data.row("villagers", villager)
			return {
				"title": str(row.get("role", villager)),
				"lines": PackedStringArray([MOOD_WORDS[state.mood(data, villager)]]),
				"chip": "Wish: " + str(row.get("wish_text", "")),
				"quote": "“%s”" % row.get("wish_line", ""),
			}
	return {}


# --- Panels ---------------------------------------------------------------------------------

func _ledger_rows() -> Array[Control]:
	var rows: Array[Control] = []
	for id: String in Game.data.ids("resources"):
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = TownStyle.label(str(Game.data.row("resources", id).get("name", id)))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var amount: Label = TownStyle.label(str(Game.state.resource(id)))
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(amount)
		rows.append(row)
	return rows


## Replaces a panel's contents with a title and `children`.
func _fill(panel: PanelContainer, title: String, children: Array[Control]) -> void:
	for old: Node in panel.get_children():
		panel.remove_child(old)
		old.queue_free()
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.add_child(TownStyle.label(title, TownStyle.TITLE))
	for child: Control in children:
		stack.add_child(child)
	panel.add_child(stack)


func _show_card(hit: Dictionary) -> void:
	var card: Dictionary = card_for(Game.data, Game.state, hit)
	_card.visible = not card.is_empty()
	if card.is_empty():
		return
	var children: Array[Control] = []
	for line: String in card["lines"]:
		children.append(TownStyle.label(line))
	if not str(card["chip"]).is_empty():
		var chip: PanelContainer = PanelContainer.new()
		var chip_style: StyleBoxFlat = StyleBoxFlat.new()
		chip_style.bg_color = TownStyle.SAND
		chip_style.border_color = TownStyle.LOT_LINE
		chip_style.set_border_width_all(2)
		chip_style.set_corner_radius_all(18)
		chip_style.set_content_margin_all(10)
		chip.add_theme_stylebox_override("panel", chip_style)
		chip.add_child(TownStyle.label(str(card["chip"]), TownStyle.SMALL))
		children.append(chip)
	if not str(card["quote"]).is_empty():
		children.append(TownStyle.label(str(card["quote"]), TownStyle.BODY, TownStyle.DIM))
	_fill(_card, str(card["title"]), children)
