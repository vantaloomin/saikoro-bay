class_name SceneNotice
extends Control
## The line before a scene plays (AC-5): "This scene plays at Suggestive."
## with what that level shows, so there are no surprises. "Change level"
## opens the level picker right there (AC-2, at any time); a change saves
## at once and the line follows it.
##
## The scene player calls `open_for(levels)` with the levels the scene has
## versions for and plays the version `play_pressed` hands back. Neutral
## skin, like the pause menu, so it reads as a setting, not as the scene.

## The player chose to play; `level` is the version to show.
signal play_pressed(level: ContentLevel.Level)

var available: Array[ContentLevel.Level] = [ContentLevel.Level.SFW]
var _line: Label
var _description: Label
var _play: Button
var _change: Button
var _picker: ContentPicker


func _ready() -> void:
	theme = NeutralSkin.theme()
	# Made in code, so the offsets have to be set too, or it stays 0 by 0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(NeutralSkin.shade(0.5))
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel: PanelContainer = NeutralSkin.panel(620)
	center.add_child(panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	_line = NeutralSkin.paragraph("", 30)
	_line.name = "Line"
	stack.add_child(_line)
	_description = NeutralSkin.paragraph("", 22, NeutralSkin.SOFT_INK)
	_description.name = "Description"
	stack.add_child(_description)
	_picker = ContentPicker.new()
	_picker.name = "Picker"
	_picker.visible = false
	_picker.picked.connect(_on_picked)
	stack.add_child(_picker)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	stack.add_child(buttons)
	_play = NeutralSkin.button("Play scene")
	_play.name = "Play"
	_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	_change = NeutralSkin.button("Change level")
	_change.name = "Change"
	_change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_change.pressed.connect(_open_picker)
	buttons.add_child(_change)


## Shows the notice for a scene with versions at `levels`.
func open_for(levels: Array[ContentLevel.Level]) -> void:
	available = levels.duplicate()
	_picker.visible = false
	_refresh()
	visible = true
	_play.grab_focus()


## The level the scene would play at right now.
func shown_level() -> ContentLevel.Level:
	return ContentLevel.shown_level(Settings.effective_content_level(), available)


func close() -> void:
	visible = false


func _refresh() -> void:
	var shown: ContentLevel.Level = shown_level()
	_line.text = ContentLevel.notice_line(shown, Settings.effective_content_level())
	_description.text = ContentLevel.DESCRIPTIONS[shown]
	# The open picker describes every level itself.
	_description.visible = not _picker.visible
	# Nothing to change in a SFW build or for a player under 18.
	_change.visible = Settings.can_choose_level() and not _picker.visible
	_picker.show_settings()


func _open_picker() -> void:
	_picker.visible = true
	_refresh()
	var target: Control = _picker.focus_target()
	if target != null:
		target.grab_focus()


func _on_picked(level: ContentLevel.Level) -> void:
	Settings.set_content_level(level)
	_refresh()


func _on_play() -> void:
	var level: ContentLevel.Level = shown_level()
	close()
	play_pressed.emit(level)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Back closes the picker; the notice itself waits for Play.
	if event.is_action_pressed(&"ui_cancel") and _picker.visible:
		_picker.visible = false
		_refresh()
		_change.grab_focus()
		get_viewport().set_input_as_handled()
