class_name TallyPanel
extends Control
## The return-to-town tally (specs/bridge.md section 6), in delve style: how
## the delve ended, then what was banked line by line, what the barrel took
## hatched in the same layout, who you rescued with their perk, and the
## landmark you won. It always waits for Continue, so nobody misses what the
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


## A line the barrel took: drawn struck through and hatched, so a loss
## reads in the same layout as a gain, not as a separate warning.
class Struck:
	extends Control
	var text: String = ""

	func _init(words: String) -> void:
		text = words
		var font: Font = BoardStyle.theme().default_font
		custom_minimum_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY) + Vector2(16, 12)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# The hatching runs past the corners; keep it inside the line.
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font: Font = BoardStyle.theme().default_font
		for step: int in range(0, int(size.x + size.y), 12):
			draw_line(Vector2(step, 0), Vector2(step - size.y, size.y), Color(BoardStyle.DIM, 0.22), 2.0)
		draw_string(font, Vector2(8, size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY, BoardStyle.DIM)
		draw_line(Vector2(4, size.y * 0.52), Vector2(size.x - 4, size.y * 0.52), BoardStyle.DIM, 2.0)


## The tally's lines, in order: {"kind", "text"}, where kind is "headline",
## "note", "gain", "lost", "join" or "landmark".
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
	for id: String in game_data.ids("resources"):
		var banked: int = int(kept_resources.get(id, 0))
		var taken: int = int(lost_resources.get(id, 0))
		if banked > 0:
			out.append({"kind": "gain", "text": "+%d %s" % [banked, GameState.amount_name(game_data, id, banked)]})
		if taken > 0:
			out.append({"kind": "lost", "text": "%d %s · the barrel" % [taken, GameState.amount_name(game_data, id, taken)]})
	for villager: Variant in settled.get("rescued", []) as Array:
		out.append({"kind": "join", "text": _joins(game_data, str(villager))})
	for villager: Variant in lost.get("villagers", []) as Array:
		out.append({"kind": "lost", "text": "%s · still below" % _role(game_data, str(villager))})
	var landmark: String = str(settled.get("landmark", ""))
	if not landmark.is_empty():
		out.append({"kind": "landmark", "text": "%s · yours to place" % _landmark_name(game_data, landmark)})
	var lost_landmark: String = str(lost.get("landmark", ""))
	if not lost_landmark.is_empty():
		out.append({"kind": "lost", "text": "%s · still below" % _landmark_name(game_data, lost_landmark)})
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
	for line: Dictionary in lines(data, settlement):
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


## Lines appear one after another; at once with reduced motion.
func _reveal() -> void:
	if Settings.reduce_motion:
		return
	for i: int in _rows.size():
		_rows[i].modulate.a = 0.0
		var tween: Tween = create_tween()
		tween.tween_interval(i * LINE_SECONDS)
		tween.tween_property(_rows[i], "modulate:a", 1.0, LINE_SECONDS)


func _row(line: Dictionary) -> Control:
	var text: String = str(line["text"])
	match str(line["kind"]):
		"headline":
			# Gold means a gain on the delve side, so a wash-up's is ink.
			var lost: bool = str(settlement.get("outcome", "")) in [Haul.WASHED_UP, Haul.ABANDONED]
			var headline: Label = BoardStyle.label(text, BoardStyle.BIG, BoardStyle.INK if lost else BoardStyle.GOLD)
			headline.add_theme_font_override("font", BoardStyle.title_font())
			return headline
		"note":
			var note: Label = BoardStyle.label(text, BoardStyle.SMALL, BoardStyle.DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(696, 0)
			return note
		"lost":
			return Struck.new(text)
		"join", "landmark":
			var joined: Label = BoardStyle.label(text, BoardStyle.BODY, BoardStyle.JADE)
			joined.add_theme_font_override("font", BoardStyle.strong_font())
			return joined
	var gain: Label = BoardStyle.label(text, BoardStyle.NUMBER, BoardStyle.INK)
	gain.add_theme_font_override("font", BoardStyle.strong_font())
	return gain


func _on_continue() -> void:
	if Time.get_ticks_msec() < _shown_at + GUARD_MS:
		return
	continued.emit()
