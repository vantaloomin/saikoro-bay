extends Control
## First scene: the age gate on a first launch (AC-1), then loads the save
## and drops the player into the right half.


func _ready() -> void:
	if Settings.needs_age_gate():
		var gate: AgeGate = AgeGate.new()
		gate.name = "AgeGate"
		add_child(gate)
		await gate.finished
	SceneFlow.change_instant(Game.load_or_new())
