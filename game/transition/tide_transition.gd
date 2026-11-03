class_name TideTransition
extends CanvasLayer
## Stub tide transition: a sheet of water sweeps over the screen and away.
## The final transition (PF-3) replaces the look, not this interface.

enum Direction {
	DOWN,  ## Town -> delve: the tide rises over the screen.
	UP,    ## Delve -> town: the water drains away.
}

const SWEEP_SECONDS: float = 0.7
const FADE_SECONDS: float = 0.25

@onready var _water: ColorRect = %Water


func _ready() -> void:
	_water.visible = false


## Covers the screen. DOWN rises from the bottom; UP falls from the top.
func cover(direction: Direction, reduce_motion: bool) -> void:
	var size: Vector2 = _water.get_viewport_rect().size
	_water.size = size
	_water.visible = true
	var tween: Tween = create_tween()
	if reduce_motion:
		_water.position = Vector2.ZERO
		_water.modulate.a = 0.0
		tween.tween_property(_water, "modulate:a", 1.0, FADE_SECONDS)
	else:
		_water.modulate.a = 1.0
		var start_y: float = size.y if direction == Direction.DOWN else -size.y
		_water.position = Vector2(0.0, start_y)
		tween.tween_property(_water, "position:y", 0.0, SWEEP_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


## Uncovers the screen, continuing the same way the water came in.
func reveal(direction: Direction, reduce_motion: bool) -> void:
	var size: Vector2 = _water.get_viewport_rect().size
	var tween: Tween = create_tween()
	if reduce_motion:
		tween.tween_property(_water, "modulate:a", 0.0, FADE_SECONDS)
	else:
		var end_y: float = -size.y if direction == Direction.DOWN else size.y
		tween.tween_property(_water, "position:y", end_y, SWEEP_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_water.visible = false
