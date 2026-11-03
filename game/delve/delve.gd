extends Control
## Greybox delve. The dice board, map and rooms arrive in M1 and M2; for now
## it shows which delve this is and offers the way back up.

@onready var _status: Label = %Status
@onready var _surface: Button = %Surface
@onready var _quit: Button = %Quit


func _ready() -> void:
	_surface.pressed.connect(_on_surface_pressed)
	_quit.pressed.connect(get_tree().quit)
	_status.text = "Delve %d\nSeed %d" % [Game.state.delve_count, Game.state.current_delve_seed()]
	SceneFlow.focus_default()


func _on_surface_pressed() -> void:
	Game.come_up()
