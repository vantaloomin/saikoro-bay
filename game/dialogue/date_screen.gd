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
##
## From Mara's date-flow review: answers can't be picked unread (they fade
## in, nothing is focused until a direction press, and keys and the pad
## wait ANSWER_GUARD_MS after they appear; a mouse click works at once);
## answers are left-aligned and numbered, and 1-9 pick them; narration is
## italic and muted; the text column holds about 60 characters, on the
## left, with the portrait on the right; the result shows the card's bead
## meter filling and the milestone change.

signal closed(kept: bool)

const SPOT_COLORS: Dictionary[String, Color] = {
	"cafe": Color(0.91, 0.84, 0.72),
	"hot_spring": Color(0.74, 0.85, 0.84),
}
const CHARS_PER_SECOND: float = 60.0
## The text column: about 60 characters of the title size (Mara).
const BOX_WIDTH: float = 1080.0
const MARGIN: float = 96.0
## The delve's result guard: keys and the pad can't pick an answer this
## soon after the answers appear.
const ANSWER_GUARD_MS: int = 400
const ANSWER_FADE: float = 0.4
## The "go on" hint fades after this many lines.
const HINT_LINES: int = 3

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
var _meter: AffectionMeter
var _answers_shown_at: int = 0
var _lines_shown: int = 0
## Whether a controller was the last input, for the hint's words.
var using_pad: bool = false
## Whether the last press was the mouse's, which skips the answer guard.
var _mouse_last: bool = false


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
	# Portrait right, text left, never over the face (art direction Frame 1).
	_portrait.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_portrait.offset_left = -MARGIN - 560.0
	_portrait.offset_right = -MARGIN
	_portrait.offset_top = -900.0
	_portrait.offset_bottom = 0.0
	add_child(_portrait)
	_box = PanelContainer.new()
	_box.name = "Box"
	_box.add_theme_stylebox_override("panel", TownStyle.panel())
	_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_box.custom_minimum_size = Vector2(BOX_WIDTH, 260)
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.position = Vector2(MARGIN, -60 - 260)
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
	# The town's type has no italic, so narration leans the regular face.
	var lean: FontVariation = FontVariation.new()
	lean.base_font = TownStyle.theme().default_font
	lean.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	_text.add_theme_font_override("italics_font", lean)
	stack.add_child(_text)
	_meter = AffectionMeter.new()
	_meter.name = "Meter"
	_meter.visible = false
	stack.add_child(_meter)
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
	return "" if id.is_empty() else data.villager_name(id)


## True once the player has left: an advance still awaiting when Leave was
## pressed must not show a line or keep the date (Imogen's PR 2 audit).
func _gone() -> bool:
	return stage == "left" or is_queued_for_deletion()


func _show_line() -> void:
	if _gone():
		return
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
	var narration: bool = line.character.is_empty()
	_text.add_theme_color_override("default_color", TownStyle.DIM if narration else TownStyle.INK)
	_text.text = "[i]%s[/i]" % line.text if narration else line.text
	_type_in()
	var index: int = 0
	for response: DialogueResponse in line.responses:
		var button: Button = Button.new()
		button.text = "%d   %s" % [index + 1, response.text]
		button.name = "Response%d" % index
		TownStyle.style_button(button, TownStyle.BODY)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not response.is_allowed
		button.pressed.connect(_on_answer_pressed.bind(index))
		_responses.add_child(button)
		index += 1
	_lines_shown += 1
	_more.text = "" if not line.responses.is_empty() or _lines_shown > HINT_LINES else go_on_hint(using_pad)
	if not typing():
		_reveal_answers()


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
	_reveal_answers()


## Shows the line's answers, if any: faded in, nothing focused, and the
## guard started (Mara's blocker 1).
func _reveal_answers() -> void:
	var has_answers: bool = runner != null and runner.line != null and not runner.line.responses.is_empty()
	_responses.visible = has_answers
	if not has_answers:
		return
	_answers_shown_at = Time.get_ticks_msec()
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null:
		focused.release_focus()
	if not Settings.reduce_motion and is_inside_tree():
		_responses.modulate.a = 0.0
		create_tween().tween_property(_responses, "modulate:a", 1.0, ANSWER_FADE)


## Whether keys and the pad may pick an answer yet.
func answers_ready() -> bool:
	return _responses.visible and Time.get_ticks_msec() >= _answers_shown_at + ANSWER_GUARD_MS


## The "go on" hint, in the words of the last input (Mara's polish 13).
static func go_on_hint(pad: bool) -> String:
	return "Press A to go on" if pad else "Click or press Enter to go on"


func _on_answer_pressed(index: int) -> void:
	# A mouse click works at once; a key or pad press on a focused answer
	# waits out the guard.
	if not _mouse_last and not answers_ready():
		return
	choose(index)


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
	if _gone():
		return
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
		_fade_leave()
		await runner.start(DateSession.INVITE)
		_show_line()
		return
	_show_result()


## The card at the end: what the date added and what's next (RD-5).
func _show_result() -> void:
	if stage != "refused":
		stage = "result"
	_fade_leave()
	_name_plate.visible = true
	_name_plate.add_theme_color_override("font_color", TownStyle.INK)
	_more.text = ""
	for old: Node in _responses.get_children():
		old.queue_free()
	var lines: PackedStringArray = result_lines(Game.data, Game.state, session, refusals, scene_reached)
	_name_plate.text = lines[0]
	_text.add_theme_color_override("default_color", TownStyle.INK)
	_text.text = "\n".join(lines.slice(1))
	_text.visible_ratio = 1.0
	if stage == "result":
		# The card's own meter, filling as the date lands.
		_meter.visible = true
		_meter.get_parent().move_child(_meter, _text.get_index())
		_meter.show_points(Game.data, Game.state.affection(session.villager), session.start_affection)
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
	var points: int = state.affection(date.villager)
	var before: Dictionary = Affection.reached(data, date.start_affection)
	var now: Dictionary = Affection.reached(data, points)
	var out: PackedStringArray = ["Date with %s" % speaker_name(data, date.villager)]
	# One model with the card (Mara's blocker 2): the meter, then the
	# milestone as a change, never a bare word that reads as a button.
	var was: String = str(before.get("name", "Getting to know you"))
	if now.get("id", "") != before.get("id", ""):
		out.append("%s → %s" % [was, now["name"]])
	else:
		out.append("Affection +%d · still %s" % [date.kept, was])
	if reached_scene:
		out.append("A private moment is unlocked")
	var next: Dictionary = Affection.next(data, points)
	if not next.is_empty():
		var unlocks: String = " · " + str(next["text"]) if not str(next["text"]).is_empty() else ""
		out.append("Next: %s%s" % [next["name"], unlocks])
	elif not now.is_empty():
		out.append(TownScreen.TOP_MILESTONE)
	var actions: int = int(GameState.date_row(data, date.villager).get("actions", 0))
	if actions > 0:
		out.append("%d %s spent" % [actions, "action" if actions == 1 else "actions"])
	return out


func _fade_leave() -> void:
	if not _leave.visible:
		return
	_leave.disabled = true
	if Settings.reduce_motion or not is_inside_tree():
		_leave.visible = false
		return
	var tween: Tween = create_tween()
	tween.tween_property(_leave, "modulate:a", 0.0, 0.25)
	tween.tween_callback(_leave.hide)


func _on_settings_changed() -> void:
	if session != null and not session.finished:
		session.follow_content_level(Settings.effective_content_level())


func _close_after_result() -> void:
	closed.emit(stage == "result")
	queue_free()


func _on_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		go_on()


func _input(event: InputEvent) -> void:
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if pad and (event as InputEventJoypadMotion == null or absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		using_pad = true
	elif event is InputEventMouseButton or event is InputEventKey:
		using_pad = false
	if event is InputEventMouseButton:
		_mouse_last = true
	elif event is InputEventKey or pad:
		_mouse_last = false


func _unhandled_input(event: InputEvent) -> void:
	var answering: bool = runner != null and runner.line != null and not runner.line.responses.is_empty() \
		and stage in ["playing", "invite"]
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()
	elif answering and _responses.visible and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
		# Nothing is focused until the first direction press (Mara's blocker 1).
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused == null or not _responses.is_ancestor_of(focused):
			get_viewport().set_input_as_handled()
			_focus_response()
	elif answering and event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		var number: int = (event as InputEventKey).keycode - KEY_1
		if number >= 0 and number < runner.line.responses.size() and answers_ready():
			get_viewport().set_input_as_handled()
			choose(number)
	elif event.is_action_pressed("ui_accept") and not answering:
		get_viewport().set_input_as_handled()
		go_on()
