class_name LandingPanel
extends Control
## The landing (DM-3, specs/delve-map.md section 8, Mara's review #1, #2,
## #5): the delve's wager. Surface and Deeper sit side by side at the same
## size, each with what it means in numbers:
##   Surface  keep everything, with the whole haul
##   Deeper   "If you wash up, you keep" with the halves, who goes back
##            below the tide, and a peek at the next floor and its prize
## HP shows large. Nothing has focus when it appears, so the first press
## only picks a side (left for Surface, right for Deeper), and presses are
## ignored for GUARD_MS, so nobody mashes through a wager.

signal surface_chosen
signal deeper_chosen

const GUARD_MS: int = 400
const COLUMN_WIDTH: float = 760.0
const PEEK_ROOM: float = 64.0

var data: GameData

var _guard_until: int = 0
var _title: Label
var _hp: Label
var _hp_bar: HpBar
var _keep: VBoxContainer
var _risk: VBoxContainer
var _below: VBoxContainer
var _surface: Button
var _deeper: Button
var _hint: Label
var _notes: Label


## A row of peeked rooms, drawn with the map's shapes.
class PeekRow:
	extends Control
	var types: Array = []

	func _init(row_types: Array) -> void:
		types = row_types
		custom_minimum_size = Vector2(types.size() * (PEEK_ROOM + 20), PEEK_ROOM)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i: int in types.size():
			MapGlyphs.draw_room(self, Rect2(i * (PEEK_ROOM + 20), 0, PEEK_ROOM, PEEK_ROOM), str(types[i]), BoardStyle.INK, 3.0)


func setup(game_data: GameData) -> void:
	data = game_data


func _ready() -> void:
	theme = BoardStyle.theme()
	_build()


func show_view(view: RunView) -> void:
	_title.text = "Landing · floor %d of %d" % [view.floor_index() + 1, view.floor_count()]
	_hp.text = "HP %d / %d" % [view.hp(), view.max_hp()]
	_hp_bar.max_hp = view.max_hp()
	_hp_bar.hp = view.hp()
	var haul: Haul = view.haul()
	_clear(_keep)
	_clear(_risk)
	_clear(_below)
	_keep.add_child(_heading("Back to town with everything"))
	for line: String in keep_lines(haul):
		_keep.add_child(BoardStyle.label(line, BoardStyle.BODY))
	_keep.add_child(_heading("You leave behind"))
	for line: String in left_behind_lines(view.peek()):
		_keep.add_child(BoardStyle.label(line, BoardStyle.BODY))
	_risk.add_child(_heading("If you wash up, you keep"))
	for line: String in risk_lines(haul):
		_risk.add_child(BoardStyle.label(line, BoardStyle.BODY))
	var peek: Dictionary = view.peek()
	_below.add_child(_heading(below_text(peek)))
	var peek_rows: Array = peek.get("rows", []) as Array
	for i: int in peek_rows.size():
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var row_label: Label = BoardStyle.label("Row %d" % (i + 1), BoardStyle.SMALL, BoardStyle.DIM)
		row_label.custom_minimum_size = Vector2(70, 0)
		line.add_child(row_label)
		line.add_child(PeekRow.new(peek_rows[i] as Array))
		_below.add_child(line)
	var source: String = view.foresight_source()
	if not source.is_empty():
		var badge: HBoxContainer = HBoxContainer.new()
		badge.add_theme_constant_override("separation", 10)
		var chip: FaceChip = FaceChip.new()
		chip.villager_id = source
		chip.role = _role(source)
		badge.add_child(chip)
		badge.add_child(BoardStyle.label("Foresight · %s: you see two rows" % _role(source), BoardStyle.SMALL, BoardStyle.DIM))
		_below.add_child(badge)
	_hint.text = ""
	_guard_until = Time.get_ticks_msec() + GUARD_MS
	var owner_now: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner_now != null:
		owner_now.release_focus()


## The Surface side: the whole haul.
func keep_lines(haul: Haul) -> PackedStringArray:
	var lines: PackedStringArray = []
	for id: String in data.ids("resources"):
		if haul.resource(id) > 0:
			lines.append("%s  %d" % [data.row("resources", id)["name"], haul.resource(id)])
	for villager: String in haul.villagers:
		lines.append("The %s comes home with you" % _role(villager).to_lower())
	if lines.is_empty():
		lines.append("Nothing yet")
	return lines


## The Surface side's cost: what's below that you won't reach this delve
## (Mara, #29), so the safe choice has weight too.
func left_behind_lines(peek: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var prize: Dictionary = peek.get("prize", {}) as Dictionary
	if prize.has("rescue"):
		lines.append("The caged %s waits for another delve" % _role(str(prize["rescue"])).to_lower())
	if prize.has("vault"):
		var vault_prize: Dictionary = prize["vault"] as Dictionary
		if vault_prize.has("landmark"):
			lines.append("Koban keeps the %s for now" % data.row("landmarks", str(vault_prize["landmark"]))["name"])
		else:
			lines.append("Koban keeps her vault for now")
	if not peek.is_empty():
		var floors_left: int = int(peek["floor"])
		lines.append("Floor %d's loot" % (floors_left + 1))
	return lines


## What the rooms since the last stop gave, under the title.
func show_notes(lines: PackedStringArray) -> void:
	_notes.text = "" if lines.is_empty() else "Since your last stop: " + " · ".join(lines)


## The Deeper side: what a wash-up leaves you (Haul.halved), and who goes
## back below the tide.
func risk_lines(haul: Haul) -> PackedStringArray:
	var lines: PackedStringArray = []
	var halved: Haul = haul.halved()
	for id: String in data.ids("resources"):
		if haul.resource(id) > 0:
			lines.append("%s  %d → %d" % [data.row("resources", id)["name"], haul.resource(id), halved.resource(id)])
	for villager: String in haul.villagers:
		lines.append("The %s goes back below the tide" % _role(villager).to_lower())
	if lines.is_empty():
		lines.append("Nothing to lose yet")
	return lines


## "Below: floor 2 · a caged villager (Shipwright)" or "Below: floor 3 ·
## Koban's vault · the Café".
func below_text(peek: Dictionary) -> String:
	if peek.is_empty():
		return ""
	var text: String = "Below: floor %d" % (int(peek["floor"]) + 1)
	var prize: Dictionary = peek.get("prize", {}) as Dictionary
	if prize.has("rescue"):
		text += " · a caged villager (%s)" % _role(str(prize["rescue"]))
	elif prize.has("vault"):
		text += " · Koban's vault"
		var vault_prize: Dictionary = prize["vault"] as Dictionary
		if vault_prize.has("landmark"):
			text += " · the %s" % data.row("landmarks", str(vault_prize["landmark"]))["name"]
		elif vault_prize.has("resources"):
			var parts: PackedStringArray = []
			var amounts: Dictionary = vault_prize["resources"] as Dictionary
			for id: Variant in amounts:
				parts.append("%d %s" % [amounts[id], data.row("resources", str(id))["name"]])
			text += " · " + ", ".join(parts)
	return text


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	# Nothing focused: the first press only picks a side.
	if event.is_action_pressed("ui_left"):
		_surface.grab_focus()
	elif event.is_action_pressed("ui_right"):
		_deeper.grab_focus()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_hint.text = "Left for Surface, right for Deeper"
	else:
		return
	get_viewport().set_input_as_handled()


func _on_surface() -> void:
	if Time.get_ticks_msec() >= _guard_until:
		surface_chosen.emit()


func _on_deeper() -> void:
	if Time.get_ticks_msec() >= _guard_until:
		deeper_chosen.emit()


func _role(villager: String) -> String:
	return str(data.row("villagers", villager)["role"]) if data.has_row("villagers", villager) else villager


func _heading(text: String) -> Label:
	var l: Label = BoardStyle.label(text, BoardStyle.NUMBER, BoardStyle.GOLD)
	l.add_theme_font_override("font", BoardStyle.strong_font())
	return l


static func _clear(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = BoardStyle.BACKGROUND
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var torii: Control = Control.new()
	torii.custom_minimum_size = Vector2(120, 120)
	torii.position = Vector2(900, 30)
	torii.draw.connect(func() -> void: MapGlyphs.draw_torii(torii, Rect2(Vector2.ZERO, Vector2(120, 120)), BoardStyle.GOLD))
	add_child(torii)
	_title = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.GOLD)
	_title.add_theme_font_override("font", BoardStyle.title_font())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(0, 156)
	_title.size = Vector2(1920, 60)
	add_child(_title)
	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_row.add_theme_constant_override("separation", 24)
	hp_row.position = Vector2(0, 224)
	hp_row.size = Vector2(1920, 72)
	add_child(hp_row)
	_hp = BoardStyle.label("", BoardStyle.BIG)
	_hp.add_theme_font_override("font", BoardStyle.strong_font())
	hp_row.add_child(_hp)
	_hp_bar = HpBar.new()
	_hp_bar.custom_minimum_size = Vector2(360, 32)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)

	var gap: float = 80.0
	var left_x: float = (1920.0 - COLUMN_WIDTH * 2 - gap) / 2.0
	var surface_col: VBoxContainer = _column(Vector2(left_x, 330))
	_keep = VBoxContainer.new()
	_keep.add_theme_constant_override("separation", 10)
	surface_col.add_child(_keep)
	var deeper_col: VBoxContainer = _column(Vector2(left_x + COLUMN_WIDTH + gap, 330))
	_risk = VBoxContainer.new()
	_risk.add_theme_constant_override("separation", 10)
	deeper_col.add_child(_risk)
	_below = VBoxContainer.new()
	_below.add_theme_constant_override("separation", 10)
	deeper_col.add_child(_below)

	# The two choices, the same size, along the bottom: never where the
	# fight's "Continue" was.
	_surface = _choice("Surface")
	_surface.position = Vector2(left_x, 860)
	_surface.pressed.connect(_on_surface)
	add_child(_surface)
	_deeper = _choice("Go deeper")
	_deeper.position = Vector2(left_x + COLUMN_WIDTH + gap, 860)
	_deeper.pressed.connect(_on_deeper)
	add_child(_deeper)
	_surface.focus_neighbor_right = _surface.get_path_to(_deeper)
	_deeper.focus_neighbor_left = _deeper.get_path_to(_surface)
	_notes = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	_notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notes.position = Vector2(0, 296)
	_notes.size = Vector2(1920, 30)
	add_child(_notes)
	_hint = BoardStyle.label("", BoardStyle.BODY, BoardStyle.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, 790)
	_hint.size = Vector2(1920, 40)
	add_child(_hint)


func _column(at: Vector2) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BoardStyle.panel(BoardStyle.DIM))
	panel.position = at
	panel.custom_minimum_size = Vector2(COLUMN_WIDTH, 490)
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	panel.add_child(col)
	return col


func _choice(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(COLUMN_WIDTH, 96)
	b.add_theme_font_size_override("font_size", BoardStyle.NUMBER)
	b.add_theme_font_override("font", BoardStyle.strong_font())
	for state: String in ["normal", "hover", "pressed"]:
		var box: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD)
		if state != "normal":
			box.bg_color = BoardStyle.FELT
		b.add_theme_stylebox_override(state, box)
	var focus: StyleBoxFlat = BoardStyle.panel(BoardStyle.INK, Color(0, 0, 0, 0))
	focus.set_border_width_all(5)
	b.add_theme_stylebox_override("focus", focus)
	for key: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(key, BoardStyle.INK)
	return b
