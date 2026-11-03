extends GutTest
## The town screen (M3 PRs 5a and 5b) on the real Game autoload: it opens
## on the diorama with the HUD filled in, says how the last delve ended,
## shows a card for what you pick, and labels "Go down" with what's kept and
## lost. Building goes list, card, carry, stamp; free things never ask.

const TOWN_SCENE: PackedScene = preload("res://game/town/town.tscn")
const TEST_SAVE: String = "user://test_town_screen.save"

var _original_state: GameState
var _original_problem: String
var _original_store: SaveStore


func before_each() -> void:
	_original_state = Game.state
	_original_problem = Game.save_problem
	_original_store = Game.store
	Game.store = SaveStore.new(TEST_SAVE)
	Game.state = GameState.new(77)
	Game.state.arrive(Game.data)
	Game.save_problem = ""


func after_each() -> void:
	Game.store.erase()
	Game.store = _original_store
	Game.state = _original_state
	Game.save_problem = _original_problem
	Game.settlement = {}
	Settings.reduce_motion = false


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
	assert_eq(Array(home["lines"]), ["A home for one villager.", "Home of the Pearl diver", TownScreen.MOOD_WORDS[Town.Mood.HAPPY]],
		"the mood on its own line, so it never wraps mid-phrase")
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


func test_the_land_is_framed_clear_of_the_hud() -> void:
	var town: TownScreen = _open()
	await wait_physics_frames(2)
	town._fit_hud()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var outline: PackedVector2Array = board.view.land_outline()
	for rect: Rect2 in town.hud_rects():
		var corners: PackedVector2Array = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]
		assert_eq(Geometry2D.intersect_polygons(outline, corners).size(), 0, "nothing of the land under %s" % rect)


# --- Building, moving and homes (PR 5b) -----------------------------------------------------

func _cell_point(board: TownBoard, cell: Vector2i) -> Vector2:
	return board.view.to_screen(Vector3(cell.x + 0.5, 0.0, cell.y + 0.5))


func _rich(town_actions: int = 4) -> void:
	Game.state.town.actions_left = town_actions
	Game.state.add_resource("driftwood", 20)
	Game.state.add_resource("pearls", 5)


func test_a_build_goes_list_card_carry_stamp() -> void:
	_rich()
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.open_build_list()
	assert_eq(town.sheet, {"kind": "list"})
	assert_not_null(town.find_child("cottage", true, false), "the list has a Cottage row")
	town.open_building("cottage")
	town.start_carry("cottage")
	assert_eq(board.mode, TownBoard.Mode.CARRY)
	board._pick_at(_cell_point(board, Vector2i(4, 2)))
	assert_eq(town.sheet["kind"], "carry", "a path is no spot")
	assert_eq(board.carry_problem, "On a path")
	board._pick_at(_cell_point(board, Vector2i(1, 1)))
	assert_eq(town.sheet["kind"], "confirm", "a costed build asks for the stamp")
	assert_eq(Game.state.town.placed.size(), 0, "nothing is spent before the stamp")
	assert_true(board.carry_held, "the ghost waits on its spot")
	var stamp: HankoButton = town.find_child("Stamp", true, false) as HankoButton
	assert_eq(town.find_child("Ledger", true, false).find_children("*", "Label", true, false).map(
		func(label: Node) -> String: return (label as Label).text).has("20 → 16"), true, "the ledger previews the spend")
	stamp.pressed.emit()
	assert_true(stamp.disabled, "the stamp locks itself on the first press (Imogen's #42 audit)")
	stamp.pressed.emit()
	assert_eq(Game.state.town.placed.size(), 0, "the build waits for the seal to touch the paper")
	await wait_seconds(HankoButton.PUNCH_SECONDS)
	assert_eq(Game.state.town.placed.size(), 1, "one stamp, one build")
	assert_eq(town.sounds.played.count("stamp"), 1, "the stamp sounds once, as the seal lands")
	assert_eq(Game.state.town.actions_left, 3, "one shell spent, once")
	assert_eq(Game.state.resource("driftwood"), 16)
	assert_eq(town.sheet, {})
	assert_eq(board.mode, TownBoard.Mode.LOOK)
	assert_eq(board.selected, {"kind": "building", "uid": Game.state.town.placed[0]["uid"]}, "the new home is picked")


func test_the_ledger_preview_keeps_each_name_on_one_line_and_its_width() -> void:
	_rich()
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var ledger: Control = town.find_child("Ledger", true, false) as Control
	await wait_process_frames(2)
	var width: float = ledger.size.x
	town.start_carry("cottage")
	board._pick_at(_cell_point(board, Vector2i(1, 1)))
	assert_eq(town.sheet["kind"], "confirm")
	await wait_process_frames(2)
	for label: Node in town.find_child("Ledger", true, false).find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			assert_eq((label as Label).get_line_count(), 1, "\"%s\" stays on one line" % (label as Label).text)
	assert_eq(ledger.size.x, width, "the sheet's edge holds still for the preview (Mara's #47 review)")


func test_backing_out_of_a_build_changes_nothing() -> void:
	_rich()
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.open_building("cottage")
	town.start_carry("cottage")
	board._pick_at(_cell_point(board, Vector2i(1, 1)))
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	town._unhandled_input(esc)
	assert_eq(town.sheet["kind"], "carry", "Not here goes back to carrying")
	assert_false(board.carry_held)
	board.cancelled.emit()
	assert_eq(town.sheet, {"kind": "building", "id": "cottage"}, "putting it back returns to its card")
	town._unhandled_input(esc)
	assert_eq(town.sheet, {"kind": "list"})
	town._unhandled_input(esc)
	assert_eq(town.sheet, {})
	assert_false((town.get_node("%PauseMenu") as PauseMenu).visible, "Esc closed sheets before the menu")
	assert_eq(Game.state.town.placed.size(), 0)
	assert_eq(Game.state.town.actions_left, 4)


func test_a_card_cant_be_carried_without_what_it_needs() -> void:
	Game.state.town.actions_left = 4
	var town: TownScreen = _open()
	town.open_building("cottage")
	var pick: Button = null
	for node: Node in town.find_children("*", "Button", true, false):
		if (node as Button).text == TownScreen.PICK_A_SPOT:
			pick = node as Button
	assert_null(pick, "no driftwood, no carrying: the card only says why")


func test_a_won_landmark_waits_on_arrival_and_places_free() -> void:
	Game.state.town.actions_left = 4
	Game.state._landmarks.append("hot_spring")
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	assert_eq(town.sheet, {"kind": "building", "id": "hot_spring"}, "the first thing on arrival (LM-5)")
	var tray: Control = town.get_node("%Tray")
	assert_true(tray.visible, "the tray stays, so the HUD doesn't jump")
	assert_eq(town._shells.lit, 0, "but the visit's budget waits for the landmark, faded")
	assert_true((town.get_node("%GoDown") as Button).disabled, "and nobody goes down without seeing it")
	town.start_carry("hot_spring")
	assert_eq(town._shells.lit, 0, "still waiting while it's carried")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	assert_eq(Game.state.town.count("hot_spring"), 1, "placed with no stamp: it's free")
	assert_eq(Game.state.town.actions_left, 4, "and costs no action")
	assert_eq(town.sheet, {})
	assert_true(_notice_says(town, TownScreen.CHEER % "Hot Spring"), "with nobody in town yet, it's just open")
	await wait_seconds(TownScreen.SHELLS_FILL_SECONDS + 0.1)
	assert_eq(town._shells.lit, -1, "then the budget fills in")
	assert_false((town.get_node("%GoDown") as Button).disabled)
	assert_true(town.sounds.played.has("chimes"))


func _notice_says(town: TownScreen, line: String) -> bool:
	for label: Node in (town.get_node("%Notice") as Control).find_children("*", "Label", true, false):
		if (label as Label).text == line:
			return true
	return false


func test_the_town_walks_over_to_see_a_landmark_and_home_again() -> void:
	Game.state._landmarks.append("hot_spring")
	Game.state._villagers.append("pearl_diver")
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var home: Vector3 = board.view.villager_spots(Game.data, Game.state)["pearl_diver"]
	var tray: Control = town.get_node("%Tray")
	town.start_carry("hot_spring")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	assert_true(board.is_gathering(), "the town comes out to see it")
	assert_eq(town._shells.lit, 0, "the shells wait until they have")
	board.advance_gathering(TownBoard.WALK_SECONDS / 2.0)
	var halfway: Vector3 = board.view.villager_spots(Game.data, Game.state)["pearl_diver"]
	assert_ne(halfway, home, "on the way")
	board.advance_gathering(TownBoard.WALK_SECONDS / 2.0)
	var there: Vector3 = board.view.villager_spots(Game.data, Game.state)["pearl_diver"]
	var rect: Rect2i = Town.rect_of(Game.data, Game.state.town.entry(Game.state.town.placed.back()["uid"]))
	assert_true(Rect2(rect).grow(1.6).has_point(Vector2(there.x, there.z)), "standing by the Hot Spring")
	assert_eq(board.bubble_reveal, 0.0, "the bubble hasn't popped yet")
	assert_false(_notice_says(town, TownScreen.GATHERED % "Hot Spring"), "the notice board waits for the pop")
	board.advance_gathering(TownBoard.POP_SECONDS)
	assert_eq(board.bubble_reveal, 1.0)
	assert_true(_notice_says(town, TownScreen.GATHERED % "Hot Spring"), "then says the town came out")
	assert_ne(town._shells.lit, 0, "and the budget starts filling in")
	board.advance_gathering(TownBoard.GATHER_HOLD_SECONDS)
	board.advance_gathering(TownBoard.WALK_SECONDS)
	assert_false(board.is_gathering())
	assert_eq(board.view.villager_spots(Game.data, Game.state)["pearl_diver"], home, "and home again")


func test_with_reduce_motion_nobody_walks_and_bubbles_crossfade() -> void:
	Settings.reduce_motion = true
	Game.state._landmarks.append("hot_spring")
	Game.state._villagers.append("pearl_diver")
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var home: Vector3 = board.view.villager_spots(Game.data, Game.state)["pearl_diver"]
	town.start_carry("hot_spring")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	assert_eq(board.view.villager_spots(Game.data, Game.state)["pearl_diver"], home, "no walk")
	assert_true(board.is_gathering(), "but the bubbles still change in turn")
	board.advance_gathering(TownBoard.POP_SECONDS)
	assert_true(_notice_says(town, TownScreen.GATHERED % "Hot Spring"))
	assert_false(board.is_gathering(), "no stay and no walk home")
	Settings.reduce_motion = false


func test_putting_a_landmark_off_shows_the_budget() -> void:
	Game.state._landmarks.append("hot_spring")
	var town: TownScreen = _open()
	town.close_sheet()
	assert_eq(town.staging, "")
	assert_true((town.get_node("%GoDown") as Button).disabled, "Later: Go down waits while the shells fill")
	await wait_seconds(TownScreen.SHELLS_FILL_SECONDS + 0.2)
	assert_false((town.get_node("%GoDown") as Button).disabled, "then the shells and Go down are back")


func test_carrying_mid_gathering_sends_everyone_home() -> void:
	_rich()
	Game.state._landmarks.append("hot_spring")
	Game.state._villagers.append("pearl_diver")
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var home: Vector3 = board.view.villager_spots(Game.data, Game.state)["pearl_diver"]
	town.start_carry("hot_spring")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	board.advance_gathering(TownBoard.WALK_SECONDS / 2.0)
	town.start_carry("lantern_post")
	assert_false(board.is_gathering())
	assert_eq(board.view.villager_spots(Game.data, Game.state)["pearl_diver"], home)
	assert_true(_notice_says(town, TownScreen.GATHERED % "Hot Spring") or town._cheer == TownScreen.GATHERED % "Hot Spring",
		"cut short, it still says the town came out")


func test_moving_is_free_and_the_last_move_undoes() -> void:
	Game.state.town.actions_left = 2
	var uid: int = Game.state.town.place("net_shed", Vector2i(0, 0))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.start_carry("net_shed", uid)
	assert_eq(board.carry_cell, Vector2i(0, 0), "it lifts from where it stands")
	board._pick_at(_cell_point(board, Vector2i(5, 5)))
	assert_eq(Game.state.town.entry(uid)["x"], 5, "moved with no stamp")
	assert_eq(Game.state.town.actions_left, 2, "for free")
	assert_eq(town.last_move, {"uid": uid, "cell": Vector2i(0, 0)})
	town.undo_move()
	assert_eq(Vector2i(Game.state.town.entry(uid)["x"], Game.state.town.entry(uid)["y"]), Vector2i(0, 0))
	assert_eq(town.last_move, {}, "one undo")


func test_a_villager_moves_to_another_home_from_their_card() -> void:
	Game.state._villagers.append("pearl_diver")
	Game.state._villagers.append("shipwright")
	var sea: int = Game.state.town.place("cottage", Vector2i(0, 7))
	var inland: int = Game.state.town.place("cottage", Vector2i(1, 1))
	Game.state.town.homes["pearl_diver"] = inland
	Game.state.town.homes["shipwright"] = sea
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.pick_home_for("pearl_diver")
	assert_eq(board.home_choices(), [sea] as Array[int], "every home but her own")
	board.home_chosen.emit(sea)
	assert_eq(Game.state.town.homes["pearl_diver"], sea)
	assert_eq(Game.state.town.homes["shipwright"], inland, "whoever lived there swaps back")
	assert_eq(board.selected, {"kind": "villager", "villager": "pearl_diver"})


func test_the_homeless_line_offers_a_cottage() -> void:
	Game.state._villagers.append("pearl_diver")
	var town: TownScreen = _open()
	var shortcut: Button = null
	for node: Node in (town.get_node("%Notice") as Control).find_children("*", "Button", true, false):
		if (node as Button).text == "Build a Cottage":
			shortcut = node as Button
	assert_not_null(shortcut)
	shortcut.pressed.emit()
	assert_eq(town.sheet, {"kind": "building", "id": "cottage"})


func test_carrying_lights_the_spots_that_make_someone_happy() -> void:
	_rich()
	Game.state._villagers.append("onsen_keeper")
	Game.state.town.homes["onsen_keeper"] = Game.state.town.place("cottage", Vector2i(1, 1))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.start_carry("tea_stall")
	var lit: Array[Vector2i] = board.wish_cells.duplicate()
	lit.sort()
	assert_eq(lit, [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 2), Vector2i(2, 1)] as Array[Vector2i])


func test_name_tags_never_cover_bubbles_or_each_other() -> void:
	for villager: String in ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]:
		Game.state._villagers.append(villager)
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	Game.state.town.homes["shipwright"] = Game.state.town.place("cottage", Vector2i(2, 5))
	Game.state.town.place("net_shed", Vector2i(2, 6))
	Game.state.town.homes["onsen_keeper"] = Game.state.town.place("cottage", Vector2i(9, 2))
	Game.state.town.place("tea_stall", Vector2i(1, 1))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	board.show_all_names = true
	var spots: Dictionary[String, Vector3] = board.view.villager_spots(Game.data, Game.state)
	var taken: Array[Rect2] = []
	for rect: Rect2 in board.bubble_rects(spots).values():
		taken.append(rect)
	var tags: Array[Dictionary] = board.map_tags(spots)
	assert_eq(tags.size(), 4 + 5, "every villager and every building")
	for tag: Dictionary in tags:
		var rect: Rect2 = tag["rect"]
		assert_true(Rect2(Vector2.ZERO, board.size).encloses(rect), "%s stays on screen" % tag["text"])
		for other: Rect2 in taken:
			assert_false(rect.intersects(other), "%s covers nothing" % tag["text"])
		taken.append(rect)


func test_the_build_tab_opens_the_list_and_affordable_rows_pick_up_at_once() -> void:
	_rich()
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	assert_eq(town.current_tab(), TownScreen.TAB_NOTICE)
	town.show_tab(TownScreen.TAB_BUILD)
	assert_eq(town.sheet, {"kind": "list"})
	assert_false((town.get_node("%Notice") as Control).visible, "the board is one tab away, not gone")
	(town.find_child("cottage", true, false) as Button).pressed.emit()
	assert_eq(town.sheet["kind"], "carry", "a row you can build picks it up at once")
	assert_eq(board.carry_building, "cottage")
	town.show_tab(TownScreen.TAB_NOTICE)
	assert_eq(town.sheet, {})
	assert_eq(board.mode, TownBoard.Mode.LOOK, "the notice tab puts it back")
	town.show_tab(TownScreen.TAB_BUILD)
	(town.find_child("bait_shop", true, false) as Button).pressed.emit()
	assert_eq(town.sheet, {"kind": "building", "id": "bait_shop"}, "a locked row opens its card")


func test_a_new_home_says_who_moved_in() -> void:
	_rich()
	Game.state._villagers.append("shrine_keeper")
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.start_carry("cottage")
	board._pick_at(_cell_point(board, Vector2i(1, 1)))
	(town.find_child("Stamp", true, false) as HankoButton).pressed.emit()
	await wait_seconds(HankoButton.PUNCH_SECONDS)
	var said: bool = false
	for label: Node in (town.get_node("%Notice") as Control).find_children("*", "Label", true, false):
		said = said or (label as Label).text == TownScreen.MOVED_IN % ["Kitsune shrine keeper", "Cottage"]
	assert_true(said)


func test_the_town_wears_its_own_type_and_furniture() -> void:
	var town: TownScreen = _open()
	assert_eq(town.theme.default_font.resource_path, TownStyle.UI_FONT_PATH, "M PLUS Rounded for the UI")
	var kinds: Dictionary = {"%Ledger": PaperBox.Kind.LEDGER, "%Notice": PaperBox.Kind.BOARD,
		"%Tray": PaperBox.Kind.TRAY, "%Card": PaperBox.Kind.PAPER}
	for path: String in kinds:
		var box: PaperBox = (town.get_node(path) as PanelContainer).get_theme_stylebox("panel") as PaperBox
		assert_not_null(box, "%s is drawn by hand" % path)
		assert_eq(box.kind, kinds[path], "%s is its own piece of furniture" % path)
	var notes: Array[Node] = (town.get_node("%Notice") as Node).find_children("*", "Label", true, false)
	assert_eq((notes[0] as Label).get_theme_font("font").resource_path, TownStyle.SIGN_FONT_PATH,
		"notes on the board are handwritten")
	var pause: Control = town.get_node("%PauseMenu")
	assert_eq(pause.get_theme_default_font(), ThemeDB.fallback_font, "the pause menu keeps its neutral skin")


func test_the_open_tab_sits_flush_on_its_sheet() -> void:
	var town: TownScreen = _open()
	await wait_process_frames(2)
	var tabs: Control = town.get_node("RightColumn/Tabs")
	var notice: Control = town.get_node("%Notice")
	assert_eq(tabs.get_rect().end.y, notice.position.y, "the notice tab joins the board")
	town.show_tab(TownScreen.TAB_BUILD)
	await wait_process_frames(2)
	assert_eq(tabs.get_rect().end.y, (town.get_node("%Card") as Control).position.y, "the build tab joins the list")
	var open: PaperBox = town._tabs[TownScreen.TAB_BUILD].get_theme_stylebox("pressed") as PaperBox
	var shut: PaperBox = town._tabs[TownScreen.TAB_BUILD].get_theme_stylebox("normal") as PaperBox
	assert_eq(open.fill, TownStyle.WASHI, "the open tab is the sheet's paper")
	assert_eq(shut.edge_width, 0.0, "a closed tab is flat, with no border")
	assert_eq(town._tabs[TownScreen.TAB_NOTICE].get_theme_stylebox("pressed").get("fill"), TownStyle.DRIFTWOOD,
		"the notice tab is the board's driftwood")


func test_the_town_sounds_like_wood_and_paper() -> void:
	_rich()
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	assert_true(town.music.playing, "the town's loop plays")
	assert_true((town.music.stream as AudioStreamOggVorbis).loop, "and loops")
	town.open_build_list()
	town.start_carry("cottage")
	board._pick_at(_cell_point(board, Vector2i(4, 2)))
	assert_eq(town.sounds.played, ["paper", "lift", "refuse"] as Array[String], "a path is a soft no")
	for cue: String in TownSounds.CUES:
		var length: float = TownSounds.stream(cue).get_length()
		assert_between(length, 0.03, 1.7, "%s is short" % cue)


func test_the_hold_tone_follows_the_fill() -> void:
	var town: TownScreen = _open()
	var hold: HoldButton = town.get_node("%GoDown") as HoldButton
	hold.set_process(false)
	hold.start_hold()
	hold.advance(HoldButton.HOLD_SECONDS * 0.4)
	var rising: float = hold.tone_level()
	assert_gt(rising, 0.0, "holding sounds")
	hold.advance(HoldButton.HOLD_SECONDS * 0.2)
	assert_gt(hold.tone_level(), rising, "and rises with the fill")
	hold.stop_hold()
	hold.advance(HoldButton.DRAIN_SECONDS * 0.5)
	assert_lt(hold.tone_level(), rising, "letting go early falls away with the fill")
	hold.advance(HoldButton.DRAIN_SECONDS)
	assert_eq(hold.tone_level(), 0.0, "and stops, never plays out")


func test_music_and_sounds_each_have_their_own_volume() -> void:
	var town: TownScreen = _open()
	assert_eq(town.music.bus, &"Music")
	assert_eq(town.sounds.get_child(0).get("bus"), &"SFX")
	town.open_build_list()
	assert_eq(town.sounds._players[0].bus, &"UI", "the list's rustle is a menu sound")
	for bus: String in Settings.BUSES:
		assert_gt(AudioServer.get_bus_index(bus), 0, "the %s bus exists" % bus)
		var row: Node = town.get_node("%PauseMenu").find_child(bus + "Volume", true, false)
		assert_not_null(row, "the pause menu has a %s slider" % bus)
		var slider: HSlider = row.find_child("Slider", true, false) as HSlider
		assert_eq(slider.step, 0.05, "a pad steps it 5%")
		assert_eq((row.find_child("Readout", true, false) as Label).text, PauseMenu.percent(slider.value), "and it reads out")


func test_names_keep_off_the_swap_preview() -> void:
	Game.state._villagers.append("pearl_diver")
	Game.state._villagers.append("shipwright")
	var sea: int = Game.state.town.place("cottage", Vector2i(0, 7))
	var inland: int = Game.state.town.place("cottage", Vector2i(1, 6))
	Game.state.town.homes["pearl_diver"] = inland
	Game.state.town.homes["shipwright"] = sea
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.pick_home_for("pearl_diver")
	board.hovered = {"kind": "building", "uid": sea}
	var swap: Dictionary = board.swap_tag()
	assert_false(swap.is_empty())
	var loses: bool = Game.state.swap_moods(Game.data, "pearl_diver", sea).values().any(
		func(mood: Town.Mood) -> bool: return mood != Town.Mood.HAPPY)
	assert_eq(swap["mood"], Town.Mood.UNHAPPY if loses else Town.Mood.HAPPY, "the icon says gain or loss")
	assert_string_contains(swap["text"], "Pearl diver happy · Nudge 1 → 2 a turn", "a swap says what the perk gains")
	for tag: Dictionary in board.map_tags(board.view.villager_spots(Game.data, Game.state)):
		assert_false((tag["rect"] as Rect2).intersects(swap["rect"]), "%s keeps off the swap preview" % tag["text"])


func test_any_press_skips_the_gathering() -> void:
	Game.state._landmarks.append("hot_spring")
	Game.state._villagers.append("pearl_diver")
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var home: Vector3 = board.view.villager_spots(Game.data, Game.state)["pearl_diver"]
	town.start_carry("hot_spring")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	board.advance_gathering(TownBoard.WALK_SECONDS / 3.0)
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.pressed = true
	town._input(press)
	assert_false(board.is_gathering(), "skipped")
	assert_eq(board.view.villager_spots(Game.data, Game.state)["pearl_diver"], home, "everyone's home")
	assert_true(_notice_says(town, TownScreen.GATHERED % "Hot Spring"), "and the line is posted")


func test_the_villager_whose_mood_changes_stands_in_plain_view() -> void:
	# The Onsen keeper wants the Hot Spring nearby, and their cottage sits in front of it.
	Game.state._landmarks.append("hot_spring")
	for villager: String in ["pearl_diver", "shipwright", "onsen_keeper"]:
		Game.state._villagers.append(villager)
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	Game.state.town.homes["shipwright"] = Game.state.town.place("cottage", Vector2i(2, 5))
	Game.state.town.homes["onsen_keeper"] = Game.state.town.place("cottage", Vector2i(9, 2))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var before: Town.Mood = Game.state.mood(Game.data, "onsen_keeper")
	town.start_carry("hot_spring")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	assert_ne(Game.state.mood(Game.data, "onsen_keeper"), before, "the keeper's mood changes")
	board.advance_gathering(TownBoard.WALK_SECONDS)
	var spot: Vector3 = board.view.villager_spots(Game.data, Game.state)["onsen_keeper"]
	var boxes: Array[AABB] = []
	for placed: Dictionary in Game.state.town.placed:
		boxes.append(TownView.block_box(Game.data, placed))
	assert_false(board.view._hidden_by(spot, boxes, board.view.camera_transform().origin), "no building hides the keeper or the bubble")


func test_each_bubble_sits_just_above_its_own_head() -> void:
	for villager: String in ["pearl_diver", "shipwright", "onsen_keeper", "shrine_keeper"]:
		Game.state._villagers.append(villager)
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	var spots: Dictionary[String, Vector3] = board.view.villager_spots(Game.data, Game.state)
	var bubbles: Dictionary[String, Rect2] = board.bubble_rects(spots)
	var gaps: Array[float] = []
	for villager: String in spots:
		var head: float = board.sprite_rect(spots[villager], TownView.villager_height(villager)).position.y
		gaps.append(head - bubbles[villager].end.y)
	assert_gt(gaps.min(), 0.0, "no bubble sits on a head")
	assert_lt(gaps.max() - gaps.min(), 3.0, "Chiyo's bubble is as close to her head as Genzo's is to his: %s" % [gaps])


func test_nobody_walks_through_a_building_to_see_a_landmark() -> void:
	Game.state._landmarks.append("hot_spring")
	for villager: String in ["pearl_diver", "shipwright"]:
		Game.state._villagers.append(villager)
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 7))
	Game.state.town.homes["shipwright"] = Game.state.town.place("cottage", Vector2i(2, 5))
	Game.state.town.place("boat_shed", Vector2i(5, 5))
	Game.state.town.place("net_shed", Vector2i(9, 2))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.start_carry("hot_spring")
	board._pick_at(_cell_point(board, Vector2i(10, 0)))
	assert_true(board.is_gathering())
	var boxes: Array[AABB] = []
	for placed: Dictionary in Game.state.town.placed:
		boxes.append(TownView.block_box(Game.data, placed))
	var steps: int = 0
	while board.is_gathering() and steps < 2000:
		board.advance_gathering(TownBoard.WALK_SECONDS / 60.0)
		steps += 1
		for villager: String in board.view.walking:
			var at: Vector3 = board.view.walking[villager]
			for box: AABB in boxes:
				assert_false(box.has_point(Vector3(at.x, 0.05, at.z)), "%s at %s is inside a building" % [villager, at])
	assert_false(board.is_gathering(), "there and home again")


# --- The kit (M4 PR 2, specs/bridge.md section 5) -------------------------------

func _texts_in(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(label: Node) -> String: return (label as Label).text)


func test_the_kit_tab_shows_the_dice_and_every_perk_with_its_gain_and_cost() -> void:
	Game.state._villagers.append("shipwright")
	Game.state.town.place("bait_shop", Vector2i(5, 0))
	var town: TownScreen = _open()
	town.show_tab(TownScreen.TAB_KIT)
	assert_eq(town.sheet, {"kind": "kit"})
	assert_eq(town.current_tab(), TownScreen.TAB_KIT)
	var card: Control = town.get_node("%Card") as Control
	assert_true(card.visible)
	var strips: Array = card.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool: return node is KitMarks.FaceStrip)
	assert_eq(strips.size(), 1, "four plain dice are one Standard row")
	var texts: Array = _texts_in(card)
	for line: String in ["Dice", "Standard × 4", "Perks", "Shipwright · Brace",
			"Start every turn with 2 block · if happy: +1 block, so 3 a turn", "Bait shop · Chum",
			"+1 of each resource from treasure rooms", "Every enemy hits 1 harder"]:
		assert_true(texts.has(line), "the Kit tab says \"%s\"" % line)
	town.show_tab(TownScreen.TAB_NOTICE)
	assert_eq(town.sheet, {})


func test_an_empty_kit_says_where_perks_come_from() -> void:
	var town: TownScreen = _open()
	town.show_tab(TownScreen.TAB_KIT)
	assert_true(_texts_in(town.get_node("%Card")).has(TownScreen.NO_PERKS))


func test_k_and_the_kit_strip_open_the_kit_and_the_shoulders_step_through_tabs() -> void:
	var town: TownScreen = _open()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	town._unhandled_input(key)
	assert_eq(town.current_tab(), TownScreen.TAB_KIT, "K opens the kit")
	town._unhandled_input(key)
	assert_eq(town.current_tab(), TownScreen.TAB_NOTICE, "and K again closes it")
	var strip: Button = town.find_child("KitStrip", true, false) as Button
	assert_not_null(strip, "the kit strip sits above Go down")
	assert_eq(strip.tooltip_text, "Your kit: 4 dice · 0 perks")
	assert_eq((strip as KitMarks.Strip).perks_text, "0 perks")
	strip.pressed.emit()
	assert_eq(town.current_tab(), TownScreen.TAB_KIT, "the strip opens the kit")
	var shoulder: InputEventJoypadButton = InputEventJoypadButton.new()
	shoulder.pressed = true
	shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER
	town._input(shoulder)
	assert_eq(town.current_tab(), TownScreen.TAB_BUILD)
	town._input(shoulder)
	assert_eq(town.current_tab(), TownScreen.TAB_NOTICE)
	town._input(shoulder)
	assert_eq(town.current_tab(), TownScreen.TAB_NOTICE, "the left shoulder stops at the first tab")
	shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER
	town._input(shoulder)
	town._input(shoulder)
	town._input(shoulder)
	assert_eq(town.current_tab(), TownScreen.TAB_KIT, "and the right one at the last")


func test_the_kit_never_opens_over_a_carried_building() -> void:
	_rich()
	var town: TownScreen = _open()
	town.start_carry("cottage")
	town.toggle_kit()
	assert_eq(town.sheet["kind"], "carry")


func test_a_shop_card_and_its_stamp_say_what_it_adds_to_the_kit() -> void:
	_rich()
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.open_building("cottage")
	assert_false(_texts_in(town.get_node("%Card")).any(func(text: String) -> bool: return text.begins_with("Kit:")),
		"a home adds nothing to the kit")
	town.open_building("net_shed")
	var texts: Array = _texts_in(town.get_node("%Card"))
	assert_true(texts.has("Kit: + Weighted die (2 3 3 4 4 5)"))
	assert_true(texts.has("Your first die never rolls a 1"))
	assert_true(texts.has("It never rolls a 6 either"), "the cost is on the card, not hidden")
	town.start_carry("net_shed")
	board._pick_at(_cell_point(board, Vector2i(5, 0)))
	assert_eq(town.sheet["kind"], "confirm")
	texts = _texts_in(town.get_node("%Card"))
	assert_true(texts.has("Kit: + Weighted die (2 3 3 4 4 5)"), "the stamp says it too")
	assert_true(texts.has("It never rolls a 6 either"))
	assert_true(texts.has("1\u00a0shell + 6\u00a0driftwood"), "an amount never wraps from its noun")
	var strip: KitMarks.Strip = town.find_child("KitStrip", true, false) as KitMarks.Strip
	assert_eq(strip.perks_text, "0 → 1 perks", "the strip previews the stamp, as the ledger does")
	assert_true(strip.dice[0]["new"], "the weighted die is the new one")


func test_a_move_tag_says_what_a_perk_gains_or_loses() -> void:
	Game.state._villagers.append("shipwright")
	Game.state.town.homes["shipwright"] = Game.state.town.place("cottage", Vector2i(2, 5))
	var shed: int = Game.state.town.place("net_shed", Vector2i(5, 5))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town.start_carry("net_shed", shed)
	board.carry_cell = Vector2i(2, 6)
	assert_eq(board.move_tag()["text"], "Free · Shipwright happy · Brace 2 → 3")
	assert_true(board.move_tag()["icon"])
	var carried: Rect2 = board.carry_tag()["rect"]
	for tag: Dictionary in board.map_tags(board.view.villager_spots(Game.data, Game.state)):
		assert_false((tag["rect"] as Rect2).intersects(carried), "%s keeps off the move tag" % tag["text"])
	board.carry_cell = Vector2i(6, 5)
	assert_eq(board.move_tag(), {"text": "Free", "mood": Town.Mood.HAPPY, "icon": false})


## Coming back with `rescued` and `landmark` from a delve that brought 6
## driftwood (specs/bridge.md section 6).
func _came_back(rescued: Array[String] = [], landmark: String = "") -> void:
	var before: Dictionary = {}
	for id: String in Game.data.ids("resources"):
		before[id] = Game.state.resource(id)
	Game.state.add_resource("driftwood", 6)
	var after: Dictionary = before.duplicate()
	after["driftwood"] = int(before["driftwood"]) + 6
	for villager: String in rescued:
		Game.state._villagers.append(villager)
		Game.state.town.homes[villager] = Game.state.town.place("cottage", Vector2i(0, 7))
	if not landmark.is_empty():
		Game.state._landmarks.append(landmark)
	Game.settlement = {"delve": 1, "outcome": Haul.SURFACED, "kept": {}, "lost": {}, "rescued": rescued,
		"landmark": landmark, "before": before, "after": after}


func _ledger_text(town: TownScreen, id: String) -> String:
	return town._ledger_amounts[id].text


func _gain_labels(town: TownScreen) -> Array:
	return (town.get_node("%Ledger") as Control).find_children("Gain", "Label", true, false).filter(
		func(node: Node) -> bool: return (node as Label).is_visible_in_tree()).map(
		func(node: Node) -> String: return (node as Label).text)


func test_coming_back_counts_up_walks_in_then_fills_the_shells() -> void:
	_came_back(["pearl_diver"] as Array[String])
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	assert_true(Game.settlement.is_empty(), "played once")
	assert_eq(town.arrival, "count")
	assert_eq(_ledger_text(town, "driftwood"), "0", "from what the town had")
	assert_eq(_gain_labels(town), ["+6"], "with what came up beside it")
	assert_true((town.get_node("%GoDown") as Button).disabled)
	assert_eq(town._shells.lit, 0, "the shells wait")
	town._show_count(0.5)
	assert_eq(_ledger_text(town, "driftwood"), "3")
	town._end_count()
	assert_eq(_ledger_text(town, "driftwood"), "6")
	assert_eq(town.arrival, "walk")
	assert_true(board.is_walking_in())
	assert_eq(board.view.villager_spots(Game.data, Game.state)["pearl_diver"], board.view.arrival_spot(0),
		"the rescued step off the end of the dock")
	assert_true((town.get_node("%GoDown") as Button).disabled)
	board.advance_gathering(TownBoard.ARRIVE_SECONDS)
	assert_eq(town.arrival, "")
	assert_eq(board.view.villager_spots(Game.data, Game.state)["pearl_diver"],
		board.view.home_spot(Game.data, Game.state.town, "pearl_diver"), "and walk home")
	assert_true((town.get_node("%GoDown") as Button).disabled, "Go down waits for the shells to fill")
	await wait_seconds(TownScreen.SHELLS_FILL_SECONDS + 0.2)
	assert_false((town.get_node("%GoDown") as Button).disabled)
	assert_eq(town._shells.lit, -1)
	assert_eq(_gain_labels(town), ["+6"], "+N stays a moment after")
	town._clear_gains()
	assert_eq(_gain_labels(town), [])


func test_one_press_skips_coming_back() -> void:
	_came_back(["pearl_diver"] as Array[String])
	var town: TownScreen = _open()
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	town._input(press)
	assert_eq(town.arrival, "", "the count, the walk-in and the fill all skip")
	assert_eq(_ledger_text(town, "driftwood"), "6")
	assert_false((town.get_node("%Board") as TownBoard).is_walking_in())
	assert_eq(town._shells.lit, -1)
	assert_false((town.get_node("%GoDown") as Button).disabled)


func test_a_press_mid_walk_skips_the_rest() -> void:
	_came_back(["pearl_diver"] as Array[String])
	var town: TownScreen = _open()
	town._end_count()
	assert_true((town.get_node("%Board") as TownBoard).is_walking_in())
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	town._input(press)
	assert_eq(town.arrival, "")
	assert_false((town.get_node("%Board") as TownBoard).is_walking_in())
	assert_false((town.get_node("%GoDown") as Button).disabled, "the shells lit at once")


func test_a_won_landmark_is_staged_after_the_walk_in() -> void:
	_came_back(["pearl_diver"] as Array[String], "hot_spring")
	var town: TownScreen = _open()
	assert_eq(town.staging, "", "not while the ledger counts")
	town._end_count()
	assert_eq(town.staging, "", "nor while the rescued walk in")
	(town.get_node("%Board") as TownBoard).advance_gathering(TownBoard.ARRIVE_SECONDS)
	assert_eq(town.staging, "hot_spring", "then the landmark comes first")
	assert_eq(town.sheet, {"kind": "building", "id": "hot_spring"})


func test_with_reduce_motion_coming_back_is_instant() -> void:
	Settings.reduce_motion = true
	_came_back(["pearl_diver"] as Array[String])
	var town: TownScreen = _open()
	await wait_process_frames(2)
	assert_eq(town.arrival, "")
	assert_eq(_ledger_text(town, "driftwood"), "6")
	assert_eq(_gain_labels(town), ["+6"], "the gain still shows")
	assert_false((town.get_node("%Board") as TownBoard).is_walking_in())
	Settings.reduce_motion = false


func test_a_town_with_nothing_to_play_starts_ready() -> void:
	var town: TownScreen = _open()
	assert_eq(town.arrival, "")
	assert_eq(town.gains, {} as Dictionary[String, int])


## Mara's #62 review: each arrival says they're home with their wish, and
## the kit strip shows the perk they bring.
func test_a_rescued_villager_reaching_home_says_so_and_pulses_the_kit() -> void:
	_came_back(["pearl_diver"] as Array[String])
	var town: TownScreen = _open()
	var line: String = TownScreen.arrival_line(Game.data, Game.state, "pearl_diver")
	assert_eq(line, "The Pearl diver is home and happy", "the cottage at (0, 7) is by the sea")
	town._end_count()
	assert_false(_notice_says(town, line), "not before they get there")
	(town.get_node("%Board") as TownBoard).advance_gathering(TownBoard.ARRIVE_SECONDS)
	assert_true(_notice_says(town, line))
	assert_eq(town._kit_strip.pulse, "+1 perk")
	town._end_pulse()
	assert_eq(town._kit_strip.pulse, "")


func test_an_unhappy_arrival_names_their_wish() -> void:
	Game.state._villagers.append("pearl_diver")
	Game.state.town.homes["pearl_diver"] = Game.state.town.place("cottage", Vector2i(0, 6))
	assert_eq(TownScreen.arrival_line(Game.data, Game.state, "pearl_diver"),
		"The Pearl diver is home and wishes to be next to the sea")


func test_arrivals_walk_at_a_pace_one_after_another() -> void:
	_came_back(["pearl_diver", "shipwright"] as Array[String])
	Game.state.town.homes["shipwright"] = Game.state.town.place("cottage", Vector2i(4, 4))
	var town: TownScreen = _open()
	var board: TownBoard = town.get_node("%Board") as TownBoard
	town._end_count()
	assert_eq(board._arrive_delay, {"pearl_diver": 0.0, "shipwright": TownBoard.ARRIVE_STAGGER} as Dictionary[String, float])
	for villager: String in board._arrive_time:
		assert_lte(board._arrive_time[villager], TownBoard.ARRIVE_SECONDS, "never longer than the cap")
	assert_lte(board._walk_seconds, TownBoard.ARRIVE_SECONDS + TownBoard.ARRIVE_STAGGER)
