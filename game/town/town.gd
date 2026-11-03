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
##
## Building (PR 5b): the right column has two tabs, "Notice board" and
## "Build" (LB/RB, the B key, or X with nothing selected). A row you can
## build picks it up at once; any other row opens its card, which says why
## not yet. A costed build is confirmed with the hanko stamp, the town's
## only confirm, with the shell and resources it would spend previewed.
## Free things never ask: placing a won landmark (the town celebrates),
## moving a building (with an undo for the last move), and moving a
## villager to another home.
##
## Landmark arrival (PR 5c, LM-5): a landmark won on the last delve is the
## first thing on arrival, and the visit's budget (the shell tray) waits
## until it's placed or put off. Placed, the town walks over to see it,
## the changed bubbles pop, and only then does the notice board say
## everyone came out, with the shells after it.
##
## The kit (M4 PR 2, specs/bridge.md section 5): a third tab, "Kit" (K, or
## the shoulders), shows the dice the next delve takes, plain ones grouped
## into one "Standard" row and each changed one a strip of its faces with
## the changes outlined and a chip saying who and what, then every perk
## with its gain (a villager's happy bonus folded in) and cost. A read-only
## strip of blank mini dice above Go down opens it. A shop's Build card and
## stamp say what it adds to the kit, and while the stamp is up the strip
## previews it.

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
## The hint under "Go down", by the input last used. The button itself
## teaches the hold; the hint fades after the first real one.
const HOLD_HINT_MOUSE: String = "Hold to go down"
const HOLD_HINT_PAD: String = "Hold"
## Text below about 20 px is hard to read; past this canvas-to-screen scale
## the HUD grows to keep body text near 24 px (SA-6, the Deck at 1280 × 800).
const HUD_TARGET_SCALE: float = 0.92
const HUD_MAX_GROWTH: float = 1.3
const PICK_A_SPOT: String = "Pick a spot"
## Until 5c stages the villagers walking over, the notice only says what
## you can see (Mara's #42 review).
const CHEER: String = "The %s is open."
const GATHERED: String = "Everyone came out to see the %s."
const MOVED_IN: String = "The %s moved into the new %s."
const TAB_NOTICE: String = "Notice board"
const TAB_BUILD: String = "Build"
## The kit (specs/bridge.md section 5): what the town gives the next delve.
const TAB_KIT: String = "Kit"
const TABS: Array[String] = [TAB_NOTICE, TAB_BUILD, TAB_KIT]
const NO_PERKS: String = "No perks yet. Each villager you rescue and each shop you build adds one."
## The room between the notice board and a card under it.
const COLUMN_GAP: float = 16.0
## How far the tabs sit in from the sheet's sides, past its round corners.
const TAB_INSET: int = 18
const MUSIC_PATH: String = "res://content/sfw/music/town_loop.ogg"
const MUSIC_DB: float = -14.0
const MUSIC_FADE_SECONDS: float = 1.5
const SHELLS_FILL_SECONDS: float = 0.5
## The widest a ledger amount gets: the stamp's spend preview.
const AMOUNT_ROOM: String = "00 → 00"

## The width AMOUNT_ROOM takes in the town's type, measured once.
static var _amount_width: float = 0.0

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
## What the right column shows instead of the selection's card, if
## anything: {"kind": "list"}, {"kind": "building", "id"} (a card from the
## list), {"kind": "carry", "id", "uid"} (uid 0 for a new building),
## {"kind": "confirm", "id", "cell"} (the stamp), or {"kind": "home",
## "villager"}.
var sheet: Dictionary = {}
## The last free move, for its undo: {"uid", "cell"} where it came from.
var last_move: Dictionary = {}
## Said on the notice board after a landmark is placed.
var _cheer: String = ""
var _stamp: HankoButton
var _kit_strip: KitMarks.Strip
var _tabs: Dictionary[String, Button] = {}
## Between the notice board and a card under it. The tabs sit flush on
## whichever sheet is first.
var _column_gap: Control
var sounds: TownSounds
var music: AudioStreamPlayer
## The landmark the arrival is staged round: the tray waits while it's
## the open card, being carried, or the town is gathering to see it.
var staging: String = ""
## The landmark the town is gathering round, and its name.
var _gathering: Dictionary = {}
## Shells lit from the left while they fill in after the staging; -1 is all.
var _shells_lit: int = -1
var _shells_waited: bool = false


func _ready() -> void:
	# The HUD frame (M3 PR 5c): each panel is a thing in the town, not a
	# window. The pause menu keeps its neutral skin (two-halves section 2).
	theme = TownStyle.theme()
	_ledger.add_theme_stylebox_override("panel", PaperBox.make(PaperBox.Kind.LEDGER))
	_notice.add_theme_stylebox_override("panel", PaperBox.make(PaperBox.Kind.BOARD))
	_card.add_theme_stylebox_override("panel", TownStyle.panel())
	_tray_panel.add_theme_stylebox_override("panel", PaperBox.make(PaperBox.Kind.TRAY))
	_right_column.add_theme_constant_override("separation", 0)
	_column_gap = Control.new()
	_column_gap.name = "Gap"
	_column_gap.custom_minimum_size = Vector2(0, COLUMN_GAP)
	_column_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_column.add_child(_column_gap)
	_right_column.move_child(_column_gap, _card.get_index())
	TownStyle.style_button(_go_down, TownStyle.TITLE)
	TownStyle.style_button(_menu_button, TownStyle.SMALL)
	_go_down.held.connect(_on_go_down_held)
	_menu_button.pressed.connect(_pause_menu.open)
	_menu_button.focus_mode = Control.FOCUS_NONE
	_pause_menu.closed.connect(SceneFlow.focus_default)
	sounds = TownSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)
	_start_music()
	_make_tabs()
	_kit_strip = KitMarks.Strip.new()
	_kit_strip.name = "KitStrip"
	_kit_strip.pressed.connect(toggle_kit)
	_actions.add_child(_kit_strip)
	_actions.move_child(_kit_strip, 0)
	_board.setup(Game.data, GameState.town_map(Game.data))
	_board.picked.connect(_on_picked)
	_board.spot_chosen.connect(_on_spot_chosen)
	_board.spot_refused.connect(sounds.play.bind("refuse").unbind(1))
	_board.gathered.connect(_on_gathered)
	_board.home_chosen.connect(_on_home_chosen)
	_board.cancelled.connect(back)
	_card.resized.connect(_aim_leader)
	_card.visibility_changed.connect(_aim_leader)
	get_viewport().size_changed.connect(_fit_hud)
	_show_hint()
	var waiting: Array[String] = Game.state.landmarks_waiting()
	if not waiting.is_empty():
		staging = waiting[0]
		sheet = {"kind": "building", "id": staging}
	refresh()
	_fit_hud.call_deferred()
	SceneFlow.focus_default()
	# A landmark won on the last delve is the first thing on arrival (LM-5).
	if not staging.is_empty():
		_focus_first.call_deferred()


## Redraws everything from the sim.
func refresh() -> void:
	_board.show_state(Game.state)
	_show_right_column()


## The ledger, the shell tray and "Go down". While the stamp is up, the
## ledger and the tray preview what it would spend (Mara's #42 review).
func _show_hud() -> void:
	var spending: String = str(sheet.get("id", "")) if sheet.get("kind", "") == "confirm" else ""
	_fill(_ledger, "Ledger", _ledger_rows(spending))
	_shells = ShellTray.new()
	var shells: int = int(Game.data.row("buildings", spending)["actions"]) if not spending.is_empty() else 0
	_shells.show_state(Game.data, Game.state, shells)
	var tray: Array[Control] = [_shells]
	if Game.state.town.actions_left == 0:
		# Said once, here, not on every card (spec section 3).
		tray.append(TownStyle.label(ShellTray.describe(Game.state), TownStyle.SMALL))
	_fill(_tray_panel, "Actions", tray)
	_show_tray()
	_go_down.text = Game.state.go_down_label(Game.data)
	var kit: Kit = Kit.build(Game.data, Game.state)
	_kit_strip.show_kit(Game.data, kit, _kit_after(kit))


## The shell tray: while the arrival is staged round a landmark the panel
## stays but its shells wait faded (Mara's #46 review), then fill in one by
## one when the notice line lands. It's a fade, so reduce motion keeps it.
func _show_tray() -> void:
	# Go down waits too, so nobody leaves without seeing what they'd lose.
	_go_down.disabled = not staging.is_empty()
	if not staging.is_empty():
		_shells.lit = 0
		_shells_waited = true
		return
	_shells.lit = _shells_lit
	if _shells_waited:
		_shells_waited = false
		_shells_lit = 0
		var tween: Tween = create_tween()
		tween.tween_method(_light_shells, 0.0, float(_shells.tokens.size()), SHELLS_FILL_SECONDS)
		tween.tween_callback(_light_shells.bind(-1.0))


func _light_shells(count: float) -> void:
	_shells_lit = int(count) if count >= 0.0 else -1
	if _shells != null and is_instance_valid(_shells):
		_shells.lit = _shells_lit
		_shells.queue_redraw()


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		return button.pressed and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not event.is_echo()
	return event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed


## The notice board: newest first after a change. While picking a home it
## folds to its newest line, so the column keeps room for the pick's card.
func _show_notice(folded: bool) -> void:
	var notice: Array[Control] = []
	var homeless: String = Game.state.homeless_line(Game.data)
	var lines: PackedStringArray = notice_lines(Game.data, Game.state, Game.save_problem)
	if Game.fake_town:
		# Its own line, so a save (or a save failing) never replaces it.
		lines.append(FakeTown.NOTICE)
	if not _cheer.is_empty():
		lines.insert(0, _cheer)
	if folded and lines.size() > 1:
		lines = lines.slice(0, 1)
	for line: String in lines:
		# Notes on the board are handwritten (two-halves: Klee One).
		var note: Label = TownStyle.label(line)
		note.add_theme_font_override("font", TownStyle.sign_font())
		notice.append(note)
		if line == homeless and not folded:
			# The shortcut sits right under the line it answers (VH-4).
			notice.append(_button("Build a Cottage", choose_building.bind("cottage")))
	_fill(_notice, "", notice)


## The column's header: "Notice board | Build" (Mara's #42 review), so the
## build list opens where it's used and the board never just vanishes.
func _make_tabs() -> void:
	# Inset, so a tab's sides land on the sheet's straight top edge, and
	# drawn over the sheet, so the open tab covers the edge it joins.
	var inset: MarginContainer = MarginContainer.new()
	inset.name = "Tabs"
	inset.z_index = 1
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		inset.add_theme_constant_override("margin_" + side, TAB_INSET)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inset.add_child(row)
	for tab: String in TABS:
		var button: Button = Button.new()
		button.text = tab
		button.name = tab.replace(" ", "")
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if tab == TAB_NOTICE:
			TownStyle.style_tab(button, TownStyle.DRIFTWOOD, TownStyle.DRIFTWOOD_DARK)
		else:
			TownStyle.style_tab(button)
		button.pressed.connect(show_tab.bind(tab))
		row.add_child(button)
		_tabs[tab] = button
	_right_column.add_child(inset)
	_right_column.move_child(inset, 0)


func current_tab() -> String:
	if sheet.get("kind", "") == "kit":
		return TAB_KIT
	return TAB_BUILD if sheet.get("kind", "") in ["list", "building", "carry", "confirm"] else TAB_NOTICE


func show_tab(tab: String) -> void:
	if tab == TAB_NOTICE and current_tab() != TAB_NOTICE:
		sounds.play("paper")
	if tab == TAB_BUILD:
		if current_tab() != TAB_BUILD or sheet.get("kind", "") != "list":
			open_build_list()
	elif tab == TAB_KIT:
		if current_tab() != TAB_KIT:
			open_kit()
	else:
		close_sheet()
	_show_tabs()


func _show_tabs() -> void:
	for tab: String in _tabs:
		_tabs[tab].set_pressed_no_signal(tab == current_tab())


func _input(event: InputEvent) -> void:
	if _board.is_gathering() and _is_press(event):
		# Any press skips the gathering to its end (Mara's #46 review).
		_board.stop_gathering()
		get_viewport().set_input_as_handled()
		return
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
	elif button.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER] and button.pressed:
		# The shoulders step through the tabs, stopping at the ends.
		var step: int = -1 if button.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		show_tab(TABS[clampi(TABS.find(current_tab()) + step, 0, TABS.size() - 1)])
		get_viewport().set_input_as_handled()
	elif button.button_index == JOY_BUTTON_X and button.pressed:
		# X is context (two-halves section 3): the selection's card buttons,
		# or the build list when nothing is selected.
		var first: Control = _first_button(_card) if _card.visible and sheet.is_empty() else null
		if first != null:
			first.grab_focus()
		else:
			toggle_build_list()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _pause_menu.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_pause_menu.close()
			get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_B:
		toggle_build_list()
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_K:
		toggle_kit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		var focused: Control = get_viewport().gui_get_focus_owner()
		if not sheet.is_empty():
			back()
		elif focused != null and _card.is_ancestor_of(focused):
			_board.grab_focus()
		else:
			_pause_menu.open()
		get_viewport().set_input_as_handled()


func _on_go_down_held() -> void:
	if Game.go_down():
		Settings.set_go_down_learned()
		_fade_hint()
		_fade_music()


## The town's loop (two-halves: major pentatonic, koto and marimba plucks,
## waves underneath), faded in on arrival.
func _start_music() -> void:
	music = AudioStreamPlayer.new()
	music.name = "Music"
	# Loops by its import settings; tools/make_town_loop.py makes it seamless.
	music.stream = load(MUSIC_PATH) as AudioStreamOggVorbis
	music.bus = &"Music"
	# Always faded in: a fade isn't motion (Mara's #45 review).
	music.volume_db = -60.0
	add_child(music)
	music.play()
	create_tween().tween_property(music, "volume_db", MUSIC_DB, MUSIC_FADE_SECONDS)


## The loop dips 3 dB under the landmark chimes (Mara's #45 review).
func _duck_music() -> void:
	if music == null or not music.playing:
		return
	var tween: Tween = create_tween()
	tween.tween_property(music, "volume_db", MUSIC_DB - 3.0, 0.1)
	tween.tween_interval(1.4)
	tween.tween_property(music, "volume_db", MUSIC_DB, 0.6)


func _fade_music() -> void:
	if music != null and music.playing:
		create_tween().tween_property(music, "volume_db", -60.0, MUSIC_FADE_SECONDS / 2.0)


func _on_picked(_hit: Dictionary) -> void:
	sheet = {}
	_show_right_column()


# --- Building, moving and homes -----------------------------------------------------------

func toggle_build_list() -> void:
	if sheet.get("kind", "") == "list":
		close_sheet()
	elif sheet.get("kind", "") not in ["carry", "confirm"]:
		open_build_list()


## The Kit tab, from its tab, K or the kit strip. It never opens while a
## building is being carried or stamped.
func toggle_kit() -> void:
	if sheet.get("kind", "") == "kit":
		close_sheet()
	elif sheet.get("kind", "") not in ["carry", "confirm"] and staging.is_empty():
		open_kit()


func open_kit() -> void:
	if sheet.get("kind", "") in ["carry", "confirm"]:
		return
	_board.stop_mode()
	_board.select({})
	sounds.play("paper")
	sheet = {"kind": "kit"}
	_show_right_column()


## A row of the list (or the board's Cottage shortcut): picks up what you
## can build at once (Mara's #42 review); anything else opens its card,
## which says why not yet.
func choose_building(building_id: String) -> void:
	if BuildList.card_for(Game.data, Game.state, building_id)["can_place"]:
		start_carry(building_id)
	else:
		open_building(building_id)


func open_build_list() -> void:
	_board.stop_mode()
	_board.select({})
	sounds.play("paper")
	sheet = {"kind": "list"}
	_show_right_column()


## A building's card from the list (or the notice board's shortcut): what
## it does and costs, why not yet, and "Pick a spot".
func open_building(building_id: String) -> void:
	_board.stop_mode()
	_board.select({})
	sounds.play("paper")
	sheet = {"kind": "building", "id": building_id}
	_show_right_column()


func close_sheet() -> void:
	_board.stop_mode()
	sheet = {}
	_show_right_column()
	SceneFlow.focus_default()


## Picks up a new building, or placed building `uid` to move it.
func start_carry(building_id: String, uid: int = 0) -> void:
	_board.select({})
	if using_pad:
		_board.place_cursor(_board.view.to_screen(_board.view.target))
	_board.start_carry(building_id, uid)
	sounds.play("lift")
	sheet = {"kind": "carry", "id": building_id, "uid": uid}
	_show_right_column()
	_board.grab_focus()


## One step back: the stamp to the carry, the carry to where it came from,
## a card to the list, the list (or a home pick) to looking around.
func back() -> void:
	match str(sheet.get("kind", "")):
		"confirm":
			_board.hold_carry(false)
			sheet = {"kind": "carry", "id": sheet["id"], "uid": 0}
			_show_right_column()
			_board.grab_focus()
		"carry":
			var uid: int = sheet["uid"]
			var building: String = sheet["id"]
			_board.stop_mode()
			if uid != 0:
				sheet = {}
				_board.select({"kind": "building", "uid": uid})
				_show_right_column()
				SceneFlow.focus_default()
			else:
				open_building(building)
		"building":
			open_build_list()
		"home":
			var villager: String = sheet["villager"]
			_board.stop_mode()
			sheet = {}
			_board.select({"kind": "villager", "villager": villager})
			_show_right_column()
			SceneFlow.focus_default()
		_:
			close_sheet()


func _on_spot_chosen(cell: Vector2i) -> void:
	if sheet.get("kind", "") != "carry":
		return
	var building: String = sheet["id"]
	var uid: int = sheet["uid"]
	if uid != 0:
		var from: Dictionary = Game.state.town.entry(uid)
		var was: Vector2i = Vector2i(from["x"], from["y"])
		if not Game.move_building(uid, cell).is_empty():
			sounds.play("refuse")
			return
		last_move = {"uid": uid, "cell": was} if was != cell else {}
		sounds.play("set_down")
		_finish_change({"kind": "building", "uid": uid}, "")
	elif BuildList.cost_text(Game.data, building) == BuildList.FREE:
		_place(building, cell)
	else:
		_board.hold_carry(true)
		sheet = {"kind": "confirm", "id": building, "cell": cell}
		_show_right_column()


func _on_stamped() -> void:
	if sheet.get("kind", "") == "confirm":
		_place(sheet["id"], sheet["cell"])


## Builds through the one sim call; on a refusal the stamp's card lists why.
func _place(building: String, cell: Vector2i) -> void:
	var homeless: Array[String] = Game.state.homeless()
	var moods_before: Dictionary[String, Town.Mood] = {}
	for villager: String in Game.state.villagers():
		moods_before[villager] = Game.state.mood(Game.data, villager)
	var refusals: Array[Dictionary] = Game.build(building, cell)
	if not refusals.is_empty():
		sounds.play("refuse")
		if sheet.get("kind", "") == "confirm":
			sheet["refusals"] = refusals
			_show_right_column()
		return
	var uid: int = Game.state.town.placed.back()["uid"]
	last_move = {}
	# A stamped build sounds the stamp; a free one is set down.
	sounds.play("stamp" if sheet.get("kind", "") == "confirm" else "set_down")
	if Game.data.row("buildings", building)["kind"] == "landmark":
		_gathering = {"uid": uid, "name": BuildList.card_for(Game.data, Game.state, building)["title"]}
		_finish_change({"kind": "building", "uid": uid}, "")
		_board.gather_at(uid, moods_before)
	else:
		var line: String = ""
		for villager: String in homeless:
			if Game.state.town.homes.get(villager, 0) == uid:
				line = MOVED_IN % [Game.data.row("villagers", villager).get("role", villager),
					BuildList.card_for(Game.data, Game.state, building)["title"]]
		_finish_change({"kind": "building", "uid": uid}, line)


## Everyone has come out and the bubbles have popped: the chimes, the
## paper burst, the notice board's line, and then the shells.
func _on_gathered() -> void:
	if _gathering.is_empty():
		return
	var uid: int = _gathering["uid"]
	var line: String = GATHERED if not Game.state.villagers().is_empty() else CHEER
	_cheer = line % _gathering["name"]
	_gathering = {}
	sounds.play("chimes")
	_duck_music()
	_board.celebrate(uid)
	_show_right_column()


func undo_move() -> void:
	if last_move.is_empty():
		return
	var uid: int = last_move["uid"]
	if Game.move_building(uid, last_move["cell"]).is_empty():
		last_move = {}
		sounds.play("set_down")
		_finish_change({"kind": "building", "uid": uid}, "")


func pick_home_for(villager: String) -> void:
	_board.select({})
	_board.start_home_pick(villager)
	sounds.play("paper")
	sheet = {"kind": "home", "villager": villager}
	_show_right_column()
	_board.grab_focus()


func _on_home_chosen(uid: int) -> void:
	if sheet.get("kind", "") != "home":
		return
	var villager: String = sheet["villager"]
	if Game.swap_home(villager, uid).is_empty():
		last_move = {}
		sounds.play("set_down")
		_finish_change({"kind": "villager", "villager": villager}, "")


## After a build, move or swap: back to looking, with the thing that
## changed selected, and `cheer` on the notice board (or nothing).
func _finish_change(select: Dictionary, cheer: String) -> void:
	_board.stop_mode()
	sheet = {}
	_cheer = cheer
	refresh()
	_board.select(select)
	_show_right_column()
	SceneFlow.focus_default()


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
	if not _card.visible or not sheet.is_empty():
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
				if resident.is_empty():
					lines.append("Nobody lives here yet.")
				else:
					# The mood gets its own line, so it never wraps mid-phrase.
					lines.append("Home of the %s" % data.row("villagers", resident).get("role", resident))
					lines.append(MOOD_WORDS[state.mood(data, resident)])
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

## One row per resource. With `spending` (a building on the stamp), what
## it would cost reads "3 → 2".
func _ledger_rows(spending: String = "") -> Array[Control]:
	if _amount_width == 0.0:
		_amount_width = ceilf(TownStyle.theme().default_font.get_string_size(AMOUNT_ROOM, HORIZONTAL_ALIGNMENT_LEFT,
			-1, TownStyle.BODY).x)
	var cost: Dictionary = {}
	if not spending.is_empty():
		cost = TownMap.parse_cost(Game.data.row("buildings", spending)["cost"] as Array)
	var rows: Array[Control] = []
	for id: String in Game.data.ids("resources"):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label: Label = TownStyle.label(str(Game.data.row("resources", id).get("name", id)))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# "Driftwood 20 → 16" broke the name in two (the M3 exit frames).
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name_label)
		var have: int = Game.state.resource(id)
		var amount: Label = TownStyle.label(str(have) if not cost.has(id) else "%d → %d" % [have, have - int(cost[id])])
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		# Always room for "00 → 00", so the stamp's preview never moves the
		# sheet's edge while the player checks the numbers (Mara's #47 review).
		amount.custom_minimum_size.x = _amount_width
		row.add_child(amount)
		rows.append(row)
	return rows


## Replaces a panel's contents with a title and `children`.
func _fill(panel: PanelContainer, title: String, children: Array[Control]) -> void:
	for old: Node in panel.get_children():
		# Hidden and freed at the end of the frame, still in the tree so it
		# never dangles: a button may be replacing its own panel.
		(old as Control).visible = false
		old.name = "Old"
		old.queue_free()
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	if not title.is_empty():
		stack.add_child(TownStyle.title_label(title))
	for child: Control in children:
		stack.add_child(child)
	panel.add_child(stack)


## The right column: the notice board, then the open sheet or the
## selection's card. The build sheets take the notice board's room.
func _show_right_column() -> void:
	var kind: String = str(sheet.get("kind", ""))
	if not staging.is_empty() and _gathering.is_empty() and not (kind in ["building", "carry"] and sheet.get("id", "") == staging):
		# Put off, or placed and gathered: the visit's budget appears.
		staging = ""
	_show_hud()
	_show_tabs()
	_notice.visible = current_tab() == TAB_NOTICE
	if _notice.visible:
		_show_notice(kind == "home")
	match kind:
		"list":
			_show_list()
		"building":
			_show_building(str(sheet["id"]))
		"carry":
			_show_carry()
		"confirm":
			_show_confirm()
		"home":
			_show_home_pick()
		"kit":
			_show_kit()
		_:
			_show_card(_board.selected)
	_column_gap.visible = _notice.visible and _card.visible
	_aim_leader()


## The build list, scrolling if it's taller than the room above "Go down"
## (on the Deck, with the HUD grown). What's all built folds into one line.
func _show_list() -> void:
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	var built: PackedStringArray = []
	for entry: Dictionary in BuildList.entries(Game.data, Game.state):
		if entry["done"]:
			# A name never wraps in the middle ("Tea / stall", Mara's #44 review).
			built.append(str(entry["name"]).replace(" ", "\u00a0"))
		else:
			rows.add_child(_list_entry(entry))
	if not built.is_empty():
		rows.add_child(TownStyle.label("Built: " + ", ".join(built), TownStyle.SMALL, TownStyle.DIM))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Rows"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.add_child(rows)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill(_card, "", [scroll])
	_card.visible = true
	_fit_list.call_deferred(scroll, rows)


func _fit_list(scroll: ScrollContainer, rows: VBoxContainer) -> void:
	if not is_instance_valid(scroll):
		return
	# Measured, not guessed: the tabs and whatever sits over the card, and
	# the card's own margins, come off the room down to the kit strip.
	var actions_top: float = _scaled_rect(_actions).position.y
	var chrome: float = _card.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	var room: float = (actions_top - 16.0 - _right_column.position.y) / hud_scale - _card.position.y - chrome
	scroll.custom_minimum_size.y = minf(rows.get_combined_minimum_size().y, maxf(room, 160.0))
	scroll.scroll_vertical = 0
	_focus_first()


## One row of the build list: the name over its cost, or over why not yet.
## A row you can build is a filled button that picks it up; any other row
## is only outlined (a padlock if it's locked) and opens its card (Mara's
## #42 review: a different shape, not just grey text).
func _list_entry(entry: Dictionary) -> Button:
	var second: String = str(entry["cost"]) if entry["status"] == "" else str(entry["status"])
	if str(entry["status"]) == BuildList.WAITING:
		second = "%s · %s" % [entry["cost"], entry["status"]]
	second = _keep_amounts(second)
	var row: Button = _button("%s\n%s" % [entry["name"], second], choose_building.bind(str(entry["id"])))
	row.name = str(entry["id"])
	# Rows are read more than pressed, so they take the body weight.
	row.add_theme_font_override("font", TownStyle.theme().default_font)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: PaperBox = row.get_theme_stylebox(state) as PaperBox
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		if not entry["can_place"] and state != "focus":
			box.draw_fill = state == "hover"
			box.shadow = false
			box.fill = TownStyle.WASHI.darkened(0.04)
			box.edge_width = 1.0
	if entry["locked"]:
		var lock: Image = PixelArt.padlock()
		lock.resize(lock.get_width() * 3, lock.get_height() * 3, Image.INTERPOLATE_NEAREST)
		row.icon = ImageTexture.create_from_image(lock)
	if not entry["can_place"]:
		for color_name: String in ["font_color", "font_hover_color", "font_focus_color"]:
			row.add_theme_color_override(color_name, TownStyle.DIM)
	return row


## The kit a pending stamp would make, for the strip's preview, or null.
func _kit_after(kit: Kit) -> Kit:
	if kit == null or sheet.get("kind", "") != "confirm":
		return null
	var building: String = str(sheet["id"])
	var perk_id: String = str(Game.data.row("buildings", building).get("perk", ""))
	if perk_id.is_empty() or kit.has_perk(perk_id):
		return null
	var after: Kit = kit.copy()
	after.add_perk(Game.data, perk_id, building)
	return after


## An amount never wraps away from what it counts ("1 / pearl").
static func _keep_amounts(text: String) -> String:
	return RegEx.create_from_string("(\\d) ").sub(text, "$1\u00a0", true)


## The Kit tab: the dice, plain ones grouped and each changed one a strip
## of its faces with what changed outlined and who changed it, then the
## perks with their gains and costs.
func _show_kit() -> void:
	var kit: Kit = Kit.build(Game.data, Game.state)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.add_child(_kit_heading("Dice"))
	if kit != null:
		for die: Dictionary in KitSheet.dice_groups(Game.data, kit):
			# The chip sits over its faces, so the sheet keeps its width.
			var row: VBoxContainer = VBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var chip: PanelContainer = _chip(str(die["chip"]))
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			row.add_child(chip)
			row.add_child(KitMarks.FaceStrip.new(die["faces"], die["changed"]))
			rows.add_child(row)
	rows.add_child(_kit_heading("Perks"))
	var lines: Array[Dictionary] = KitSheet.perk_lines(Game.data, kit) if kit != null else []
	if lines.is_empty():
		rows.add_child(TownStyle.label(NO_PERKS, TownStyle.SMALL, TownStyle.DIM))
	for line: Dictionary in lines:
		var title: Label = TownStyle.label("%s · %s" % [line["source"], line["perk"]])
		title.add_theme_font_override("font", TownStyle.strong_font())
		rows.add_child(title)
		rows.add_child(_mark_line(KitSheet.gain_text(line), false))
		if not str(line["cost"]).is_empty():
			rows.add_child(_mark_line(str(line["cost"]), true))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Rows"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The fade sits over the scroll's bottom edge while there's more below.
	var holder: MarginContainer = MarginContainer.new()
	holder.add_child(scroll)
	var fade: KitMarks.Fade = KitMarks.Fade.new(scroll)
	fade.name = "Fade"
	holder.add_child(fade)
	_fill(_card, "", [holder])
	_card.visible = true
	_fit_list.call_deferred(scroll, rows)


func _kit_heading(text: String) -> Label:
	var heading: Label = TownStyle.label(text, TownStyle.SMALL, TownStyle.DIM)
	heading.add_theme_font_override("font", TownStyle.strong_font())
	return heading


## A gain (▲) or cost (▼) line: the shape first, then the words.
func _mark_line(text: String, cost: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(KitMarks.Mark.new(cost))
	var words: Label = TownStyle.label(text, TownStyle.SMALL)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	return row


## A shop's kit lines for its Build card and the stamp, or none.
func _shop_lines(building_id: String) -> Array[Control]:
	var perk: Dictionary = KitSheet.shop_perk(Game.data, building_id)
	if perk.is_empty():
		return []
	var kit_line: Label = TownStyle.label(str(perk["kit"]))
	kit_line.add_theme_font_override("font", TownStyle.strong_font())
	return [kit_line, _mark_line(str(perk["gain"]), false), _mark_line(str(perk["cost"]), true)]


## A rounded sand chip, as the villager card's wish uses.
func _chip(text: String) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	var chip_style: StyleBoxFlat = StyleBoxFlat.new()
	chip_style.bg_color = TownStyle.SAND
	chip_style.border_color = TownStyle.LOT_LINE
	chip_style.set_border_width_all(2)
	chip_style.set_corner_radius_all(18)
	chip_style.set_content_margin_all(8)
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var words: Label = TownStyle.label(text, TownStyle.SMALL)
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_child(words)
	return chip


func _show_building(building_id: String) -> void:
	var card: Dictionary = BuildList.card_for(Game.data, Game.state, building_id)
	var children: Array[Control] = []
	for line: String in card["lines"]:
		children.append(TownStyle.label(line))
	# Costs first, as on any card; what the shop adds to the kit is the new
	# part, last, above Pick a spot (Mara's #51 review).
	children.append_array(_shop_lines(building_id))
	if Game.data.row("buildings", building_id)["kind"] == "landmark":
		var place: Button = _button("Place now", start_carry.bind(building_id, 0))
		place.disabled = not card["can_place"]
		children.append(place)
		children.append(_button("Later", close_sheet))
	else:
		# The list picks up what you can build, so this card is mostly for
		# why not; "Pick a spot" shows only when it can be.
		if card["can_place"]:
			children.append(_button(PICK_A_SPOT, start_carry.bind(building_id, 0)))
		children.append(_button("Back", open_build_list))
	_fill(_card, str(card["title"]), children)
	_card.visible = true
	_focus_first.call_deferred()


func _show_carry() -> void:
	var building: String = sheet["id"]
	var moving: bool = int(sheet["uid"]) != 0
	var name: String = str(BuildList.card_for(Game.data, Game.state, building)["title"])
	var children: Array[Control] = [
		TownStyle.label(BuildList.FREE if moving else BuildList.cost_text(Game.data, building)),
		TownStyle.label("Lit spots would make someone happier.", TownStyle.SMALL, TownStyle.DIM),
		TownStyle.label(("B" if using_pad else "Right-click") + " to put it back.", TownStyle.SMALL, TownStyle.DIM),
	]
	var put_back: Button = _button("Put it back", back)
	put_back.focus_mode = Control.FOCUS_NONE
	children.append(put_back)
	_fill(_card, ("Move the %s" if moving else "Place the %s") % name, children)
	_card.visible = true


func _show_confirm() -> void:
	var building: String = sheet["id"]
	var name: String = str(BuildList.card_for(Game.data, Game.state, building)["title"])
	var children: Array[Control] = [TownStyle.label(_keep_amounts(BuildList.cost_text(Game.data, building)))]
	children.append_array(_shop_lines(building))
	for refusal: Dictionary in sheet.get("refusals", []) as Array:
		children.append(TownStyle.label(str(refusal["text"])))
	_stamp = HankoButton.new()
	_stamp.text = "Stamp"
	_stamp.name = "Stamp"
	_stamp.stamped.connect(_on_stamped)
	if sheet.has("refusals"):
		_stamp.disabled = true
	children.append(_stamp)
	children.append(_button("Not here", back))
	_fill(_card, "Build the %s here?" % name, children)
	_card.visible = true
	_focus_first.call_deferred()


func _show_home_pick() -> void:
	var villager: String = sheet["villager"]
	var role: String = str(Game.data.row("villagers", villager).get("role", villager))
	var swap_line: String = "Whoever lives there moves into the %s's home." % role if Game.state.town.homes.has(villager) \
		else "Whoever lives there waits on the dock."
	var children: Array[Control] = [
		TownStyle.label("Pick one of the framed homes.", TownStyle.BODY),
		TownStyle.label(swap_line, TownStyle.SMALL, TownStyle.DIM),
	]
	var cancel: Button = _button("Cancel", back)
	cancel.focus_mode = Control.FOCUS_NONE
	children.append(cancel)
	_fill(_card, "A new home for the %s" % role, children)
	_card.visible = true


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
	match str(hit.get("kind", "")):
		"building":
			var uid: int = hit["uid"]
			children.append(_button("Move · free", start_carry.bind(str(Game.state.town.entry(uid)["building"]), uid)))
			if last_move.get("uid", 0) == uid:
				children.append(_button("Undo move", undo_move))
		"villager":
			if _has_other_home(str(hit["villager"])):
				children.append(_button("Move to another home", pick_home_for.bind(str(hit["villager"]))))
	_fill(_card, str(card["title"]), children)


func _has_other_home(villager: String) -> bool:
	for building: Dictionary in Game.state.town.placed:
		if TownView.kind_of(Game.data, building) == "home" and Game.state.town.homes.get(villager, 0) != building["uid"]:
			return true
	return false


func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	TownStyle.style_button(button, TownStyle.SMALL)
	button.pressed.connect(action)
	return button


func _focus_first() -> void:
	var first: Control = _first_button(_card)
	if first != null:
		first.grab_focus()


## The card's first button that can take focus, or null.
static func _first_button(panel: Control) -> Control:
	for node: Node in panel.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE and not button.is_queued_for_deletion():
			return button
	return null
