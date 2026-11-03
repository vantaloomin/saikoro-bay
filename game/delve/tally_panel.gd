class_name TallyPanel
extends Control
## The return-to-town tally (specs/bridge.md section 6), in delve style: how
## the delve ended, then who you rescued with their perk, the landmark you
## won, and what was banked, each resource with the barrel's share hatched
## beside it. It always waits for Continue, so nobody misses what the
## barrel took (Mara's bridge review). It reads Game.settlement, which was
## banked and saved before it showed (Imogen's bridge review).

signal continued

## A press this soon after the tally shows is one meant for the screen
## before it, as on the room boards' results.
const GUARD_MS: int = 400
## Lines appear one after another, unless motion is reduced.
const LINE_SECONDS: float = 0.12
const HEADLINES: Dictionary[String, String] = {
	Haul.SURFACED: "Surfaced",
	Haul.CLEARED: "Cleared the vault",
	Haul.WASHED_UP: "Washed up",
	Haul.ABANDONED: "Washed up",
}
const NOTHING: String = "Nothing came up with you."
const BARREL: String = "The barrel took half your haul, and anyone with you went back below."

var data: GameData
var settlement: Dictionary = {}
var continue_button: Button
var _shown_at: int = 0
var _rows: Array[Control] = []
var _name_width: float = 0.0


## What the barrel took from one resource, beside what you kept: hatched
## like a spent shell, never struck through, so the numbers stay readable
## (Mara's #58 review).
class Barrel:
	extends Control
	var text: String = ""

	func _init(words: String) -> void:
		text = words
		var font: Font = BoardStyle.theme().default_font
		custom_minimum_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY) + Vector2(24, 14)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# The hatching runs past the corners; keep it inside the chip.
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font: Font = BoardStyle.theme().default_font
		for step: int in range(0, int(size.x + size.y), 10):
			draw_line(Vector2(step, 0), Vector2(step - size.y, size.y), Color(BoardStyle.DIM, 0.18), 2.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(BoardStyle.DIM, 0.5), false, 1.0)
		draw_string(font, Vector2(12, size.y * 0.7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY, BoardStyle.INK)


## The tally's lines, in order: people, then places, then resources (Mara's
## #58 review). Each is {"kind", "text"}, where kind is "headline", "note",
## "join", "landmark", "below" or "resource"; a resource line also has
## "amount" ("+4"), "name" and "barrel" ("−5 to the barrel", or "").
static func lines(game_data: GameData, settled: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var outcome: String = str(settled.get("outcome", ""))
	out.append({"kind": "headline", "text": HEADLINES.get(outcome, "Back in town")})
	var kept: Dictionary = settled.get("kept", {}) as Dictionary
	var lost: Dictionary = settled.get("lost", {}) as Dictionary
	var kept_resources: Dictionary = kept.get("resources", {}) as Dictionary
	var lost_resources: Dictionary = lost.get("resources", {}) as Dictionary
	if outcome in [Haul.WASHED_UP, Haul.ABANDONED] and not _empty(lost):
		out.append({"kind": "note", "text": BARREL})
	for villager: Variant in settled.get("rescued", []) as Array:
		out.append({"kind": "join", "text": _joins(game_data, str(villager))})
	var landmark: String = str(settled.get("landmark", ""))
	if not landmark.is_empty():
		out.append({"kind": "landmark", "text": "%s · yours to place" % _landmark_name(game_data, landmark)})
	for villager: Variant in lost.get("villagers", []) as Array:
		out.append({"kind": "below", "text": "%s is still below · you can bring them up next delve"
			% _role(game_data, str(villager))})
	var lost_landmark: String = str(lost.get("landmark", ""))
	if not lost_landmark.is_empty():
		out.append({"kind": "below", "text": "%s is still below · you can win it next delve"
			% _landmark_name(game_data, lost_landmark)})
	for id: String in game_data.ids("resources"):
		var banked: int = int(kept_resources.get(id, 0))
		var taken: int = int(lost_resources.get(id, 0))
		if banked <= 0 and taken <= 0:
			continue
		var noun: String = GameState.amount_name(game_data, id, banked)
		var barrel: String = "−%d to the barrel" % taken if taken > 0 else ""
		out.append({"kind": "resource", "text": "+%d %s" % [banked, noun], "amount": "+%d" % banked, "name": noun,
			"barrel": barrel})
	if out.size() == 1:
		out.append({"kind": "note", "text": NOTHING})
	return out


## "Pearl diver joins · Nudge": the moment the player learns that rescuing
## people changes the dice (Mara's bridge review).
static func _joins(game_data: GameData, villager: String) -> String:
	var perk_id: String = str(game_data.row("villagers", villager).get("perk", "")) if game_data.has_row("villagers", villager) else ""
	var words: String = "%s joins" % _role(game_data, villager)
	if game_data.has_row("perks", perk_id):
		words += " · " + str(game_data.row("perks", perk_id)["name"])
	return words


static func _role(game_data: GameData, villager: String) -> String:
	return str(game_data.row("villagers", villager).get("role", villager)) if game_data.has_row("villagers", villager) else villager


static func _landmark_name(game_data: GameData, landmark: String) -> String:
	return str(game_data.row("landmarks", landmark).get("name", landmark)) if game_data.has_row("landmarks", landmark) else landmark


static func _empty(haul: Dictionary) -> bool:
	return (haul.get("resources", {}) as Dictionary).is_empty() and (haul.get("villagers", []) as Array).is_empty() \
		and str(haul.get("landmark", "")).is_empty()


func setup(game_data: GameData, settled: Dictionary) -> void:
	data = game_data
	settlement = settled


func _ready() -> void:
	theme = BoardStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(BoardStyle.BACKGROUND, 0.92)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = BoardStyle.panel()
	box.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var shown: Array[Dictionary] = lines(data, settlement)
	# The barrel chips stack in their own column, after the longest name
	# (Mara's #58 review).
	for line: Dictionary in shown:
		if line["kind"] == "resource":
			_name_width = maxf(_name_width, BoardStyle.strong_font().get_string_size(str(line["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.NUMBER).x)
	for line: Dictionary in shown:
		var row: Control = _row(line)
		column.add_child(row)
		_rows.append(row)
	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(0, 72)
	continue_button.add_theme_font_size_override("font_size", BoardStyle.BODY)
	continue_button.add_theme_font_override("font", BoardStyle.strong_font())
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var face: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD, BoardStyle.GOLD if state != "normal" else BoardStyle.LACQUER)
		continue_button.add_theme_stylebox_override(state, face)
	continue_button.add_theme_color_override("font_hover_color", BoardStyle.LACQUER)
	continue_button.add_theme_color_override("font_focus_color", BoardStyle.LACQUER)
	continue_button.add_theme_color_override("font_pressed_color", BoardStyle.LACQUER)
	continue_button.pressed.connect(_on_continue)
	column.add_child(continue_button)
	_shown_at = Time.get_ticks_msec()
	_reveal()
	continue_button.grab_focus.call_deferred()


## Lines appear one after another; at once with reduced motion. A
## wash-up's barrel sounds as the first line it took from appears, or as
## the panel opens with reduced motion (Mara's #58 review), so the town's
## uncovering stays a relief.
func _reveal() -> void:
	var barrel_at: int = _barrel_row()
	if Settings.reduce_motion:
		if barrel_at >= 0:
			_play_barrel()
		return
	for i: int in _rows.size():
		_rows[i].modulate.a = 0.0
		var tween: Tween = create_tween()
		tween.tween_interval(i * LINE_SECONDS)
		if i == barrel_at:
			tween.tween_callback(_play_barrel)
		tween.tween_property(_rows[i], "modulate:a", 1.0, LINE_SECONDS)


## The row the barrel sounds on, or -1 when it doesn't (not a wash-up).
func _barrel_row() -> int:
	if str(settlement.get("outcome", "")) != Haul.WASHED_UP:
		return -1
	var shown: Array[Dictionary] = lines(data, settlement)
	for i: int in shown.size():
		if not str(shown[i].get("barrel", "")).is_empty():
			return i
	return 0


func _play_barrel() -> void:
	Soundscape.stinger(Soundscape.barrel_for(int(settlement.get("delve", 0))))


func _row(line: Dictionary) -> Control:
	var text: String = str(line["text"])
	match str(line["kind"]):
		"headline":
			# Gold means a gain on the delve side, so a wash-up's is ink.
			var lost: bool = str(settlement.get("outcome", "")) in [Haul.WASHED_UP, Haul.ABANDONED]
			var headline: Label = BoardStyle.label(text, BoardStyle.BIG, BoardStyle.INK if lost else BoardStyle.GOLD)
			headline.add_theme_font_override("font", BoardStyle.title_font())
			return headline
		"note", "below":
			var note: Label = BoardStyle.label(text, BoardStyle.SMALL, BoardStyle.DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(696, 0)
			return note
		"join", "landmark":
			# People and places at the resources' size: they're the bigger
			# event (Mara's #58 review).
			var joined: Label = BoardStyle.label(text, BoardStyle.NUMBER, BoardStyle.JADE)
			joined.add_theme_font_override("font", BoardStyle.strong_font())
			return joined
	return _resource_row(line)


## "+4 driftwood ▨ −5 to the barrel": the amount right-aligned in tabular
## figures, the barrel's share hatched on the same row.
func _resource_row(line: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var font: Font = BoardStyle.strong_font()
	var amount: Label = BoardStyle.label(str(line["amount"]), BoardStyle.NUMBER, BoardStyle.INK)
	amount.add_theme_font_override("font", font)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.custom_minimum_size.x = font.get_string_size("+88", HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.NUMBER).x
	row.add_child(amount)
	var noun: Label = BoardStyle.label(str(line["name"]), BoardStyle.NUMBER, BoardStyle.INK)
	noun.add_theme_font_override("font", font)
	noun.custom_minimum_size.x = _name_width
	row.add_child(noun)
	if not str(line["barrel"]).is_empty():
		row.add_child(Barrel.new(str(line["barrel"])))
	return row


func _on_continue() -> void:
	if Time.get_ticks_msec() < _shown_at + GUARD_MS:
		return
	continued.emit()
