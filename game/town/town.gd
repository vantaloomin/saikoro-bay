extends Control
## Greybox town. Free-form and real time in the full game; for now it shows
## where the town's actions will live and the "Go down" button (TC-7).
##
## "Go down" is always visible and never glows or animates: a button that
## nudges the player would spoil the "second delve unprompted" playtest signal.

@onready var _status: Label = %Status
@onready var _go_down: Button = %GoDown
@onready var _quit: Button = %Quit


func _ready() -> void:
	_go_down.pressed.connect(_on_go_down_pressed)
	_quit.pressed.connect(get_tree().quit)
	_status.text = _status_text()
	SceneFlow.focus_default()


func _status_text() -> String:
	var lines: PackedStringArray = ["Delves so far: %d" % Game.state.delve_count]
	if Game.saving_locked:
		lines.append("Saving is off: your save is from a newer version of the game.")
	return "\n".join(lines)


func _on_go_down_pressed() -> void:
	Game.go_down()
