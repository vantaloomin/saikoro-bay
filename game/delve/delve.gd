extends Control
## The delve (M2): plays Game.run on the map screen. You pick rooms on the
## map, fights play on the dice board, and at each landing you choose
## Surface or Deeper with the stakes in front of you. The haul strip stays
## along the top throughout.
##
## Stand-ins until their boards exist (Mara's UX, next): the room bot plays
## treasure, rest and rescue rooms, and the map says what they gave; the
## vault bot plays Koban's vault. A wash-up, surfacing or clearing the
## vault goes back to town, where the haul is banked.

const BOARD_SCENE: PackedScene = preload("res://game/delve/board/fight_board.tscn")

var _strip: HaulStrip
var _map: MapView
var _landing: LandingPanel
var _board: FightBoard
var _head_up: Button
## What the rooms played since the last stop gave, for the map.
var _notes: PackedStringArray = []


func _ready() -> void:
	theme = BoardStyle.theme()
	var background: ColorRect = ColorRect.new()
	background.color = BoardStyle.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_map = MapView.new()
	_map.setup(Game.data)
	_map.room_chosen.connect(_on_room_chosen)
	_under_strip(_map)
	_landing = LandingPanel.new()
	_landing.setup(Game.data)
	_landing.surface_chosen.connect(_on_surface_pressed)
	_landing.deeper_chosen.connect(_on_deeper_pressed)
	_landing.visible = false
	_under_strip(_landing)
	_strip = HaulStrip.new()
	_strip.setup(Game.data)
	add_child(_strip)
	_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_strip.offset_bottom = HaulStrip.HEIGHT
	_head_up = Button.new()
	_head_up.text = "Head back to town"
	_head_up.visible = false
	_head_up.position = Vector2(760, 500)
	_head_up.custom_minimum_size = Vector2(400, 80)
	_head_up.pressed.connect(_on_surface_pressed)
	add_child(_head_up)
	_advance()


## Moves the run on until it needs the player: a room to pick, a fight, a
## landing, or the end.
func _advance() -> void:
	var run: DelveRun = Game.run
	if run == null:
		return
	for guard: int in 32:
		match run.step:
			DelveRun.Step.CHOOSE_ROOM:
				_show(_map)
				_map.show_view(RunView.new(run))
				_map.show_notes(_notes)
				_notes.clear()
				return
			DelveRun.Step.IN_ROOM:
				if run.fight != null:
					_show_fight(run)
					return
				if run.room != null:
					_play_room(run)
				run.finish_room()
			DelveRun.Step.LANDING:
				_show(_landing)
				_landing.show_view(RunView.new(run))
				return
			DelveRun.Step.VAULT:
				if run.vault == null:
					_show(_map)
					_map.show_notes(["Koban's vault wouldn't open. Close the game to leave."])
					return
				# Stand-in until the vault board: the vault bot plays it.
				VaultBot.new().play_vault(run.vault)
				PlaytestLog.log_event("vault_played", {"won": run.vault.state == Vault.State.WON,
					"rounds_won": run.vault.rounds_won, "rounds_lost": run.vault.rounds_lost})
				run.finish_vault()
			_:
				_show(null)
				if not Game.come_up():
					# Refused (a transition was running): let the player retry.
					_head_up.visible = true
					_head_up.grab_focus()
				return


## Shows one screen (the map, the landing, or nothing while a board or the
## tide is up) and refreshes the strip.
func _show(screen: Control) -> void:
	_map.visible = screen == _map
	_landing.visible = screen == _landing
	if Game.run != null:
		_strip.show_view(RunView.new(Game.run))


func _on_room_chosen(col: int) -> void:
	var run: DelveRun = Game.run
	if run == null or not run.choose(col):
		return
	PlaytestLog.log_event("room_chosen", {"floor": run.floor_index, "row": run.row, "col": col, "type": run.room_type,
		"hp": run.hp})
	_advance()


## Stand-in until the room boards (Mara's UX): the room bot plays it.
func _play_room(run: DelveRun) -> void:
	var played: DiceRoom = run.room
	RoomBot.new().play_room(played)
	var gave: PackedStringArray = []
	for id: String in played.payout:
		gave.append("+%d %s" % [played.payout[id], Game.data.row("resources", id)["name"]])
	var before: int = run.hp
	if played.hp > before:
		gave.append("+%d HP" % (played.hp - before))
	elif played.hp < before:
		gave.append("-%d HP" % (before - played.hp))
	if played.room_id == DelveMap.RESCUE:
		gave.append("the cage opened" if played.succeeded else "still caged: you'll find them again")
	var room_name: String = Game.data.row("rooms", played.room_id)["name"]
	_notes.append("%s: %s" % [room_name, ", ".join(gave) if not gave.is_empty() else "nothing"])
	PlaytestLog.log_event("room_played", {"room": played.room_id, "floor": run.floor_index, "row": run.row,
		"payout": played.payout, "hp": played.hp, "opened": played.succeeded})


func _show_fight(run: DelveRun) -> void:
	if _board != null:
		_board.queue_free()
	_show(null)
	_board = BOARD_SCENE.instantiate() as FightBoard
	_board.setup(run.fight, Game.data)
	_board.again_text = "Continue"
	_board.leave_shown = false
	_board.top_inset = HaulStrip.HEIGHT
	# Marked seen as the fight is dealt, which is when the banner shows: the
	# board goes into the tree a few lines down. If showing it is ever
	# deferred, mark it seen from the board when the banner appears instead.
	_board.twist_banner = Game.state.meet_twist(run.fight.twist)
	_board.again_requested.connect(_on_fight_over)
	add_child(_board)
	# Under the strip, over the background.
	move_child(_board, 1)
	PlaytestLog.log_event("fight_start", {"enemy": run.fight.enemy_id, "floor": run.floor_index, "row": run.row})


func _on_fight_over() -> void:
	if _board != null:
		_board.queue_free()
		_board = null
	Game.run.finish_room()
	_advance()


func _on_surface_pressed() -> void:
	# Also retries coming up if an earlier try was refused after surfacing.
	if Game.run.surface():
		PlaytestLog.log_event("landing", {"choice": "surface", "floor": Game.run.floor_index, "hp": Game.run.hp})
		_advance()
	elif Game.run.is_over():
		_head_up.visible = false
		_advance()


func _on_deeper_pressed() -> void:
	if Game.run.go_deeper():
		PlaytestLog.log_event("landing", {"choice": "deeper", "floor": Game.run.floor_index, "hp": Game.run.hp})
		_advance()


func _under_strip(screen: Control) -> void:
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_top = HaulStrip.HEIGHT
