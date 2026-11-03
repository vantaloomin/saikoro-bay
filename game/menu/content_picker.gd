class_name ContentPicker
extends VBoxContainer
## The content level choice (AC-2), in the neutral skin: one row per level,
## each with its name and what it shows, and a dot on the picked one.
##
## Used by the age gate, the pause menu and the scene notice. It only
## emits `picked`; whoever owns it decides when to save. When the level
## can't be changed (a SFW build, or a player under 18) it shows why
## instead of the rows.

signal picked(level: ContentLevel.Level)

const ROW_HEIGHT: float = 84.0

var level: ContentLevel.Level = ContentLevel.Level.SFW
var _rows: Dictionary[ContentLevel.Level, Button] = {}
var _dots: Dictionary[ContentLevel.Level, RadioDot] = {}
var _locked: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var group: ButtonGroup = ButtonGroup.new()
	for option: ContentLevel.Level in ContentLevel.NAMES:
		var row: Button = Button.new()
		row.name = ContentLevel.NAMES[option].to_pascal_case()
		row.toggle_mode = true
		row.button_group = group
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.tooltip_text = ContentLevel.DESCRIPTIONS[option]
		NeutralSkin.style_button(row)
		var line: HBoxContainer = HBoxContainer.new()
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 18
		line.offset_right = -18
		line.add_theme_constant_override("separation", 16)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot: RadioDot = RadioDot.new()
		dot.custom_minimum_size = Vector2(24, 24)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(dot)
		var words: VBoxContainer = VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 2)
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title: Label = NeutralSkin.label(ContentLevel.NAMES[option], 26)
		title.name = "Name"
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(title)
		var description: Label = NeutralSkin.label(ContentLevel.DESCRIPTIONS[option], 20, NeutralSkin.SOFT_INK)
		description.name = "Description"
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(description)
		line.add_child(words)
		row.add_child(line)
		row.pressed.connect(_on_row_pressed.bind(option))
		add_child(row)
		_rows[option] = row
		_dots[option] = dot
	_locked = NeutralSkin.paragraph("", 22, NeutralSkin.SOFT_INK)
	_locked.name = "Locked"
	_locked.visible = false
	add_child(_locked)
	set_level(ContentLevel.Level.SFW)


func _ready() -> void:
	# A row is a Button with its words laid over it, so it has to be told
	# how wide they are or a long description runs past its frame.
	for option: ContentLevel.Level in _rows:
		var line: Control = _rows[option].get_child(0) as Control
		_rows[option].custom_minimum_size.x = line.get_combined_minimum_size().x - line.offset_right + line.offset_left


## Shows `value` as picked without emitting `picked`.
func set_level(value: ContentLevel.Level) -> void:
	level = value
	for option: ContentLevel.Level in _rows:
		_rows[option].set_pressed_no_signal(option == value)
		_dots[option].on = option == value


## With a reason, hides the rows and says why the level is SFW; "" shows
## the rows again.
func set_locked(reason: String) -> void:
	for row: Button in _rows.values():
		row.visible = reason.is_empty()
	_locked.text = "%s %s" % [reason, ContentLevel.DESCRIPTIONS[ContentLevel.Level.SFW]] if not reason.is_empty() else ""
	_locked.visible = not reason.is_empty()


func is_locked() -> bool:
	return _locked.visible


## Shows what Settings holds now: its level, or why it's locked.
func show_settings() -> void:
	set_level(Settings.content_level if Settings.can_choose_level() else ContentLevel.Level.SFW)
	set_locked(Settings.level_locked_reason())


## The row for `option`, for focus and tests.
func row(option: ContentLevel.Level) -> Button:
	return _rows[option]


## The picked row, or null when locked, for focus.
func focus_target() -> Control:
	return null if is_locked() else _rows[level]


func _on_row_pressed(option: ContentLevel.Level) -> void:
	set_level(option)
	picked.emit(option)


## The picked mark: a ring, filled when on.
class RadioDot:
	extends Control

	var on: bool = false:
		set(value):
			on = value
			queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size / 2.0
		var radius: float = minf(size.x, size.y) / 2.0 - 1.0
		draw_arc(center, radius, 0.0, TAU, 32, NeutralSkin.INK, 2.0, true)
		if on:
			draw_circle(center, radius - 5.0, NeutralSkin.INK, true, -1.0, true)
