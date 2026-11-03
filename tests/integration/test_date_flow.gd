extends GutTest
## A date from the town (M5): the villager card shows affection and a Date
## button, the button opens the spot pick, the stamp opens the date screen,
## and the date's end spends the action, keeps the affection and saves.
## Leaving midway spends and keeps nothing.

const TOWN_SCENE: PackedScene = preload("res://game/town/town.tscn")
const TEST_SAVE: String = "user://test_date_flow.save"

var _original_state: GameState
var _original_store: SaveStore
var _original_motion: bool
var _original_age: bool
var _original_level: ContentLevel.Level


func before_each() -> void:
	_original_state = Game.state
	_original_store = Game.store
	_original_motion = Settings.reduce_motion
	_original_age = Settings.age_confirmed
	_original_level = Settings.content_level
	Settings.reduce_motion = true
	Game.store = SaveStore.new(TEST_SAVE)
	var state: GameState = GameState.new(21)
	state.town.needs_budget = false
	state.town.actions_left = 10
	state.add_resource("driftwood", 20)
	state._villagers.append_array(["pearl_diver", "onsen_keeper"] as Array[String])
	state._landmarks.append("cafe")
	state.build(Game.data, "cottage", Vector2i(0, 7))
	state.build(Game.data, "cottage", Vector2i(1, 7))
	state.build(Game.data, "cafe", Vector2i(0, 0))
	state.town.actions_left = 2
	state.town.kept = 0
	Game.state = state


func after_each() -> void:
	Game.store.erase()
	Game.store = _original_store
	Game.state = _original_state
	Settings.reduce_motion = _original_motion
	Settings.age_confirmed = _original_age
	Settings.content_level = _original_level


func _open_card(villager: String) -> TownScreen:
	var town: TownScreen = TOWN_SCENE.instantiate() as TownScreen
	add_child_autofree(town)
	(town.get_node("%Board") as TownBoard).select({"kind": "villager", "villager": villager})
	town._show_right_column()
	return town


func _card_button(town: TownScreen, name: String) -> Button:
	for node: Node in town.get_node("%Card").find_children(name, "Button", true, false):
		if not node.is_queued_for_deletion() and (node as Control).visible:
			return node as Button
	return null


## Plays the date on screen, always taking response `pick`, to its card.
func _play(screen: DateScreen, pick: int) -> void:
	var guard: int = 0
	while screen.stage in ["playing", "invite"] and guard < 200:
		guard += 1
		if screen.runner.busy:
			await wait_process_frames(1)
		elif screen.runner.line != null and not screen.runner.line.responses.is_empty():
			await screen.choose(mini(pick, screen.runner.line.responses.size() - 1))
		else:
			await screen.go_on()


func _start_date(town: TownScreen, villager: String, spot: String) -> DateScreen:
	town.open_date(villager)
	town.choose_date_spot(spot)
	town._on_date_stamped()
	await wait_process_frames(2)
	return town.date_screen


func test_the_card_shows_affection_and_a_date_button() -> void:
	var town: TownScreen = _open_card("pearl_diver")
	assert_eq(Array(TownScreen.affection_lines(Game.data, 0)), ["Getting to know you", "Next: Fond at 2"])
	assert_eq(Array(TownScreen.affection_lines(Game.data, 2)),
		["Fond", "Next: Close at 3 · unlocks a private moment"])
	assert_eq(Array(TownScreen.affection_lines(Game.data, 3)), ["Close"])
	var date: Button = _card_button(town, "Date")
	assert_not_null(date)
	assert_eq(date.text, "Date · 1 action")
	assert_false(date.disabled)
	assert_eq(town.get_node("%Card").find_children("Affection", "AffectionMeter", true, false).size(), 1)


func test_no_actions_or_no_spot_says_why() -> void:
	Game.state.town.actions_left = 0
	assert_eq(TownScreen.date_button(Game.data, Game.state, "pearl_diver"),
		{"text": "Date · 1 action", "why": "No actions left", "can": false})
	Game.state.town.actions_left = 2
	Game.state.town.placed = Game.state.town.placed.filter(func(b: Dictionary) -> bool: return b["building"] != "cafe")
	assert_false(TownScreen.date_button(Game.data, Game.state, "pearl_diver")["can"])


func test_the_spot_pick_lists_every_spot_and_why_not() -> void:
	var town: TownScreen = _open_card("pearl_diver")
	town.open_date("pearl_diver")
	assert_false(_card_button(town, "Spot_cafe").disabled)
	assert_true(_card_button(town, "Spot_hot_spring").disabled, "the Hot Spring isn't won yet")
	town.back()
	assert_eq(town.sheet, {}, "back to the villager's card")


func test_a_whole_date_spends_the_action_and_saves_the_affection() -> void:
	var town: TownScreen = _open_card("pearl_diver")
	var screen: DateScreen = await _start_date(town, "pearl_diver", "cafe")
	assert_not_null(screen, "the stamp opens the date")
	assert_eq(Game.state.town.actions_left, 2, "nothing spent while it plays")
	await _play(screen, 0)
	assert_eq(screen.stage, "result")
	assert_eq(Game.state.town.actions_left, 1)
	assert_eq(Game.state.affection("pearl_diver"), screen.session.kept)
	assert_gt(screen.session.kept, 1, "the first answers land")
	var saved: SaveStore.ReadResult = Game.store.read()
	assert_true(saved.is_ok(), "saved at the end")
	var loaded: GameState = GameState.from_dict(saved.payload[GameState.PAYLOAD_KEY])
	assert_eq(loaded.affection("pearl_diver"), Game.state.affection("pearl_diver"))
	assert_eq(Array(DateScreen.result_lines(Game.data, Game.state, screen.session, [], screen.scene_reached))[0], "Date over")
	(screen.get_node("Box").find_child("BackToTown", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_null(town.date_screen)
	assert_eq(town.sheet, {})


func test_reaching_close_plays_the_invitation() -> void:
	Game.state._affection["onsen_keeper"] = 2
	var town: TownScreen = _open_card("onsen_keeper")
	var screen: DateScreen = await _start_date(town, "onsen_keeper", "cafe")
	await _play(screen, 0)
	assert_true(screen.scene_reached)
	assert_true(Affection.scene_unlocked(Game.data, Game.state.affection("onsen_keeper")))
	assert_has(DateScreen.result_lines(Game.data, Game.state, screen.session, [], true), "A private moment is unlocked")


func test_leaving_midway_spends_and_keeps_nothing() -> void:
	var town: TownScreen = _open_card("pearl_diver")
	var before: Dictionary = Game.state.to_dict()
	var screen: DateScreen = await _start_date(town, "pearl_diver", "cafe")
	await screen.go_on()
	screen.leave()
	await wait_process_frames(2)
	assert_eq(Game.state.to_dict(), before)
	assert_null(town.date_screen)
	assert_false(Game.store.read().is_ok(), "nothing was saved")


func test_the_date_reads_the_content_level_from_settings() -> void:
	Settings.age_confirmed = false
	Settings.content_level = ContentLevel.Level.FULL
	assert_eq(Game.begin_date("pearl_diver", "cafe").content_level, ContentLevel.Level.SFW, "no age check, no adult lines")
	Settings.age_confirmed = true
	assert_eq(Game.begin_date("pearl_diver", "cafe").content_level, Settings.effective_content_level())


func test_a_double_stamp_opens_one_date() -> void:
	var town: TownScreen = _open_card("pearl_diver")
	town.open_date("pearl_diver")
	town.choose_date_spot("cafe")
	town._on_date_stamped()
	town._on_date_stamped()
	await wait_process_frames(2)
	assert_eq(town.find_children("*", "DateScreen", false, false).size(), 1)
