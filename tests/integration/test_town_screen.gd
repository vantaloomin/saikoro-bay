extends GutTest
## The town screen (M3 PR 5a) on the real Game autoload: it opens on the
## diorama with the HUD filled in, says how the last delve ended, shows a
## card for what you pick, and labels "Go down" with what's kept and lost.

const TOWN_SCENE: PackedScene = preload("res://game/town/town.tscn")

var _original_state: GameState
var _original_problem: String


func before_each() -> void:
	_original_state = Game.state
	_original_problem = Game.save_problem
	Game.state = GameState.new(77)
	Game.state.arrive(Game.data)
	Game.save_problem = ""


func after_each() -> void:
	Game.state = _original_state
	Game.save_problem = _original_problem


func _open() -> TownScreen:
	var town: TownScreen = TOWN_SCENE.instantiate() as TownScreen
	add_child_autofree(town)
	return town


func test_the_screen_opens_with_the_hud_filled_in() -> void:
	Game.state.town.actions_left = 5
	Game.state.town.kept = 1
	var town: TownScreen = _open()
	assert_eq((town.get_node("%GoDown") as Button).text, "Go down · keep 1, 4 are lost")
	var tray: ShellTray = (town.get_node("%Tray") as PanelContainer).find_children("*", "ShellTray", true, false)[0] as ShellTray
	assert_eq(tray.tokens.size(), 5)
	assert_eq(tray.tooltip_text, "5 actions left, 1 kept from your last visit")
	assert_false((town.get_node("%Card") as Control).visible, "no card until you pick something")


func test_the_notice_board_says_how_the_last_delve_went() -> void:
	assert_eq(Array(TownScreen.notice_lines(Game.data, Game.state, "")), [TownScreen.FIRST_VISIT])
	Game.state.delve_count = 1
	Game.state._villagers.append("pearl_diver")
	Game.state.last_delve = {"delve": 1, "outcome": Haul.SURFACED, "kept": {"resources": {"pearls": 2}}}
	assert_eq(Array(TownScreen.notice_lines(Game.data, Game.state, "Saving is off.")), [
		TownScreen.ARRIVAL[Haul.SURFACED], "Brought back: Pearls 2",
		"The Pearl diver has nowhere to live", "Saving is off.",
	])
	Game.state.last_delve = {"delve": 1, "outcome": Haul.ABANDONED, "kept": {}}
	assert_string_contains(TownScreen.notice_lines(Game.data, Game.state, "")[0], "Your actions are back",
		"quitting mid-delve says what it cost (Vanta's rule)")


func test_cards_for_buildings_and_villagers() -> void:
	var state: GameState = Game.state
	state._villagers.append("pearl_diver")
	state._villagers.append("shrine_keeper")
	var cottage: int = state.town.place("cottage", Vector2i(0, 7))
	state.town.homes["pearl_diver"] = cottage
	var empty: int = state.town.place("cottage", Vector2i(2, 2))
	var home: Dictionary = TownScreen.card_for(Game.data, state, {"kind": "building", "uid": cottage})
	assert_eq(home["title"], "Cottage")
	assert_eq(Array(home["lines"]), ["A home for one villager.", "Home of the Pearl diver · happy"])
	assert_eq(Array(TownScreen.card_for(Game.data, state, {"kind": "building", "uid": empty})["lines"])[1],
		"Nobody lives here yet.")
	var diver: Dictionary = TownScreen.card_for(Game.data, state, {"kind": "villager", "villager": "pearl_diver"})
	assert_eq(diver["title"], "Pearl diver")
	assert_eq(Array(diver["lines"]), [TownScreen.MOOD_WORDS[Town.Mood.HAPPY]])
	assert_eq(diver["chip"], "Wish: Next to the sea")
	var keeper: Dictionary = TownScreen.card_for(Game.data, state, {"kind": "villager", "villager": "shrine_keeper"})
	assert_eq(Array(keeper["lines"]), [TownScreen.MOOD_WORDS[Town.Mood.HOMELESS]])
	assert_eq(TownScreen.card_for(Game.data, state, {"kind": "cell", "cell": Vector2i(1, 1)}), {})


func test_picking_on_the_board_opens_and_closes_the_card() -> void:
	Game.state._villagers.append("pearl_diver")
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var card: Control = town.get_node("%Card") as Control
	var dock: Vector2 = board.view.to_screen(board.view.dock_spot(0) + Vector3(0, 0.5, 0))
	board._pick_at(dock)
	assert_eq(board.selected, {"kind": "villager", "villager": "pearl_diver"})
	assert_true(card.visible)
	board._pick_at(board.view.to_screen(Vector3(6.5, 0.0, 2.5)))
	assert_eq(board.selected, {}, "picking the ground clears it")
	assert_false(card.visible)


func test_holding_y_holds_go_down() -> void:
	var town: TownScreen = _open()
	var go_down: HoldButton = town.get_node("%GoDown") as HoldButton
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_Y
	press.pressed = true
	town._input(press)
	go_down.advance(HoldButton.HOLD_SECONDS * 0.5)
	assert_almost_eq(go_down.progress(), 0.5, 0.01)
	press.pressed = false
	town._input(press)
	assert_false(go_down.is_holding(), "letting go cancels")
	go_down.advance(HoldButton.DRAIN_SECONDS)
	assert_eq(go_down.progress(), 0.0, "and the fill drains")


func test_esc_and_start_open_the_pause_menu_with_quit_in_it() -> void:
	var town: TownScreen = _open()
	var menu: PauseMenu = town.get_node("%PauseMenu") as PauseMenu
	assert_false(menu.visible)
	assert_not_null(menu.find_child("Quit", true, false), "Quit lives in the menu")
	assert_null(town.find_child("Quit", false, false), "not beside Go down")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	town._unhandled_input(esc)
	assert_true(menu.visible)
	var hold: InputEventJoypadButton = InputEventJoypadButton.new()
	hold.button_index = JOY_BUTTON_Y
	hold.pressed = true
	town._input(hold)
	assert_false((town.get_node("%GoDown") as HoldButton).is_holding(), "no holding Go down behind the menu")
	town._unhandled_input(esc)
	assert_false(menu.visible)
	var start: InputEventJoypadButton = InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	town._input(start)
	assert_true(menu.visible)


func test_the_hold_hint_follows_the_input() -> void:
	var town: TownScreen = _open()
	assert_eq(town.hint_text(), TownScreen.HOLD_HINT_MOUSE)
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	town._input(pad)
	assert_eq(town.hint_text(), TownScreen.HOLD_HINT_PAD)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	town._input(click)
	assert_eq(town.hint_text(), TownScreen.HOLD_HINT_MOUSE)


func test_the_town_is_framed_between_the_hud_columns() -> void:
	var town: TownScreen = _open()
	await wait_physics_frames(2)
	town._fit_hud()
	var safe: Rect2 = town.safe_area()
	var ledger: Rect2 = (town.get_node("%Ledger") as Control).get_global_rect()
	var notice: Rect2 = (town.get_node("%Notice") as Control).get_global_rect()
	assert_gt(safe.position.x, ledger.end.x - 1.0, "right of the ledger")
	assert_lt(safe.end.x, notice.position.x + 1.0, "left of the notice board and card")
	var board: TownBoard = town.get_node("%Board") as TownBoard
	assert_true(safe.grow(1.0).encloses(board.view.town_bounds()))
