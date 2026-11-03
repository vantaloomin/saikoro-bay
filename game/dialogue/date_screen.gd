class_name DateScreen
extends Control
## A date (M5: RD-1, RD-2, RD-8), over the town: the spot behind, the
## villager's portrait, and a text box with their lines and your answers.
##
## The script plays against the DateSession, never the game. Leaving
## midway ("Leave", Esc or B) spends and earns nothing. At the end the one
## sim call spends the action and keeps the affection, and the game saves;
## the card then says what the date added and the next milestone. A date
## that reaches the scene's milestone plays the villager's invitation
## (~ scene_invite) before the card.
##
## A press finishes a line still typing, the next press moves on (SN-4).
## Under reduce motion lines appear whole. A content level changed from the
## pause menu mid-date applies from the next line.

signal closed(kept: bool)

const SPOT_COLORS: Dictionary[String, Color] = {
	"cafe": Color(0.91, 0.84, 0.72),
	"hot_spring": Color(0.74, 0.85, 0.84),
}
const CHARS_PER_SECOND: float = 60.0
const BOX_WIDTH: float = 1400.0

var session: DateSession
var runner: DialogueRunner
## "playing", "invite", "result" or "refused".
var stage: String = "playing"
## What finish_date returned, for the result card.
var refusals: Array[Dictionary] = []
var scene_reached: bool = false

var _background: ColorRect
var _spot_label: Label
var _portrait: Portrait
var _box: PanelContainer
var _name_plate: Label
var _text: RichTextLabel
var _responses: VBoxContainer
var _more: Label
var _leave: Button
var _typing: Tween


## Builds the screen for `date` and starts its script. Await it, or listen
## for `closed`.
func open(date: DateSession) -> void:
	session = date
	Settings.changed.connect(_on_settings_changed)
	_build()
	var resource: DialogueResource = load(session.script_path) as DialogueResource
	runner = DialogueRunner.new(resource, session)
	await runner.start(DateSession.TITLE)
	_show_line()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = TownStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_background = ColorRect.new()
	_background.color = SPOT_COLORS.get(session.spot, TownStyle.SKY)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_spot_label = TownStyle.title_label(str(Game.data.row("landmarks", session.spot).get("name", session.spot)))
	_spot_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_spot_label.position = Vector2(48, 36)
	add_child(_spot_label)
	_leave = Button.new()
	_leave.text = "Leave · nothing spent"
	_leave.name = "Leave"
	TownStyle.style_button(_leave, TownStyle.SMALL)
	_leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_leave.position = Vector2(-48 - 320, 36)
	_leave.custom_minimum_size = Vector2(320, 0)
	_leave.pressed.connect(leave)
	add_child(_leave)
	_portrait = Portrait.new()
	_portrait.name = "Portrait"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_portrait.size = Vector2(480, 640)
	_portrait.position = Vector2(-240, 60)
	add_child(_portrait)
	_box = PanelContainer.new()
	_box.name = "Box"
	_box.add_theme_stylebox_override("panel", TownStyle.panel())
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.custom_minimum_size = Vector2(BOX_WIDTH, 260)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.position = Vector2(-BOX_WIDTH / 2.0, -60 - 260)
	_box.gui_input.connect(_on_box_input)
	add_child(_box)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(stack)
	_name_plate = TownStyle.label("", TownStyle.TITLE)
	_name_plate.name = "NamePlate"
	stack.add_child(_name_plate)
	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_color_override("default_color", TownStyle.INK)
	_text.add_theme_font_size_override("normal_font_size", TownStyle.TITLE)
	_text.add_theme_font_size_override("italics_font_size", TownStyle.TITLE)
	stack.add_child(_text)
	_responses = VBoxContainer.new()
	_responses.name = "Responses"
	_responses.add_theme_constant_override("separation", 8)
	stack.add_child(_responses)
	_more = TownStyle.label("", TownStyle.SMALL, TownStyle.DIM)
	_more.name = "More"
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_more)


## The speaker's name for the plate: the villager's name once data has
## one, else their role; "" for narration.
static func speaker_name(data: GameData, id: String) -> String:
	if id.is_empty():
		return ""
	if data.has_row("villagers", id):
		var row: Dictionary = data.row("villagers", id)
		return str(row.get("name", row.get("role", id)))
	return id.capitalize()


func _show_line() -> void:
	for old: Node in _responses.get_children():
		old.queue_free()
	var line: DialogueLine = runner.line
	if line == null:
		_on_script_end()
		return
	_name_plate.text = speaker_name(Game.data, line.character)
	_name_plate.visible = not line.character.is_empty()
	if not line.character.is_empty():
		_name_plate.add_theme_color_override("font_color", Portrait.hue_of(line.character).darkened(0.25))
	if line.character == session.villager or _portrait.character.is_empty():
		_portrait.show_face(session.villager, DialogueRunner.tag(line, "face") if line.character == session.villager else "")
	_text.text = line.text
	_type_in()
	var index: int = 0
	for response: DialogueResponse in line.responses:
		var button: Button = Button.new()
		button.text = response.text
		button.name = "Response%d" % index
		TownStyle.style_button(button, TownStyle.BODY)
		button.disabled = not response.is_allowed
		button.pressed.connect(choose.bind(index))
		_responses.add_child(button)
		index += 1
	_responses.visible = false if typing() else not line.responses.is_empty()
	_more.text = "" if not line.responses.is_empty() else "Click or press A to go on"
	if not typing():
		_focus_response()


func _type_in() -> void:
	if _typing != null:
		_typing.kill()
		_typing = null
	_text.visible_ratio = 1.0
	var length: int = _text.get_total_character_count()
	if Settings.reduce_motion or length == 0 or not is_inside_tree():
		return
	_text.visible_ratio = 0.0
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, length / CHARS_PER_SECOND)
	_typing.finished.connect(_finish_typing)


func typing() -> bool:
	return _typing != null and _typing.is_running()


func _finish_typing() -> void:
	if _typing != null:
		_typing.kill()
		_typing = null
	_text.visible_ratio = 1.0
	_responses.visible = runner != null and runner.line != null and not runner.line.responses.is_empty()
	_focus_response()


func _focus_response() -> void:
	if not _responses.visible:
		return
	for button: Node in _responses.get_children():
		if not (button as Button).disabled and not button.is_queued_for_deletion():
			(button as Button).grab_focus()
			return


## A press on a plain line: finish typing, else move on.
func go_on() -> void:
	if stage == "result" or stage == "refused":
		return
	if typing():
		_finish_typing()
		return
	if runner.busy or runner.line == null or not runner.line.responses.is_empty():
		return
	await runner.advance()
	_show_line()


## Picks response `index` of the line on screen.
func choose(index: int) -> void:
	if typing() or runner.busy or runner.line == null or runner.line.responses.is_empty():
		return
	await runner.advance(index)
	_show_line()


## Leaves without finishing: nothing is spent or kept. Not after the end.
func leave() -> void:
	if stage != "playing":
		return
	stage = "left"
	closed.emit(false)
	queue_free()


func _on_script_end() -> void:
	if stage == "invite":
		_show_result()
		return
	var before: bool = Affection.scene_unlocked(Game.data, session.start_affection)
	refusals = Game.finish_date(session)
	if not refusals.is_empty():
		stage = "refused"
		_show_result()
		return
	scene_reached = not before and Affection.scene_unlocked(Game.data, Game.state.affection(session.villager))
	var resource: DialogueResource = runner.resource
	if scene_reached and resource.cues.has(DateSession.INVITE):
		stage = "invite"
		_leave.visible = false
		await runner.start(DateSession.INVITE)
		_show_line()
		return
	_show_result()


## The card at the end: what the date added and what's next (RD-5).
func _show_result() -> void:
	if stage != "refused":
		stage = "result"
	_leave.visible = false
	_name_plate.visible = true
	_name_plate.add_theme_color_override("font_color", TownStyle.INK)
	_more.text = ""
	for old: Node in _responses.get_children():
		old.queue_free()
	var lines: PackedStringArray = result_lines(Game.data, Game.state, session, refusals, scene_reached)
	_name_plate.text = lines[0]
	_text.text = "\n".join(lines.slice(1))
	_text.visible_ratio = 1.0
	var back: Button = Button.new()
	back.text = "Back to town"
	back.name = "BackToTown"
	TownStyle.style_button(back, TownStyle.BODY)
	back.pressed.connect(_close_after_result)
	_responses.add_child(back)
	_responses.visible = true
	back.grab_focus.call_deferred()


## The result card's title and lines.
static func result_lines(data: GameData, state: GameState, date: DateSession, refused: Array[Dictionary],
		reached_scene: bool) -> PackedStringArray:
	if not refused.is_empty():
		var reasons: PackedStringArray = ["The date couldn't count"]
		for refusal: Dictionary in refused:
			reasons.append(str(refusal["text"]))
		return reasons
	var role: String = str(data.row("villagers", date.villager).get("role", date.villager))
	var points: int = state.affection(date.villager)
	var out: PackedStringArray = ["Date over", "Affection with the %s +%d (now %d)" % [role, date.kept, points]]
	var reached: Dictionary = Affection.reached(data, points)
	if not reached.is_empty():
		out.append("%s" % reached["name"])
	if reached_scene:
		out.append("A private moment is unlocked")
	var next: Dictionary = Affection.next(data, points)
	if not next.is_empty():
		var unlocks: String = " · " + str(next["text"]).to_lower() if not str(next["text"]).is_empty() else ""
		out.append("Next: %s at %d%s" % [next["name"], next["points"], unlocks])
	return out


func _on_settings_changed() -> void:
	if session != null and not session.finished:
		session.content_level = Settings.effective_content_level()


func _close_after_result() -> void:
	closed.emit(stage == "result")
	queue_free()


func _on_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		go_on()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()
	elif event.is_action_pressed("ui_accept") and (runner == null or runner.line == null or runner.line.responses.is_empty()):
		get_viewport().set_input_as_handled()
		go_on()
