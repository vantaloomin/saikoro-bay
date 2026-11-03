extends Control
## First scene: loads the save and drops the player into the right half.


func _ready() -> void:
	SceneFlow.change_instant(Game.load_or_new())
