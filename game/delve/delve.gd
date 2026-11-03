extends Control
## Greybox delve (M2 stand-in until the map screen): plays Game.run room by
## room, always taking the leftmost room it can reach. Fights show on the
## board; treasure, rest and rescue rooms are placeholders that pass for
## now. At a landing, Surface and Deeper choose; a wash-up or surfacing
## goes back to town, where the haul is banked.

const BOARD_SCENE: PackedScene = preload("res://game/delve/board/fight_board.tscn")

var _board: FightBoard
var _deeper: Button

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
				run.finish_room()
			DelveRun.Step.LANDING:
				_surface.visible = true
				_deeper.visible = true
				_set_status(run, "Landing: surface with your haul, or go deeper?")
				_surface.grab_focus()
				return
			DelveRun.Step.VAULT:
				_set_status(run, "Koban's vault opens in a later build. Close the game to leave.")
				return
			_:
				if not Game.come_up():
					# Refused (a transition was running): let the player retry.
					_surface.visible = true
					_surface.grab_focus()
				return


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
	_status.text = "Delve %d · HP %d/%d · %s" % [Game.state.delve_count, run.hp, run.max_hp, text]
