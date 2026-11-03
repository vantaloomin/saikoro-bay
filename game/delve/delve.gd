extends Control
## Greybox delve (M1): one dice fight at a time on the board, against an
## enemy drawn from this delve's ENEMIES stream. "Fight again" draws the next
## enemy from the same streams, so a delve seed always deals the same
## fights. The map, rooms and carried HP arrive in M2.

const BOARD_SCENE: PackedScene = preload("res://game/delve/board/fight_board.tscn")

var _rng: RngStreams
var _board: FightBoard
var _fights: int = 0

@onready var _surface: Button = %Surface
@onready var _status: Label = %Status


func _ready() -> void:
	_surface.pressed.connect(_on_surface_pressed)
	_rng = RngStreams.new(Game.state.current_delve_seed())
	_next_fight()


func _next_fight() -> void:
	if _board != null:
		_board.queue_free()
	var enemies: Array = Array(Game.data.ids("enemies"))
	var enemy_id: String = _rng.pick(RngStreams.Stream.ENEMIES, enemies) as String
	var fight: Fight = Fight.create(Game.data, "fresh", enemy_id, _rng)
	_fights += 1
	_status.text = "Delve %d · fight %d · seed %d" % [Game.state.delve_count, _fights, Game.state.current_delve_seed()]
	_board = BOARD_SCENE.instantiate() as FightBoard
	_board.setup(fight, Game.data)
	_board.again_requested.connect(_next_fight)
	_board.leave_requested.connect(_on_surface_pressed)
	add_child(_board)
	move_child(_board, 0)
	PlaytestLog.log_event("fight_start", {"enemy": enemy_id, "fight": _fights})


func _on_surface_pressed() -> void:
	Game.come_up()
