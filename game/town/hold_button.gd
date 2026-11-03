class_name HoldButton
extends Button
## A button you hold instead of click, for a step that can't be undone
## (two-halves section 3: hold Y for Go down). Holding fills a bar under the
## text; letting go early resets it, so there's no confirm dialog. Works
## with the mouse, touch, ui_accept on focus, and start_hold()/stop_hold()
## for a controller button held anywhere.

signal held

const HOLD_SECONDS: float = 0.8

var _holding: bool = false
var _progress: float = 0.0


func _ready() -> void:
	button_down.connect(start_hold)
	button_up.connect(stop_hold)
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	if event.is_action("ui_accept") and not event.is_echo():
		if event.is_pressed():
			start_hold()
		else:
			stop_hold()
		accept_event()


func start_hold() -> void:
	if disabled or _holding:
		return
	_holding = true
	_progress = 0.0
	set_process(true)


func stop_hold() -> void:
	_holding = false
	_progress = 0.0
	set_process(false)
	queue_redraw()


## How far the hold has got, 0 to 1.
func progress() -> float:
	return _progress


func _process(delta: float) -> void:
	advance(delta)


## Moves the hold on by `seconds`. Emits held once when it fills.
func advance(seconds: float) -> void:
	if not _holding:
		return
	_progress = minf(_progress + seconds / HOLD_SECONDS, 1.0)
	queue_redraw()
	if _progress >= 1.0:
		stop_hold()
		held.emit()


func _draw() -> void:
	if _progress <= 0.0:
		return
	var bar: Rect2 = Rect2(Vector2(8, size.y - 12), Vector2((size.x - 16) * _progress, 6))
	draw_rect(bar, TownStyle.VERMILION)
