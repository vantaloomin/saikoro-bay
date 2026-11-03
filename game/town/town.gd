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


## What the town says on arrival about the last delve. An abandoned delve
## is said plainly, so a player who quit mid-delve knows why it counts.
const ARRIVAL: Dictionary[String, String] = {
	Haul.SURFACED: "You surfaced with your whole haul.",
	Haul.CLEARED: "You beat Koban and came up with everything.",
	Haul.WASHED_UP: "You washed up in a barrel. You kept half your resources. Anyone you rescued went back below the tide.",
	Haul.ABANDONED: "The game closed mid-delve, so you washed up in a barrel with nothing.",
}


func _status_text() -> String:
	var lines: PackedStringArray = []
	var last: Dictionary = Game.state.last_delve
	if ARRIVAL.has(str(last.get("outcome", ""))):
		lines.append(ARRIVAL[str(last["outcome"])])
		var kept: Dictionary = (last.get("kept", {}) as Dictionary).get("resources", {}) as Dictionary
		var parts: PackedStringArray = []
		for id: Variant in kept:
			var label: String = str(Game.data.row("resources", str(id)).get("name", id))
			parts.append("%s %d" % [label, int(kept[id])])
		if not parts.is_empty():
			lines.append("Brought back: " + ", ".join(parts))
	lines.append("Delves so far: %d" % Game.state.delve_count)
	if Game.saving_locked:
		lines.append("Saving is off: your save is from a newer version of the game.")
	return "\n".join(lines)


func _on_go_down_pressed() -> void:
	Game.go_down()
