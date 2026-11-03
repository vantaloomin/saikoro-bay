extends Node
## Moves between the two halves through the tide transition.
##
## Autoload "SceneFlow". While a transition runs, `busy` is true, GUI input is
## off (no double clicks, no clicks on the scene being left), and saving is
## blocked, so a save never captures half of each world.
##
## Also gives keyboard and controller players a starting focus: the first
## navigation press with nothing focused focuses the scene's node in the
## "default_focus" group.

signal transition_started(direction: TideTransition.Direction)
signal transition_finished(direction: TideTransition.Direction)

const TRANSITION_SCENE: PackedScene = preload("res://game/transition/tide_transition.tscn")
const FOCUS_GROUP: StringName = &"default_focus"
const NAV_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev", &"ui_accept",
]

## Swaps the sweep for a short fade (SA-7). Settings will own this later.
var reduce_motion: bool = false

var busy: bool:
	get:
		return _busy

var _busy: bool = false
var _overlay: TideTransition


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = TRANSITION_SCENE.instantiate() as TideTransition
	add_child(_overlay)


## Changes to `scene_path` behind the tide. Returns false (and does nothing)
## if a transition is already running.
func change_half(scene_path: String, direction: TideTransition.Direction) -> bool:
	if _busy:
		return false
	_busy = true
	get_viewport().gui_disable_input = true
	transition_started.emit(direction)

	await _overlay.cover(direction, reduce_motion)
	var error: Error = get_tree().change_scene_to_file(scene_path)
	assert(error == OK, "couldn't load %s" % scene_path)
	# change_scene_to_file swaps on the next frame; wait for the new scene.
	await get_tree().scene_changed
	await _overlay.reveal(direction, reduce_motion)

	get_viewport().gui_disable_input = false
	_busy = false
	transition_finished.emit(direction)
	focus_default()
	return true


## Changes scene with no transition (boot and loading).
func change_instant(scene_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene_path)


## Focuses the current scene's default control, if it has one.
func focus_default() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for node: Node in get_tree().get_nodes_in_group(FOCUS_GROUP):
		var control: Control = node as Control
		if control != null and scene.is_ancestor_of(control) and control.is_visible_in_tree():
			control.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	if _busy or get_viewport().gui_get_focus_owner() != null:
		return
	for action: StringName in NAV_ACTIONS:
		if event.is_action_pressed(action):
			focus_default()
			get_viewport().set_input_as_handled()
			return
