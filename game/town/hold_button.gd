class_name HoldButton
extends Button
## A button you hold instead of click, for a step that can't be undone
## (two-halves section 3: hold Y for Go down). The button teaches the hold
## itself (Mara's #41 review): holding sweeps a tide fill across it, letting
## go drains the fill back, and a short press gives a small wiggle (an
## outline flash with reduce motion), so there's no confirm dialog. Works
## with the mouse, touch, ui_accept on focus, and start_hold()/stop_hold()
## for a controller button held anywhere.

signal held

const HOLD_SECONDS: float = 0.6
const DRAIN_SECONDS: float = 0.3
## Let go before this much of the fill, and the button nudges.
const SHORT_PRESS: float = 0.5
const NUDGE_SECONDS: float = 0.3
const FILL: Color = Color(0.29, 0.62, 0.64, 0.5)

var _holding: bool = false
var _progress: float = 0.0
var _flash: float = 0.0


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
	set_process(true)


func stop_hold() -> void:
	if not _holding:
		return
	_holding = false
	if _progress < SHORT_PRESS:
		nudge()


## How full the hold is, 0 to 1.
func progress() -> float:
	return _progress


func is_holding() -> bool:
	return _holding


## "Keep holding": a quick wiggle, or an outline flash with reduce motion.
func nudge() -> void:
	if Settings.reduce_motion or not is_inside_tree():
		_flash = NUDGE_SECONDS
		set_process(true)
		queue_redraw()
		return
	pivot_offset = size / 2.0
	var tween: Tween = create_tween()
	for angle: float in [-2.0, 2.0, -1.0, 0.0]:
		tween.tween_property(self, "rotation_degrees", angle, NUDGE_SECONDS / 4.0)


func _process(delta: float) -> void:
	advance(delta)


## Moves the hold on by `seconds`: fills while held, drains after. Emits
## held once when the fill completes.
func advance(seconds: float) -> void:
	_flash = maxf(_flash - seconds, 0.0)
	if _holding:
		_progress = minf(_progress + seconds / HOLD_SECONDS, 1.0)
		if _progress >= 1.0:
			_holding = false
			_progress = 0.0
			held.emit()
	else:
		_progress = maxf(_progress - seconds / DRAIN_SECONDS, 0.0)
	if not _holding and _progress <= 0.0 and _flash <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _progress > 0.0:
		draw_rect(Rect2(Vector2(4, 4), Vector2((size.x - 8.0) * _progress, size.y - 8.0)), FILL)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), TownStyle.INK, false, 4.0)
