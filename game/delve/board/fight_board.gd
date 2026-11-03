class_name FightBoard
extends Control
## The greybox dice board (M1): one Fight, played with mouse, keyboard or
## controller. It only calls the fight's moves and animates only from the
## fight's events, so what you see is what the sim did.
##
## Inputs (two-halves section 3):
##   click a die, then a slot (or A on each)   place
##   right-click / B on a slot or placed die     take back
##   X or the "+1" button with a die selected    Nudge
##   R or Reroll, pick the discard, confirm      reroll (two steps)
##   Y, Space or End turn                        commit (hover shows the result)
## Clicking or pressing A during resolution fast-forwards it.

signal again_requested
signal leave_requested

const COMMIT_ACTION: StringName = &"board_commit"
const CONTEXT_ACTION: StringName = &"board_context"
const REROLL_ACTION: StringName = &"board_reroll"


## The enemy's intent: icon plus number, always. This turn large, next turn
## small and dimmed.
class IntentView:
	extends Control
	var current: Dictionary = {}
	var next: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(420, 150)

	func _draw() -> void:
		var font: Font = get_theme_default_font()
		var x: float = 0
		for kind: String in ["attack", "guard"]:
			if current.has(kind):
				BoardStyle.draw_intent_glyph(self, Rect2(x, 10, 72, 72), kind, BoardStyle.INK)
				draw_string(font, Vector2(x + 80, 70), str(current[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BIG, BoardStyle.INK)
				x += 190
		draw_string(font, Vector2(0, 128), "next", HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.SMALL, BoardStyle.DIM)
		x = 60
		for kind: String in ["attack", "guard"]:
			if next.has(kind):
				BoardStyle.draw_intent_glyph(self, Rect2(x, 104, 32, 32), kind, BoardStyle.DIM)
				draw_string(font, Vector2(x + 36, 130), str(next[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY, BoardStyle.DIM)
				x += 90


var fight: Fight
var data: GameData

var _selected: int = -1
var _reroll_mode: bool = false
var _reroll_discard: int = -1
var _busy: bool = false
var _skip: bool = false
var _selected_at_ms: int = 0

var _shown_enemy_hp: int = 0
var _shown_enemy_block: int = 0
var _shown_player_hp: int = 0
var _shown_player_block: int = 0
var _mend_badge: String = ""

var _enemy_name: Label
var _enemy_hp: Label
var _enemy_bar: ProgressBar
var _enemy_block: Label
var _intent: IntentView
var _twist: Label
var _message: Label
var _badge: Label
var _slot_cards: Dictionary[String, SlotCard] = {}
var _dice: Array[DieView] = []
var _player_hp: Label
var _player_bar: ProgressBar
var _player_block: Label
var _end_turn: Button
var _end_preview: Label
var _reroll: Button
var _nudge: Button
var _results: PanelContainer
var _results_text: Label
var _again: Button


## Builds the board for `new_fight`. Call before adding it to the tree.
func setup(new_fight: Fight, game_data: GameData) -> void:
	fight = new_fight
	data = game_data


func _ready() -> void:
	_ensure_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_all()
	if not _dice.is_empty():
		_dice[0].grab_focus()


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if fight == null or fight.state != Fight.State.PLAYER_TURN:
		return
	if _busy:
		if event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
			_skip = true
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(COMMIT_ACTION):
		_on_end_turn()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CONTEXT_ACTION):
		_on_nudge()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(REROLL_ACTION):
		_on_reroll()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _on_die_pressed(die_id: int) -> void:
	if _busy or fight.state != Fight.State.PLAYER_TURN:
		return
	var d: Fight.Die = fight.die(die_id)
	if _reroll_mode:
		var reason: String = fight.reroll_refusal(die_id)
		if not reason.is_empty():
			_say(reason, true)
			return
		_reroll_discard = die_id
		_refresh_all()
		return
	if not d.slot_id.is_empty():
		_take_back(die_id)
		return
	if d.locked:
		_say("House lock: this die is locked this turn.", true)
		return
	_selected = -1 if _selected == die_id else die_id
	_selected_at_ms = Time.get_ticks_msec()
	_refresh_all()


func _on_slot_pressed(slot_id: String) -> void:
	if _busy or fight.state != Fight.State.PLAYER_TURN:
		return
	if _selected < 0:
		_say("Pick a die first.", false)
		return
	var reason: String = fight.place_refusal(_selected, slot_id)
	if not reason.is_empty():
		PlaytestLog.log_event("invalid_drop", {"die": _selected, "value": fight.die(_selected).value, "slot": slot_id})
		_say(reason, true)
		_pulse(_slot_cards[slot_id])
		return
	PlaytestLog.log_event("place", {"die": _selected, "slot": slot_id, "hover_ms": Time.get_ticks_msec() - _selected_at_ms})
	fight.place(_selected, slot_id)
	_selected = -1
	_say("", false)
	_refresh_all()
	_focus_first_free_die()


func _on_slot_secondary(slot_id: String) -> void:
	var s: Fight.Slot = fight.slot(slot_id)
	if _busy or s == null or s.dice.is_empty():
		_cancel()
		return
	_take_back(s.dice[s.dice.size() - 1])


func _take_back(die_id: int) -> void:
	if fight.take_back(die_id):
		PlaytestLog.log_event("take_back", {"die": die_id, "turn": fight.turn})
		_refresh_all()


func _on_nudge() -> void:
	if _busy or not fight.has_perk(Fight.NUDGE_PERK):
		return
	var target: int = _selected
	if target < 0:
		var focused: DieView = get_viewport().gui_get_focus_owner() as DieView
		target = focused.die_id if focused != null else -1
	if target < 0:
		_say("Pick a die to nudge.", false)
		return
	if not fight.nudge(target):
		_say("Nudge: once a turn, on an unplaced die below 6.", true)
		return
	_refresh_all()
	_flash_latest_perk()


func _on_reroll() -> void:
	if _busy:
		return
	if not _reroll_mode:
		if fight.rerolls_left <= 0:
			_say("No rerolls left this turn.", true)
			return
		_reroll_mode = true
		_reroll_discard = -1
		_selected = -1
		_say("Pick a die to discard. B cancels.", false)
		_refresh_all()
		return
	if _reroll_discard < 0:
		_say("Pick a die to discard first.", false)
		return
	fight.reroll(_reroll_discard)
	_reroll_mode = false
	_reroll_discard = -1
	_say("", false)
	_refresh_all()


func _cancel() -> void:
	_selected = -1
	_reroll_mode = false
	_reroll_discard = -1
	_say("", false)
	_refresh_all()


func _on_end_turn() -> void:
	if _busy or fight.state != Fight.State.PLAYER_TURN:
		return
	_cancel()
	var start: int = fight.events.size()
	fight.end_turn()
	await _play(fight.events.slice(start))
	_refresh_all()
	if fight.state != Fight.State.PLAYER_TURN:
		_show_results()


# --- Resolution playback ------------------------------------------------------

## Steps through a turn's events at about 150 ms each. Reduce motion or a
## fast-forward makes it instant. The next turn's roll ends the playback.
func _play(turn_events: Array[Dictionary]) -> void:
	_busy = true
	_skip = Settings.reduce_motion
	_end_turn.disabled = true
	for event: Dictionary in turn_events:
		if event["type"] == "turn_start":
			break
		_apply_event(event)
		_refresh_numbers()
		if not _skip:
			await get_tree().create_timer(BoardStyle.STEP_SECONDS).timeout
	_busy = false
	_end_turn.disabled = false


func _apply_event(event: Dictionary) -> void:
	match event["type"] as String:
		"damage":
			if event["target"] == "enemy":
				_shown_enemy_block = maxi(0, _shown_enemy_block - (event["blocked"] as int))
				_shown_enemy_hp = maxi(0, _shown_enemy_hp - (event["amount"] as int))
			else:
				_shown_player_block = maxi(0, _shown_player_block - (event["blocked"] as int))
				_shown_player_hp = maxi(0, _shown_player_hp - (event["amount"] as int))
		"block":
			if event["target"] == "player":
				_shown_player_block += event["amount"] as int
		"heal":
			_shown_player_hp += event["amount"] as int
		"perk":
			if event["perk"] == Fight.MEND_PERK:
				_mend_badge = "%s · +%d HP" % [_source_name(str(event["source"])), event["amount"]]
			_show_badge(event)


func _flash_latest_perk() -> void:
	for i: int in range(fight.events.size() - 1, -1, -1):
		if fight.events[i]["type"] == "perk":
			_show_badge(fight.events[i])
			return


## Perk source badge (KP-2): who did it, and what.
func _show_badge(event: Dictionary) -> void:
	var what: String = ""
	match event["perk"] as String:
		Fight.NUDGE_PERK:
			what = "+%d" % event["amount"]
		Fight.BRACE_PERK:
			what = "+%d block" % event["amount"]
		Fight.MEND_PERK:
			what = "+%d HP" % event["amount"]
	_badge.text = "%s · %s" % [_source_name(str(event["source"])), what]
	_badge.visible = true


func _source_name(source: String) -> String:
	if data != null and data.has_row("villagers", source):
		return str(data.row("villagers", source)["role"])
	return source.capitalize()


# --- Drawing state ------------------------------------------------------------

func _refresh_all() -> void:
	_shown_enemy_hp = fight.enemy_hp
	_shown_enemy_block = fight.enemy_block
	_shown_player_hp = fight.player_hp
	_shown_player_block = fight.player_block
	_refresh_numbers()
	_intent.current = fight.current_intent()
	_intent.next = fight.next_intent()
	_intent.queue_redraw()

	for view: DieView in _dice:
		var d: Fight.Die = fight.die(view.die_id)
		view.value = d.value
		view.locked = d.locked
		view.discarded = d.discarded
		view.selected = view.die_id == _selected or view.die_id == _reroll_discard
		view.placed = not d.slot_id.is_empty()
		view.bite_marker = fight.twist == "snake_eyes" and d.value == 1 and d.is_free()

	for s: Fight.Slot in fight.slots:
		var card: SlotCard = _slot_cards[s.id]
		card.placed_values.clear()
		for placed: int in s.dice:
			card.placed_values.append(fight.die(placed).value)
		_set_preview(card, s)
		card.queue_redraw()

	_reroll.visible = true
	_reroll.disabled = fight.rerolls_left <= 0 and not _reroll_mode
	if _reroll_mode:
		var others: int = 0
		for d: Fight.Die in fight.hand:
			if d.is_free() and not d.locked and d.id != _reroll_discard:
				others += 1
		_reroll.text = "Confirm: discard %d, reroll %d" % [fight.die(_reroll_discard).value, others] if _reroll_discard >= 0 else "Pick a die to discard"
	else:
		_reroll.text = "Reroll (%d left)" % fight.rerolls_left
	_nudge.visible = fight.has_perk(Fight.NUDGE_PERK)
	_nudge.disabled = fight.nudges_left <= 0
	_nudge.text = "Nudge +1" if fight.nudges_left > 0 else "Nudge (used)"
	_end_preview.text = end_turn_summary()


func _refresh_numbers() -> void:
	_enemy_name.text = fight.enemy_name
	_enemy_bar.max_value = fight.enemy_max_hp
	_enemy_bar.value = _shown_enemy_hp
	_enemy_hp.text = "HP %d / %d" % [_shown_enemy_hp, fight.enemy_max_hp]
	_enemy_block.text = "Guard %d" % _shown_enemy_block if _shown_enemy_block > 0 else ""
	_player_bar.max_value = fight.player_max_hp
	_player_bar.value = _shown_player_hp
	_player_hp.text = "HP %d / %d" % [_shown_player_hp, fight.player_max_hp]
	_player_block.text = "Block %d" % _shown_player_block


func _set_preview(card: SlotCard, s: Fight.Slot) -> void:
	card.preview_text = ""
	card.preview_ok = true
	if s.is_complete():
		card.preview_text = _effect_text(s.row["effect"] as String, fight.slot_amount(s), -1)
		return
	if s.dice.size() > 0 and _selected < 0:
		card.preview_text = "Waiting for another %d" % fight.die(s.dice[0]).value
		return
	if _selected < 0:
		return
	var p: Dictionary = fight.preview(_selected, s.id)
	if not p["ok"]:
		card.preview_text = p["reason"]
		card.preview_ok = false
	elif not p["complete"] and not p["can_complete"]:
		card.preview_text = "Needs another %d" % fight.die(_selected).value
		card.preview_ok = false
	elif not p["complete"]:
		card.preview_text = "%s with another %d" % [_effect_text(p["effect"] as String, p["amount"] as int, p["blocked"] as int), fight.die(_selected).value]
	else:
		card.preview_text = _effect_text(p["effect"] as String, p["amount"] as int, p["blocked"] as int)


func _effect_text(effect: String, amount: int, blocked: int) -> String:
	match effect:
		"damage":
			if blocked > 0:
				return "%d damage (%d into guard)" % [amount, blocked]
			return "%d damage" % amount
		"block":
			return "Block %d" % amount
		"heal":
			return "Heal %d" % amount
	return ""


## The End turn preview line (Mara 2), built from the real pipeline's
## events on a copy, e.g. "You deal 9 (4 into guard) · Block 5 · Hits 8, you take 3".
func end_turn_summary() -> String:
	var preview: Dictionary = fight.preview_end_turn()
	var dealt: int = 0
	var into_guard: int = 0
	var block: int = 0
	var bites: int = 0
	var hit: int = 0
	var taken: int = 0
	for event: Dictionary in preview["events"] as Array[Dictionary]:
		match event["type"] as String:
			"damage":
				if event["target"] == "enemy":
					dealt += (event["amount"] as int) + (event["blocked"] as int)
					into_guard += event["blocked"] as int
				elif event["source"] == "enemy":
					hit = (event["amount"] as int) + (event["blocked"] as int)
					taken = event["amount"] as int
				else:
					bites += event["amount"] as int
			"block":
				if event["target"] == "player":
					block += event["amount"] as int
	var parts: PackedStringArray = []
	parts.append("You deal %d (%d into guard)" % [dealt, into_guard] if into_guard > 0 else "You deal %d" % dealt)
	if block > 0:
		parts.append("Block %d" % block)
	if bites > 0:
		parts.append("Snake eyes %d" % bites)
	match preview["state"] as Fight.State:
		Fight.State.WON:
			parts.append("Wins the fight")
		Fight.State.LOST:
			parts.append("You go down")
		_:
			parts.append("Hits %d, you take %d" % [hit, taken])
	for s: Fight.Slot in fight.slots:
		if s.needed() > 1 and not s.dice.is_empty() and not s.is_complete():
			parts.append("%s: incomplete" % s.row["name"])
	return " · ".join(parts)


func _say(text: String, is_error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", BoardStyle.DANGER if is_error else BoardStyle.INK)


func _pulse(card: SlotCard) -> void:
	card.pulsing = true
	card.queue_redraw()
	await get_tree().create_timer(0.3 if not Settings.reduce_motion else 0.15).timeout
	card.pulsing = false
	card.queue_redraw()


func _focus_first_free_die() -> void:
	for view: DieView in _dice:
		if not view.placed and not view.discarded:
			view.grab_focus()
			return
	_end_turn.grab_focus()


func _show_results() -> void:
	var won: bool = fight.state == Fight.State.WON
	var lines: PackedStringArray = []
	lines.append("You beat the %s in %d turns." % [fight.enemy_name, fight.turn] if won else "The %s cleaned you out." % fight.enemy_name)
	lines.append("HP %d / %d" % [fight.player_hp, fight.player_max_hp])
	if not _mend_badge.is_empty():
		lines.append(_mend_badge)
	_results_text.text = "\n".join(lines)
	_results.visible = true
	_again.grab_focus()


# --- Layout -------------------------------------------------------------------

func _build() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = BoardStyle.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)

	# Enemy across the felt.
	var enemy_row: HBoxContainer = HBoxContainer.new()
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.add_theme_constant_override("separation", 48)
	column.add_child(enemy_row)
	var enemy_panel: PanelContainer = PanelContainer.new()
	enemy_panel.add_theme_stylebox_override("panel", BoardStyle.panel())
	enemy_panel.custom_minimum_size = Vector2(620, 0)
	enemy_row.add_child(enemy_panel)
	var enemy_box: VBoxContainer = VBoxContainer.new()
	enemy_panel.add_child(enemy_box)
	_enemy_name = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.GOLD)
	enemy_box.add_child(_enemy_name)
	_enemy_bar = _bar(BoardStyle.DANGER)
	enemy_box.add_child(_enemy_bar)
	var enemy_numbers: HBoxContainer = HBoxContainer.new()
	enemy_numbers.add_theme_constant_override("separation", 32)
	enemy_box.add_child(enemy_numbers)
	_enemy_hp = BoardStyle.label("", BoardStyle.BODY)
	enemy_numbers.add_child(_enemy_hp)
	_enemy_block = BoardStyle.label("", BoardStyle.BODY, BoardStyle.JADE)
	enemy_numbers.add_child(_enemy_block)
	_twist = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	_twist.autowrap_mode = TextServer.AUTOWRAP_WORD
	_twist.custom_minimum_size = Vector2(580, 0)
	enemy_box.add_child(_twist)
	var enemy_row_data: Dictionary = data.row("enemies", fight.enemy_id) if data != null else {}
	_twist.text = str(enemy_row_data.get("twist_text", ""))
	_intent = IntentView.new()
	enemy_row.add_child(_intent)

	_message = BoardStyle.label("", BoardStyle.BODY)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(0, 36)
	column.add_child(_message)

	# Slots in the middle, numbered in resolution order.
	var slot_row: HBoxContainer = HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 24)
	column.add_child(slot_row)
	var order: int = 1
	for s: Fight.Slot in fight.slots:
		var card: SlotCard = SlotCard.new()
		card.slot_id = s.id
		card.order = order
		card.title = str(s.row["name"])
		card.rule_text = str(s.row["text"])
		card.sockets = s.needed()
		card.is_pair = s.row["accepts"] == "pair"
		for face: int in 6:
			card.accepted[face] = _accepts_face(s.row, face + 1)
		card.pressed.connect(_on_slot_pressed.bind(s.id))
		card.secondary_pressed.connect(_on_slot_secondary.bind(s.id))
		slot_row.add_child(card)
		_slot_cards[s.id] = card
		order += 1

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	# Your side: HP on the left, the hand in the middle, the verbs on the right.
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 40)
	column.add_child(bottom)
	var player_panel: PanelContainer = PanelContainer.new()
	player_panel.add_theme_stylebox_override("panel", BoardStyle.panel(BoardStyle.JADE))
	player_panel.custom_minimum_size = Vector2(360, 0)
	bottom.add_child(player_panel)
	var player_box: VBoxContainer = VBoxContainer.new()
	player_panel.add_child(player_box)
	player_box.add_child(BoardStyle.label("You", BoardStyle.BODY, BoardStyle.JADE))
	_player_bar = _bar(BoardStyle.JADE)
	player_box.add_child(_player_bar)
	_player_hp = BoardStyle.label("", BoardStyle.BODY)
	player_box.add_child(_player_hp)
	_player_block = BoardStyle.label("", BoardStyle.BODY, BoardStyle.JADE)
	player_box.add_child(_player_block)
	_badge = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.GOLD)
	_badge.visible = false
	player_box.add_child(_badge)

	var hand: HBoxContainer = HBoxContainer.new()
	hand.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.add_theme_constant_override("separation", 20)
	bottom.add_child(hand)
	for d: Fight.Die in fight.hand:
		var view: DieView = DieView.new()
		view.die_id = d.id
		view.custom_minimum_size = Vector2(120, 120)
		view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		view.pressed.connect(_on_die_pressed.bind(d.id))
		view.secondary_pressed.connect(_cancel)
		hand.add_child(view)
		_dice.append(view)

	var verbs: VBoxContainer = VBoxContainer.new()
	verbs.custom_minimum_size = Vector2(520, 0)
	verbs.add_theme_constant_override("separation", 12)
	bottom.add_child(verbs)
	_end_preview = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.INK)
	_end_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	verbs.add_child(_end_preview)
	var verb_row: HBoxContainer = HBoxContainer.new()
	verb_row.add_theme_constant_override("separation", 12)
	verbs.add_child(verb_row)
	_nudge = _button("Nudge +1", 0)
	_nudge.pressed.connect(_on_nudge)
	verb_row.add_child(_nudge)
	_reroll = _button("Reroll", 0)
	_reroll.pressed.connect(_on_reroll)
	verb_row.add_child(_reroll)
	_end_turn = _button("End turn", 80)
	_end_turn.pressed.connect(_on_end_turn)
	verbs.add_child(_end_turn)

	# Results, over the table.
	_results = PanelContainer.new()
	_results.add_theme_stylebox_override("panel", BoardStyle.panel())
	_results.visible = false
	add_child(_results)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.custom_minimum_size = Vector2(720, 320)
	_results.position = Vector2(600, 380)
	var results_box: VBoxContainer = VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 20)
	_results.add_child(results_box)
	_results_text = BoardStyle.label("", BoardStyle.NUMBER)
	results_box.add_child(_results_text)
	_again = _button("Fight again", 72)
	_again.pressed.connect(again_requested.emit)
	results_box.add_child(_again)
	var leave: Button = _button("Return to town", 64)
	leave.pressed.connect(leave_requested.emit)
	results_box.add_child(leave)


static func _accepts_face(row: Dictionary, face: int) -> bool:
	match row["accepts"] as String:
		"range":
			return face >= (row["min"] as int) and face <= (row["max"] as int)
		"even":
			return face % 2 == 0
		"odd":
			return face % 2 == 1
		"exact":
			return face == (row["min"] as int)
	return true


func _bar(color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 24)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	var back: StyleBoxFlat = StyleBoxFlat.new()
	back.bg_color = BoardStyle.FELT
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _button(text: String, height: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", BoardStyle.BODY)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if height > 0:
		b.custom_minimum_size = Vector2(0, height)
	else:
		b.custom_minimum_size = Vector2(0, 56)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD if state != "disabled" else BoardStyle.DIM)
		box.set_content_margin_all(8)
		if state == "hover" or state == "pressed":
			box.bg_color = BoardStyle.FELT
		b.add_theme_stylebox_override(state, box)
	var focus: StyleBoxFlat = BoardStyle.panel(BoardStyle.INK, Color(0, 0, 0, 0))
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", BoardStyle.INK)
	return b


static func _ensure_actions() -> void:
	var bindings: Dictionary[StringName, Array] = {
		COMMIT_ACTION: [KEY_SPACE, JOY_BUTTON_Y],
		CONTEXT_ACTION: [KEY_X, JOY_BUTTON_X],
		REROLL_ACTION: [KEY_R],
	}
	for action: StringName in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var keys: Array = bindings[action]
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = keys[0] as Key
		InputMap.action_add_event(action, key)
		if keys.size() > 1:
			var pad: InputEventJoypadButton = InputEventJoypadButton.new()
			pad.button_index = keys[1] as JoyButton
			InputMap.action_add_event(action, pad)
