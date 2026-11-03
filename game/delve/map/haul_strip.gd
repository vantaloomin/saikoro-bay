class_name HaulStrip
extends PanelContainer
## The haul strip (DM-8, Mara's review #6): a fixed strip along the top of
## the map and every room. HP, each resource with "+N" when it changes,
## chips for a rescued villager and a won landmark, and how far the next
## safe exit is. What's at risk (the halves) only shows at the landing.

const HEIGHT: int = 64
const DELTA_SECONDS: float = 2.0

var data: GameData

var _hp: Label
var _hp_bar: HpBar
var _hp_delta: Label
var _amounts: Dictionary[String, Label] = {}
var _deltas: Dictionary[String, Label] = {}
var _chips: HBoxContainer
var _progress: Label
var _shown: Dictionary[String, int] = {}
var _shown_hp: int = -1


func setup(game_data: GameData) -> void:
	data = game_data


func _ready() -> void:
	theme = BoardStyle.theme()
	var box: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD, BoardStyle.LACQUER)
	box.set_border_width_all(0)
	box.border_width_bottom = 2
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.content_margin_left = 40
	box.content_margin_right = 40
	add_theme_stylebox_override("panel", box)
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Shows the run as the player sees it. Changes since the last call show as
## "+N" (or "-N" for HP) for a moment.
func show_view(view: RunView) -> void:
	var haul: Haul = view.haul()
	_hp.text = "HP %d / %d" % [view.hp(), view.max_hp()]
	_hp_bar.max_hp = view.max_hp()
	_hp_bar.hp = view.hp()
	if _shown_hp >= 0 and view.hp() != _shown_hp:
		var change: int = view.hp() - _shown_hp
		_flash(_hp_delta, "%+d" % change, BoardStyle.JADE if change > 0 else BoardStyle.DANGER)
	_shown_hp = view.hp()
	for id: String in _amounts:
		var amount: int = haul.resource(id)
		_amounts[id].text = str(amount)
		if _shown.has(id) and amount > _shown[id]:
			_flash(_deltas[id], "+%d" % (amount - _shown[id]), BoardStyle.GOLD)
		elif _shown.has(id) and amount < _shown[id]:
			_flash(_deltas[id], "%d" % (amount - _shown[id]), BoardStyle.DANGER)
		_shown[id] = amount
	_show_chips(haul)
	_progress.text = progress_text(view)


static func progress_text(view: RunView) -> String:
	var floor_text: String = "Floor %d of %d" % [view.floor_index() + 1, view.floor_count()]
	match view.step():
		DelveRun.Step.LANDING:
			return "%s · at the landing" % floor_text
		DelveRun.Step.VAULT:
			return "Koban's vault"
		DelveRun.Step.CHOOSE_ROOM, DelveRun.Step.IN_ROOM:
			var exit_name: String = "vault" if view.floor_index() == view.floor_count() - 1 else "landing"
			var left: int = view.rooms_to_landing()
			if view.step() == DelveRun.Step.CHOOSE_ROOM:
				return "%s · %s in %d room%s" % [floor_text, exit_name, left, "" if left == 1 else "s"]
			if left == 0:
				return "%s · %s after this room" % [floor_text, exit_name]
			return "%s · %s %d room%s after this" % [floor_text, exit_name, left, "" if left == 1 else "s"]
	return floor_text


func _build() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	add_child(row)
	_hp = BoardStyle.label("", BoardStyle.BODY)
	row.add_child(_hp)
	_hp_bar = HpBar.new()
	_hp_bar.custom_minimum_size = Vector2(200, 22)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hp_bar)
	_hp_delta = _delta_label()
	row.add_child(_hp_delta)
	for id: String in data.ids("resources"):
		var name_label: Label = BoardStyle.label(data.row("resources", id)["name"], BoardStyle.BODY, BoardStyle.DIM)
		row.add_child(name_label)
		var amount: Label = BoardStyle.label("0", BoardStyle.BODY)
		amount.add_theme_font_override("font", BoardStyle.strong_font())
		row.add_child(amount)
		_amounts[id] = amount
		var delta: Label = _delta_label()
		row.add_child(delta)
		_deltas[id] = delta
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 12)
	row.add_child(_chips)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_progress = BoardStyle.label("", BoardStyle.BODY)
	row.add_child(_progress)


func _delta_label() -> Label:
	var l: Label = BoardStyle.label("", BoardStyle.BODY, BoardStyle.GOLD)
	l.add_theme_font_override("font", BoardStyle.strong_font())
	l.custom_minimum_size = Vector2(44, 0)
	l.modulate.a = 0.0
	return l


func _flash(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 1.0
	if not is_inside_tree():
		return
	var tween: Tween = label.create_tween()
	if not Settings.reduce_motion:
		# Flies up into place, so the gain is noticed (Mara #6).
		label.position.y += 18
		tween.tween_property(label, "position:y", label.position.y - 18, BoardStyle.STEP_SECONDS)
	tween.tween_interval(DELTA_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, BoardStyle.STEP_SECONDS)


func _show_chips(haul: Haul) -> void:
	for child: Node in _chips.get_children():
		child.queue_free()
	for villager: String in haul.villagers:
		var chip: FaceChip = FaceChip.new()
		chip.villager_id = villager
		chip.role = data.row("villagers", villager)["role"] if data.has_row("villagers", villager) else villager
		chip.custom_minimum_size = Vector2(44, 44)
		chip.tooltip_text = chip.role
		_chips.add_child(chip)
	if not haul.landmark.is_empty():
		var landmark: Label = BoardStyle.label(data.row("landmarks", haul.landmark)["name"], BoardStyle.SMALL, BoardStyle.GOLD)
		var holder: PanelContainer = PanelContainer.new()
		var box: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD)
		box.set_content_margin_all(4)
		holder.add_theme_stylebox_override("panel", box)
		holder.add_child(landmark)
		_chips.add_child(holder)
