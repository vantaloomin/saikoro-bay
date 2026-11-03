class_name SceneNotice
extends Control
## What a scene will show, before it plays (AC-5).
##
## Above SFW it's a modal: "This scene: Suggestive", what that shows, and
## Play scene (focused) or Change level, which opens the level picker right
## there (AC-2, at any time). A change saves at once and the lines follow
## it. At SFW there's no choice to make, so it's a one-line banner that
## fades after a few seconds and the scene starts at once (Mara's #56
## review).
##
## The scene player calls `open_for(levels)` with the levels the scene has
## versions for and plays the version `play_pressed` hands back (on the
## next frame for the banner, so connecting after `open_for` still works).
## Neutral skin, like the pause menu, so it reads as a setting.

## The scene may start; `level` is the version to show.
signal play_pressed(level: ContentLevel.Level)

const BANNER_SECONDS: float = 3.0
const BANNER_FADE_SECONDS: float = 0.5

var available: Array[ContentLevel.Level] = [ContentLevel.Level.SFW]
var _modal: Control
var _line: Label
var _cap: Label
var _description: Label
var _hint: Label
var _play: Button
var _change: Button
var _picker: ContentPicker
var _banner: PanelContainer
var _banner_line: Label
var _banner_tween: Tween


func _ready() -> void:
	theme = NeutralSkin.theme()
	# Made in code, so the offsets have to be set too, or it stays 0 by 0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal = _make_modal()
	add_child(_modal)
	_banner = _make_banner()
	add_child(_banner)
	close()
	Settings.changed.connect(_refresh)


## Shows the notice for a scene with versions at `levels`.
func open_for(levels: Array[ContentLevel.Level]) -> void:
	available = levels.duplicate()
	visible = true
	if shown_level() == ContentLevel.Level.SFW:
		_show_banner()
		return
	_picker.visible = false
	_modal.visible = true
	_refresh()
	_play.grab_focus()


## True while the modal waits for Play.
func is_waiting() -> bool:
	return visible and _modal.visible


## The level the scene would play at right now.
func shown_level() -> ContentLevel.Level:
	return ContentLevel.shown_level(Settings.effective_content_level(), available)


func close() -> void:
	_modal.visible = false
	_banner.visible = false
	visible = false


func _make_modal() -> Control:
	var modal: Control = Control.new()
	modal.name = "Modal"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(NeutralSkin.shade(0.5))
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var panel: PanelContainer = NeutralSkin.panel(620)
	center.add_child(panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	_line = NeutralSkin.paragraph("", 32)
	_line.name = "Line"
	stack.add_child(_line)
	_cap = NeutralSkin.paragraph("", 22)
	_cap.name = "Cap"
	stack.add_child(_cap)
	_description = NeutralSkin.paragraph("", 22, NeutralSkin.SOFT_INK)
	_description.name = "Description"
	stack.add_child(_description)
	_hint = NeutralSkin.paragraph("Changes the level for every scene. You can also change it from the pause menu.", 22, NeutralSkin.SOFT_INK)
	_hint.name = "Hint"
	stack.add_child(_hint)
	_picker = ContentPicker.new()
	_picker.name = "Picker"
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
	return modal


func _make_banner() -> PanelContainer:
	var banner: PanelContainer = NeutralSkin.panel(0)
	banner.name = "Banner"
	var box: StyleBoxFlat = banner.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	box.set_content_margin_all(16)
	box.content_margin_left = 28
	box.content_margin_right = 28
	banner.add_theme_stylebox_override("panel", box)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.offset_top = 112  # clear of the town's Menu button
	_banner_line = NeutralSkin.label("", 26)
	_banner_line.name = "Line"
	banner.add_child(_banner_line)
	return banner


func _show_banner() -> void:
	_modal.visible = false
	_banner_line.text = ContentLevel.notice_line(ContentLevel.Level.SFW)
	_banner.visible = true
	_banner.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_SECONDS)
	# Reduce motion: it just goes, no fade.
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.0 if SceneFlow.reduce_motion else BANNER_FADE_SECONDS)
	_banner_tween.tween_callback(close)
	play_pressed.emit.call_deferred(ContentLevel.Level.SFW)


func _refresh() -> void:
	if not is_waiting():
		return
	var shown: ContentLevel.Level = shown_level()
	var effective: ContentLevel.Level = Settings.effective_content_level()
	_line.text = ContentLevel.notice_line(shown)
	_cap.text = ContentLevel.cap_line(shown, effective)
	_cap.visible = not _cap.text.is_empty()
	_description.text = ContentLevel.DESCRIPTIONS[shown]
	# The open picker describes every level itself.
	_description.visible = not _picker.visible
	_hint.visible = _picker.visible
	# Nothing to change in a SFW build or for a player under 18.
	_change.visible = Settings.can_choose_level() and not _picker.visible
	_picker.show_settings()


func _open_picker() -> void:
	_picker.visible = true
	_refresh()
	var target: Control = _picker.focus_target()
	if target != null:
		target.grab_focus()


func _close_picker() -> void:
	_picker.visible = false
	_refresh()
	_change.grab_focus()


func _on_picked(level: ContentLevel.Level) -> void:
	Settings.set_content_level(level)
	_refresh()


func _on_play() -> void:
	var level: ContentLevel.Level = shown_level()
	close()
	play_pressed.emit(level)


func _unhandled_input(event: InputEvent) -> void:
	if not is_waiting():
		return
	# Back closes the picker and returns to the notice; the notice itself
	# waits for Play.
	if event.is_action_pressed(&"ui_cancel"):
		if _picker.visible:
			_close_picker()
		get_viewport().set_input_as_handled()
