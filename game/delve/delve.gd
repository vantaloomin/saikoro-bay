extends Control
## Greybox delve (M2 stand-in until the map screen): plays Game.run room by
## room, always taking the leftmost room it can reach. Fights show on the
## board. Treasure, rest and rescue rooms have no board yet, so the room
## bot plays them and the status line says what they gave. At a landing,
## Surface and Deeper choose. Koban's vault has no board yet either, so the
## vault bot plays it. A wash-up, surfacing or clearing the vault goes back
## to town, where the haul is banked.

const BOARD_SCENE: PackedScene = preload("res://game/delve/board/fight_board.tscn")

var _board: FightBoard
var _deeper: Button
## What the rooms played since the last stop gave, for the status line.
var _notes: PackedStringArray = []

@onready var _surface: Button = %Surface
@onready var _status: Label = %Status


func _ready() -> void:
	_surface.text = "Surface"
	_surface.pressed.connect(_on_surface_pressed)
	_deeper = _surface.duplicate() as Button
	_deeper.text = "Deeper"
	_deeper.position.y += 64
	_deeper.pressed.connect(_on_deeper_pressed)
	add_child(_deeper)
	_advance()


## Moves the run on until it needs the player: a fight, a landing, the
## vault, or the end.
func _advance() -> void:
	var run: DelveRun = Game.run
	_surface.visible = false
	_deeper.visible = false
	if run == null:
		return
	for guard: int in 32:
		match run.step:
			DelveRun.Step.CHOOSE_ROOM:
				run.choose(run.reachable()[0])
			DelveRun.Step.IN_ROOM:
				if run.fight != null:
					_show_fight(run)
					return
				if run.room != null:
					_play_room(run)
				run.finish_room()
			DelveRun.Step.LANDING:
				_surface.visible = true
				_deeper.visible = true
				_set_status(run, "Landing: surface with your haul, or go deeper?")
				_surface.grab_focus()
				return
			DelveRun.Step.VAULT:
				if run.vault == null:
					_set_status(run, "Koban's vault wouldn't open. Close the game to leave.")
					return
				# Stand-in until the vault board: the vault bot plays it.
				VaultBot.new().play_vault(run.vault)
				PlaytestLog.log_event("vault_played", {"won": run.vault.state == Vault.State.WON,
					"rounds_won": run.vault.rounds_won, "rounds_lost": run.vault.rounds_lost})
				run.finish_vault()
			_:
				if not Game.come_up():
					# Refused (a transition was running): let the player retry.
					_surface.visible = true
					_surface.grab_focus()
				return


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
		gave.append("cage open" if played.succeeded else "cage still shut")
	var room_name: String = Game.data.row("rooms", played.room_id)["name"]
	_notes.append("%s: %s" % [room_name, ", ".join(gave) if not gave.is_empty() else "nothing"])
	PlaytestLog.log_event("room_played", {"room": played.room_id, "floor": run.floor_index, "row": run.row,
		"payout": played.payout, "hp": played.hp, "opened": played.succeeded})


func _show_fight(run: DelveRun) -> void:
	if _board != null:
		_board.queue_free()
	_set_status(run, "Floor %d · %s" % [run.floor_index + 1, run.room_type])
	_board = BOARD_SCENE.instantiate() as FightBoard
	_board.setup(run.fight, Game.data)
	_board.again_text = "Continue"
	_board.leave_shown = false
	# Marked seen as the fight is dealt, which is when the banner shows: the
	# board goes into the tree a few lines down. If showing it is ever
	# deferred, mark it seen from the board when the banner appears instead.
	_board.twist_banner = Game.state.meet_twist(run.fight.twist)
	_board.again_requested.connect(_on_fight_over)
	add_child(_board)
	move_child(_board, 0)
	PlaytestLog.log_event("fight_start", {"enemy": run.fight.enemy_id, "floor": run.floor_index, "row": run.row})


func _on_fight_over() -> void:
	if _board != null:
		_board.queue_free()
		_board = null
	Game.run.finish_room()
	_advance()


func _on_surface_pressed() -> void:
	# Also retries coming up if an earlier try was refused after surfacing.
	if Game.run.surface() or Game.run.is_over():
		Game.come_up()


func _on_deeper_pressed() -> void:
	if Game.run.go_deeper():
		_advance()


func _set_status(run: DelveRun, text: String) -> void:
	var shown: String = text
	if not _notes.is_empty():
		shown = "%s · %s" % [" · ".join(_notes), text]
		_notes.clear()
	_status.text = "Delve %d · HP %d/%d · %s" % [Game.state.delve_count, run.hp, run.max_hp, shown]
