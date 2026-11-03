class_name TownScreen
extends Control
## The town, above the tide (M3 PR 5a): the diorama fills the screen and
## the HUD hugs the corners like things in the world (two-halves section 1):
## a ledger of resources, a notice board, the tide-shell action tray, a card
## for whatever is selected, and "Go down".
##
## "Go down" is a hold, so it needs no confirm, and its words say what's
## kept and lost (spec section 1). It never glows or nudges: a button that
## pushes the player would spoil the "second delve unprompted" signal.

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
const HOLD_HINT: String = "Hold to go down. On a controller, hold Y."

@onready var _board: TownBoard = %Board
@onready var _ledger: PanelContainer = %Ledger
@onready var _notice: PanelContainer = %Notice
@onready var _card: PanelContainer = %Card
@onready var _tray_panel: PanelContainer = %Tray
@onready var _go_down: HoldButton = %GoDown
@onready var _hold_hint: Label = %HoldHint
@onready var _quit: Button = %Quit

var _shells: ShellTray


func _ready() -> void:
	for panel: PanelContainer in [_ledger, _notice, _card, _tray_panel]:
		panel.add_theme_stylebox_override("panel", TownStyle.panel())
	TownStyle.style_button(_go_down, TownStyle.TITLE)
	TownStyle.style_button(_quit)
	_hold_hint.add_theme_font_size_override("font_size", TownStyle.SMALL)
	_hold_hint.add_theme_color_override("font_color", TownStyle.INK)
	_hold_hint.text = HOLD_HINT
	_go_down.held.connect(_on_go_down_held)
	_quit.pressed.connect(get_tree().quit)
	_board.setup(Game.data, GameState.town_map(Game.data))
	_board.picked.connect(_on_picked)
	refresh()
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


## Holding Y anywhere holds "Go down" (two-halves section 3).
func _input(event: InputEvent) -> void:
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button == null or button.button_index != JOY_BUTTON_Y:
		return
	if button.pressed:
		_go_down.start_hold()
	else:
		_go_down.stop_hold()
	get_viewport().set_input_as_handled()


func _on_go_down_held() -> void:
	Game.go_down()


func _on_picked(hit: Dictionary) -> void:
	_show_card(hit)


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
					else "Home of the %s." % data.row("villagers", resident).get("role", resident))
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
