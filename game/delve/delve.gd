extends Control
## The delve (M2): plays Game.run on the map screen. You pick rooms on the
## map, fights play on the fight board, treasure, rest and rescue rooms on
## the room board, and at each landing you choose Surface or Deeper with
## the stakes in front of you. The haul strip stays along the top
## throughout.
##
## Koban's vault plays on the vault board. A wash-up, surfacing or clearing
## the vault banks the haul and shows the tally here; its Continue carries
## you up to town. Game.run is null while the tally is up, so every handler
## below checks it first (Imogen's bridge review).

const BOARD_SCENE: PackedScene = preload("res://game/delve/board/fight_board.tscn")

var _strip: HaulStrip
var _map: MapView
var _landing: LandingPanel
var _board: FightBoard
var _room_board: RoomBoard
var _vault_board: VaultBoard
var _head_up: Button
var _tally: TallyPanel
## What the fights since the last stop paid, for the map and the landing.
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
		if Game.tally_open:
			_show_tally()
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
					_show_room(run)
					return
				run.finish_room()
			DelveRun.Step.LANDING:
				_show(_landing)
				_landing.show_view(RunView.new(run))
				_landing.show_notes(_notes)
				_notes.clear()
				return
			DelveRun.Step.VAULT:
				if run.vault == null:
					_show(_map)
					_map.show_notes(["Koban's vault wouldn't open. Close the game to leave."])
					return
				if not run.vault.is_over():
					_show_vault(run)
					return
				run.finish_vault()
			_:
				_show(null)
				if not Game.come_up():
					# Refused (a transition was running): let the player retry.
					_head_up.visible = true
					_head_up.grab_focus()
					return
				_head_up.visible = false
				_show_tally()
				return


## The tally over the delve screen: what came up, what the barrel took, and
## who joins. Its Continue starts the tide up.
func _show_tally() -> void:
	if _tally != null:
		return
	_tally = TallyPanel.new()
	_tally.name = "Tally"
	_tally.setup(Game.data, Game.settlement)
	_tally.continued.connect(_on_tally_continued)
	add_child(_tally)
	# The strip still shows the haul as carried; the tally says what came of it.
	_strip.visible = false


func _on_tally_continued() -> void:
	Game.leave_tally()


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


func _show_room(run: DelveRun) -> void:
	_show(null)
	_room_board = RoomBoard.new()
	_room_board.setup(run.room, Game.data, run.map.rescue_villager if run.room_type == DelveMap.RESCUE else "")
	_room_board.top_inset = HaulStrip.HEIGHT
	_room_board.finished.connect(_on_room_over)
	add_child(_room_board)
	move_child(_room_board, 1)
	PlaytestLog.log_event("room_start", {"room": run.room_type, "floor": run.floor_index, "row": run.row})


func _show_vault(run: DelveRun) -> void:
	_show(null)
	if _vault_board != null:
		return
	var prize: String = ""
	var landmark: String = str(run.map.vault_prize.get("landmark", ""))
	if Game.data.has_row("landmarks", landmark):
		prize = str(Game.data.row("landmarks", landmark)["name"])
	_vault_board = VaultBoard.new()
	_vault_board.setup(run.vault, Game.data, prize, run.kit)
	_vault_board.top_inset = HaulStrip.HEIGHT
	_vault_board.finished.connect(_on_vault_over)
	add_child(_vault_board)
	move_child(_vault_board, 1)
	PlaytestLog.log_event("vault_start", {"floor": run.floor_index, "hp": run.hp})


func _on_vault_over() -> void:
	# Once only: a second emit (a double Continue) would find the run gone
	# after come_up() (Imogen, #31).
	if _vault_board == null or Game.run == null or Game.run.vault == null:
		return
	_vault_board.queue_free()
	_vault_board = null
	var played: Vault = Game.run.vault
	PlaytestLog.log_event("vault_played", {"won": played.state == Vault.State.WON,
		"rounds_won": played.rounds_won, "rounds_lost": played.rounds_lost})
	Game.run.finish_vault()
	_advance()


func _on_room_over() -> void:
	if _room_board != null:
		_room_board.queue_free()
		_room_board = null
	if Game.run == null or Game.run.room == null:
		return
	var played: DiceRoom = Game.run.room
	Game.run.finish_room()
	PlaytestLog.log_event("room_played", {"room": played.room_id, "floor": Game.run.floor_index, "payout": played.payout,
		"hp": played.hp, "opened": played.succeeded})
	_advance()


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
	if Game.run == null:
		return
	var enemy: String = Game.run.fight.enemy_name if Game.run.fight != null else "Fight"
	Game.run.finish_room()
	var found: PackedStringArray = []
	for id: String in Game.run.last_loot:
		found.append("%d %s" % [Game.run.last_loot[id], str(Game.data.row("resources", id)["name"]).to_lower()])
	if not found.is_empty() and not Game.run.is_over():
		_notes.append("%s: found %s" % [enemy, ", ".join(found)])
	_advance()


func _on_surface_pressed() -> void:
	# Also retries coming up if an earlier try was refused after surfacing.
	if Game.run == null:
		return
	if Game.run.surface():
		PlaytestLog.log_event("landing", {"choice": "surface", "floor": Game.run.floor_index, "hp": Game.run.hp})
		_advance()
	elif Game.run.is_over():
		_head_up.visible = false
		_advance()


func _on_deeper_pressed() -> void:
	if Game.run == null:
		return
	if Game.run.go_deeper():
		PlaytestLog.log_event("landing", {"choice": "deeper", "floor": Game.run.floor_index, "hp": Game.run.hp})
		_advance()


func _under_strip(screen: Control) -> void:
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_top = HaulStrip.HEIGHT
