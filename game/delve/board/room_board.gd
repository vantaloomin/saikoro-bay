class_name RoomBoard
extends Control
## The board for a treasure, rest or rescue room (DiceRoom; specs/delve-map.md
## section 3 and 8, Mara's map review #7 and #9). Same dice, same moves and
## the same inputs as the fight board; what changes is the table and what
## the big button does:
##   treasure  three locks, one roll and a reroll; "Open" previews the loot
##   rest      one Soak slot; "Soak" previews the heal and any heal wasted
##             at max HP
##   rescue    the cage's three locks over 3 turns, the tide rising; "End
##             turn" previews the locks it opens and "Lose 2 · tide". A lock
##             that opens stays open and its dice come back to the hand.
## It only calls the room's moves and reads the room's state, so what you
## see is what the sim did. Continue (after the room ends) emits finished.

signal finished

const RESULT_GUARD_MS: int = 400
const VERBS: Dictionary[String, String] = {"treasure": "Open", "rest": "Soak", "rescue": "End turn"}
const INTROS: Dictionary[String, String] = {
	"treasure": "One roll, one reroll. Fill any locks you can, then open them.",
	"rest": "One roll. Up to two dice in the water heal you by their total.",
	"rescue": "Open all three locks before the tide comes in. An open lock stays open, and its dice come back.",
}


## The cage with the tide rising (Mara #7): water climbs a third of the
## cage each turn, so the clock reads without numbers.
class TideView:
	extends Control
	var turn: int = 1
	var turns: int = 3
	var open: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(150, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2(10, 10), size - Vector2(20, 20))
		var level: float = clampf(float(turn - 1) / float(maxi(turns, 1)), 0.0, 1.0)
		var water: Rect2 = Rect2(r.position.x, r.end.y - r.size.y * level, r.size.x, r.size.y * level)
		draw_rect(r, BoardStyle.FELT)
		if level > 0.0:
			draw_rect(water, Color(BoardStyle.JADE, 0.55))
			# A wavy top edge, so the water reads as water in greyscale.
			var pts: PackedVector2Array = []
			for i: int in 13:
				var x: float = r.position.x + r.size.x * i / 12.0
				pts.append(Vector2(x, water.position.y + sin(i * 1.3) * 4.0))
			draw_polyline(pts, BoardStyle.INK, 3.0)
		MapGlyphs.draw_glyph(self, r.grow(-18), DelveMap.RESCUE, BoardStyle.INK)
		if not open:
			for k: int in 5:
				var x: float = r.position.x + r.size.x * (k + 0.5) / 5.0
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), BoardStyle.GOLD, 4.0)
		draw_rect(r, BoardStyle.GOLD, false, 3.0)


var room: DiceRoom
var data: GameData
## The caged villager's id (rescue rooms), for the copy.
var villager: String = ""
## Room left free above the board for the haul strip.
var top_inset: int = 0

var _selected: int = -1
var _reroll_mode: bool = false
var _reroll_discard: int = -1
var _busy: bool = false

var _title: Label
var _intro: Label
var _turns: Label
var _tide: TideView
var _message: Label
var _last_turn: Label
var _slot_cards: Dictionary[String, SlotCard] = {}
var _dice: Array[DieView] = []
var _hp: Label
var _hp_bar: HpBar
var _end_preview: Label
var _end_detail: Label
var _nudge: Button
var _nudge_chip: FaceChip
var _reroll: Button
var _verb: Button
var _results: PanelContainer
var _results_text: Label
var _continue: Button
var _sounds: BoardSounds
var _results_shown_at: int = 0


func setup(new_room: DiceRoom, game_data: GameData, caged: String = "") -> void:
	room = new_room
	data = game_data
	villager = caged


func _ready() -> void:
	FightBoard._ensure_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BoardStyle.theme()
	_sounds = BoardSounds.new()
	add_child(_sounds)
	_build()
	_refresh()
	if not _dice.is_empty():
		_dice[0].grab_focus()


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if room == null or room.state != DiceRoom.State.PLAYER_TURN or _busy:
		return
	if event.is_action_pressed(FightBoard.COMMIT_ACTION):
		_on_verb()
	elif event.is_action_pressed(FightBoard.CONTEXT_ACTION):
		_on_nudge()
	elif event.is_action_pressed(FightBoard.REROLL_ACTION):
		_on_reroll()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_die_pressed(die_id: int) -> void:
	if _busy or room.state != DiceRoom.State.PLAYER_TURN:
		return
	if _reroll_mode:
		var reason: String = room.reroll_refusal(die_id)
		if not reason.is_empty():
			_say(reason, true)
			return
		_reroll_discard = die_id
		_refresh()
		return
	if not room.die(die_id).slot_id.is_empty():
		_take_back(die_id)
		return
	_selected = -1 if _selected == die_id else die_id
	_refresh()


func _on_die_drag_started(die_id: int) -> void:
	if not _reroll_mode and _selected != die_id:
		_on_die_pressed(die_id)


func _on_die_dropped(die_id: int, slot_id: String) -> void:
	if _reroll_mode or not room.die(die_id).is_free():
		return
	_selected = die_id
	_on_slot_pressed(slot_id)


func _on_slot_pressed(slot_id: String) -> void:
	if _busy or room.state != DiceRoom.State.PLAYER_TURN:
		return
	if _selected < 0:
		_say("Pick a die first.", false)
		return
	var reason: String = room.place_refusal(_selected, slot_id)
	if not reason.is_empty():
		PlaytestLog.log_event("invalid_drop", {"die": _selected, "value": room.die(_selected).value, "slot": slot_id, "room": room.room_id})
		_slot_cards[slot_id].preview_text = reason
		_slot_cards[slot_id].preview_tone = "error"
		_slot_cards[slot_id].queue_redraw()
		_sounds.play("invalid")
		return
	room.place(_selected, slot_id)
	PlaytestLog.log_event("place", {"die": _selected, "slot": slot_id, "room": room.room_id})
	_sounds.play("place")
	_selected = -1
	_say("", false)
	_refresh()
	_focus_first_free_die()


func _on_slot_secondary(slot_id: String) -> void:
	var s: DiceRoom.Slot = room.slot(slot_id)
	if _busy or s == null or s.dice.is_empty():
		_cancel()
		return
	_take_back(s.dice[s.dice.size() - 1])


func _take_back(die_id: int) -> void:
	if room.take_back(die_id):
		PlaytestLog.log_event("take_back", {"die": die_id, "turn": room.turn, "room": room.room_id})
		_sounds.play("take_back")
		_refresh()


func _on_nudge() -> void:
	if _busy or room.table.nudge_perk.is_empty():
		return
	var target: int = _selected
	if target < 0:
		var focused: DieView = get_viewport().gui_get_focus_owner() as DieView
		target = focused.die_id if focused != null else -1
	if target < 0:
		_say("Pick a die to nudge.", false)
		return
	if not room.nudge(target):
		_say("Nudge: once a turn, on an unplaced die below 6.", true)
		return
	_refresh()


func _on_reroll() -> void:
	if _busy:
		return
	if not _reroll_mode:
		if room.table.rerolls_left <= 0:
			_say("No rerolls left this turn.", true)
			return
		_reroll_mode = true
		_reroll_discard = -1
		_selected = -1
		_say("Pick a die to discard. B cancels.", false)
		_refresh()
		return
	if _reroll_discard < 0:
		_say("Pick a die to discard first.", false)
		return
	room.reroll(_reroll_discard)
	_sounds.play("roll")
	_sounds.play("land")
	_reroll_mode = false
	_reroll_discard = -1
	_say("", false)
	_refresh()


func _cancel() -> void:
	_selected = -1
	_reroll_mode = false
	_reroll_discard = -1
	_say("", false)
	_refresh()


func _on_verb() -> void:
	if _busy or room.state != DiceRoom.State.PLAYER_TURN:
		return
	_cancel()
	var before: Dictionary = _snapshot()
	var start: int = room.events.size()
	room.end_turn()
	_last_turn.text = "Last turn: " + describe(room.events.slice(start), before)
	if room.state == DiceRoom.State.PLAYER_TURN:
		_sounds.play("roll")
		_sounds.play("land")
	_refresh()
	if room.state != DiceRoom.State.PLAYER_TURN:
		_show_results()


# --- What the room says -------------------------------------------------------

## What the big button would do now, from the room's own pipeline on a
## planning copy. Keys: headline, detail, lost (HP), healed, wasted.
func turn_preview() -> Dictionary:
	var copy: DiceRoom = room.planning_copy()
	copy.end_turn()
	var out: Dictionary = {"headline": "", "detail": "", "lost": maxi(0, room.hp - copy.hp), "healed": maxi(0, copy.hp - room.hp), "wasted": 0}
	match room.room_id:
		DelveMap.TREASURE:
			var gains: PackedStringArray = _gains(room.payout, copy.payout)
			out["headline"] = " · ".join(gains) if not gains.is_empty() else "Nothing yet"
			out["detail"] = "Open takes what the full locks hold, and the room ends." if not gains.is_empty() \
				else "Fill a lock to take what it holds. Open ends the room."
		DelveMap.REST:
			var soaked: int = 0
			for s: DiceRoom.Slot in room.slots:
				soaked += room.slot_amount(s)
			out["wasted"] = soaked - (out["healed"] as int)
			out["headline"] = "Heal %d" % out["healed"]
			if (out["wasted"] as int) > 0:
				out["headline"] += " (%d wasted, you're at %d/%d)" % [out["wasted"], room.hp, room.max_hp]
			out["detail"] = "Soak heals by the dice in the water, up to your max HP. The room ends."
		_:
			# Locks this turn opens: full now and not opened on an earlier turn.
			var opened: int = 0
			for s: DiceRoom.Slot in room.slots:
				if not s.sealed and s.is_complete():
					opened += 1
			var parts: PackedStringArray = []
			if copy.succeeded:
				parts.append("Opens the cage")
			else:
				parts.append("Opens no locks" if opened == 0 else "Opens %d lock%s" % [opened, "" if opened == 1 else "s"])
				if (out["lost"] as int) > 0:
					parts.append("Lose %d · tide" % out["lost"])
				if copy.state == DiceRoom.State.LOST:
					parts.append("Down")
				elif room.turns_left() <= 1:
					parts.append("last turn: they stay caged")
			out["headline"] = " · ".join(parts)
			out["detail"] = "Each turn the cage stays shut, the tide takes %d HP, ignoring block." % room.tide_damage
	return out


## One dimmed line about a resolved turn.
func describe(turn_events: Array, before: Dictionary) -> String:
	var parts: PackedStringArray = []
	for event: Dictionary in turn_events:
		match event["type"] as String:
			"turn_start":
				break
			"open":
				var id: String = str(event["source"]).trim_prefix("slot:")
				parts.append("opened the %s" % str(room.slot(id).row["name"]).to_lower())
			"damage":
				parts.append("the tide took %d HP" % event["amount"])
	if parts.is_empty():
		parts.append("no lock opened")
	if (before["hp"] as int) != room.hp and room.room_id == DelveMap.REST:
		parts = PackedStringArray(["healed %d HP" % (room.hp - (before["hp"] as int))])
	return " · ".join(parts)


func _snapshot() -> Dictionary:
	return {"hp": room.hp, "payout": room.payout.duplicate()}


func _gains(before: Dictionary, after: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in data.ids("resources"):
		var gained: int = (after.get(id, 0) as int) - (before.get(id, 0) as int)
		if gained > 0:
			out.append("+%d %s" % [gained, str(data.row("resources", id)["name"]).to_lower()])
	return out


## The footer for a slot: what it does with the dice in it, or with the
## held die added.
func slot_preview(s: DiceRoom.Slot) -> Dictionary:
	var out: Dictionary = {"text": "", "tone": "ok", "fit": 0}
	if s.sealed:
		return {"text": "Open · its dice came back", "tone": "ok", "fit": -1 if _selected >= 0 else 0}
	var values: Array[int] = room.table.values_in(s)
	if _selected >= 0 and s.dice.size() >= s.max_dice():
		# A full slot is a plan, not a mistake: say what it holds, in a
		# neutral tone (Mara, #30). Red is for a drop that was refused.
		var held: String = _effect_text(s, DiceTable.amount(s, values)) if s.is_complete() else "doesn't match yet"
		return {"text": "Full · " + held, "tone": "ok" if s.is_complete() else "wait", "fit": -1}
	if _selected >= 0:
		var reason: String = room.place_refusal(_selected, s.id)
		if not reason.is_empty():
			return {"text": reason, "tone": "error", "fit": -1}
		out["fit"] = 1
		values.append(room.die(_selected).value)
	if values.is_empty():
		return out
	if s.is_complete_with(values):
		out["text"] = _effect_text(s, DiceTable.amount(s, values))
	elif s.row["accepts"] == "sum_at_least":
		var total: int = 0
		for v: int in values:
			total += v
		out["text"] = "%d / %d" % [total, s.row["min"]]
		out["tone"] = "wait"
	else:
		var missing: int = maxi(1, s.min_dice() - values.size())
		out["text"] = "Needs %d more" % missing if values.size() < s.min_dice() else "Doesn't match yet"
		out["tone"] = "wait"
	return out


func _effect_text(s: DiceRoom.Slot, amount: int) -> String:
	match s.row["effect"] as String:
		"resource":
			return "+%d %s" % [amount, str(data.row("resources", str(s.row["resource"]))["name"]).to_lower()]
		"heal":
			# Capped at max HP before it's shown (Mara, #29).
			var healed: int = mini(amount, room.max_hp - room.hp)
			return "Heal %d" % healed if healed == amount else "Heal %d (%d wasted)" % [healed, amount - healed]
		"open":
			return "Opens"
	return ""


func _villager_role() -> String:
	if data.has_row("villagers", villager):
		return str(data.row("villagers", villager)["role"])
	return "villager"


func results_text() -> String:
	var lines: PackedStringArray = []
	match room.room_id:
		DelveMap.TREASURE:
			var gains: PackedStringArray = _gains({}, room.payout)
			lines.append("You found " + ", ".join(gains).replace("+", "") + "." if not gains.is_empty() else "Nothing this time.")
		DelveMap.REST:
			lines.append("You healed %d HP." % (room.hp - room.start_hp))
		_:
			if room.succeeded:
				lines.append("The cage opens. The %s joins your haul." % _villager_role().to_lower())
			elif room.state == DiceRoom.State.LOST:
				lines.append("The tide took you under.")
			else:
				lines.append("The %s is still caged. You'll find them again." % _villager_role().to_lower())
	lines.append("HP %d / %d" % [room.hp, room.max_hp])
	return "\n".join(lines)


# --- Drawing state --------------------------------------------------------------

func _refresh() -> void:
	for view: DieView in _dice:
		var d: DiceRoom.Die = room.die(view.die_id)
		view.value = d.value
		view.locked = d.locked
		view.discarded = d.discarded
		view.selected = view.die_id == _selected or view.die_id == _reroll_discard
		view.placed = not d.slot_id.is_empty()
		view.placed_order = _slot_cards[d.slot_id].order if view.placed else 0
	for s: DiceRoom.Slot in room.slots:
		var card: SlotCard = _slot_cards[s.id]
		card.placed_values.clear()
		for placed: int in s.dice:
			card.placed_values.append(room.die(placed).value)
		card.opened = s.sealed
		var p: Dictionary = slot_preview(s)
		card.preview_text = p["text"]
		card.preview_tone = p["tone"]
		card.held_fit = p["fit"]
		card.held_value = room.die(_selected).value if _selected >= 0 else 0
		card.queue_redraw()
	var t: Dictionary = turn_preview()
	_end_preview.text = t["headline"]
	_end_detail.text = t["detail"]
	_hp.text = "HP %d / %d" % [room.hp, room.max_hp]
	_hp_bar.max_hp = room.max_hp
	_hp_bar.hp = room.hp
	_hp_bar.ghost = t["lost"] if room.state == DiceRoom.State.PLAYER_TURN else 0
	_hp_bar.gain = t["healed"] if room.state == DiceRoom.State.PLAYER_TURN else 0
	if room.room_id == DelveMap.RESCUE:
		_turns.text = "Turn %d / %d" % [mini(room.turn, room.turns), room.turns]
		_tide.turn = room.turn if room.state == DiceRoom.State.PLAYER_TURN else room.turns + 1
		_tide.turns = room.turns
		_tide.open = room.succeeded
		if room.succeeded:
			_tide.turn = room.turn
		_tide.queue_redraw()
	_reroll.visible = room.table.rerolls_per_turn > 0
	_reroll.disabled = room.table.rerolls_left <= 0 and not _reroll_mode
	if _reroll_mode:
		_reroll.text = "Confirm: discard %d, reroll the rest" % room.die(_reroll_discard).value if _reroll_discard >= 0 else "Pick a die to discard"
	else:
		_reroll.text = "Reroll (%d left)" % room.table.rerolls_left
	var nudger: String = room.table.nudge_source
	_nudge.visible = not room.table.nudge_perk.is_empty()
	_nudge.disabled = room.table.nudges_left <= 0
	var nudger_name: String = str(data.row("villagers", nudger)["role"]) if data.has_row("villagers", nudger) else nudger
	_nudge.text = "Nudge +1 · %s" % nudger_name if room.table.nudges_left > 0 else "Nudge used · %s" % nudger_name
	_nudge_chip.villager_id = nudger
	_nudge_chip.role = nudger_name
	_nudge_chip.dimmed = room.table.nudges_left <= 0
	_verb.disabled = room.state != DiceRoom.State.PLAYER_TURN


func _say(text: String, is_error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", BoardStyle.DANGER if is_error else BoardStyle.INK)


func _focus_first_free_die() -> void:
	for view: DieView in _dice:
		if not view.placed and not view.discarded:
			view.grab_focus()
			return
	_verb.grab_focus()


func _on_continue() -> void:
	# A press meant for the button before can't skip the result (Mara, #30).
	if Time.get_ticks_msec() >= _results_shown_at + RESULT_GUARD_MS:
		finished.emit()


func _show_results() -> void:
	_results_text.text = results_text()
	_results.visible = true
	_results_shown_at = Time.get_ticks_msec()
	_continue.grab_focus()
	PlaytestLog.log_event("room_result", {"room": room.room_id, "turns": room.turn, "payout": room.payout, "hp": room.hp,
		"opened": room.succeeded})


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
	for side: String in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 40 + top_inset)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)

	# The room across the felt.
	var head_row: HBoxContainer = HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(head_row)
	var head: PanelContainer = PanelContainer.new()
	head.add_theme_stylebox_override("panel", BoardStyle.panel())
	head.custom_minimum_size = Vector2(1100, 150)
	head_row.add_child(head)
	var head_inner: HBoxContainer = HBoxContainer.new()
	head_inner.add_theme_constant_override("separation", 32)
	head.add_child(head_inner)
	var head_text: VBoxContainer = VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_inner.add_child(head_text)
	_title = BoardStyle.label(_room_title(), BoardStyle.NUMBER, BoardStyle.GOLD)
	_title.add_theme_font_override("font", BoardStyle.title_font())
	head_text.add_child(_title)
	_intro = BoardStyle.label(INTROS.get(room.room_id, ""), BoardStyle.BODY, BoardStyle.INK)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size = Vector2(800, 0)
	head_text.add_child(_intro)
	_turns = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.INK)
	_turns.add_theme_font_override("font", BoardStyle.strong_font())
	head_text.add_child(_turns)
	_tide = TideView.new()
	_tide.visible = room.room_id == DelveMap.RESCUE
	head_inner.add_child(_tide)

	var lines: HBoxContainer = HBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 40)
	lines.custom_minimum_size = Vector2(0, 40)
	column.add_child(lines)
	_last_turn = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	lines.add_child(_last_turn)
	_message = BoardStyle.label("", BoardStyle.BODY)
	lines.add_child(_message)

	var slot_row: HBoxContainer = HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 24)
	column.add_child(slot_row)
	var order: int = 1
	for s: DiceRoom.Slot in room.slots:
		var card: SlotCard = SlotCard.new()
		card.slot_id = s.id
		card.order = order
		card.title = str(s.row["name"])
		card.rule_text = str(s.row["text"])
		card.sockets = s.max_dice()
		card.is_pair = s.row["accepts"] == "pair"
		for face: int in 6:
			card.accepted[face] = RoomBot._each_die_fits(s, [face + 1] as Array[int])
		card.pressed.connect(_on_slot_pressed.bind(s.id))
		card.secondary_pressed.connect(_on_slot_secondary.bind(s.id))
		card.die_dropped.connect(_on_die_dropped.bind(s.id))
		slot_row.add_child(card)
		_slot_cards[s.id] = card
		order += 1

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
	_hp_bar = HpBar.new()
	player_box.add_child(_hp_bar)
	_hp = BoardStyle.label("", BoardStyle.BODY)
	player_box.add_child(_hp)

	var hand: HBoxContainer = HBoxContainer.new()
	hand.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.add_theme_constant_override("separation", 20)
	bottom.add_child(hand)
	for d: DiceRoom.Die in room.hand:
		var view: DieView = DieView.new()
		view.die_id = d.id
		view.custom_minimum_size = Vector2(150, 150)
		view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		view.pressed.connect(_on_die_pressed.bind(d.id))
		view.secondary_pressed.connect(_cancel)
		view.drag_started.connect(_on_die_drag_started.bind(d.id))
		hand.add_child(view)
		_dice.append(view)

	var verbs: VBoxContainer = VBoxContainer.new()
	verbs.custom_minimum_size = Vector2(520, 0)
	verbs.add_theme_constant_override("separation", 12)
	bottom.add_child(verbs)
	_end_preview = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.INK)
	_end_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_preview.custom_minimum_size = Vector2(520, 0)
	verbs.add_child(_end_preview)
	_end_detail = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	_end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_detail.custom_minimum_size = Vector2(520, 0)
	verbs.add_child(_end_detail)
	var verb_row: HBoxContainer = HBoxContainer.new()
	verb_row.add_theme_constant_override("separation", 12)
	verbs.add_child(verb_row)
	_nudge = _button("Nudge +1", 0)
	_nudge.pressed.connect(_on_nudge)
	verb_row.add_child(_nudge)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		(_nudge.get_theme_stylebox(state) as StyleBoxFlat).content_margin_left = 60
	_nudge_chip = FaceChip.new()
	_nudge.add_child(_nudge_chip)
	_nudge_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_KEEP_SIZE, 10)
	_reroll = _button("Reroll", 0)
	_reroll.pressed.connect(_on_reroll)
	verb_row.add_child(_reroll)
	_verb = _button(VERBS.get(room.room_id, "End turn"), 80, true)
	_verb.pressed.connect(_on_verb)
	verbs.add_child(_verb)

	_results = PanelContainer.new()
	_results.add_theme_stylebox_override("panel", BoardStyle.panel())
	_results.visible = false
	add_child(_results)
	_results.custom_minimum_size = Vector2(720, 300)
	_results.position = Vector2(600, 380)
	var results_box: VBoxContainer = VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 20)
	_results.add_child(results_box)
	_results_text = BoardStyle.label("", BoardStyle.NUMBER)
	_results_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_text.custom_minimum_size = Vector2(680, 0)
	results_box.add_child(_results_text)
	_continue = _button("Continue", 72)
	_continue.pressed.connect(_on_continue)
	results_box.add_child(_continue)


func _room_title() -> String:
	var name: String = str(data.row("rooms", room.room_id)["name"]) if data.has_row("rooms", room.room_id) else room.room_id
	if room.room_id == DelveMap.RESCUE and not villager.is_empty():
		return "%s · the %s" % [name, _villager_role().to_lower()]
	return name


static func _button(text: String, height: int, primary: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", BoardStyle.BODY)
	b.add_theme_font_override("font", BoardStyle.strong_font())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, height if height > 0 else 56)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD if state != "disabled" else BoardStyle.DIM)
		box.set_content_margin_all(8)
		if state == "hover" or state == "pressed":
			box.bg_color = BoardStyle.FELT
		if primary and state != "disabled":
			box.bg_color = BoardStyle.GOLD if state == "normal" else BoardStyle.GOLD.lightened(0.15)
		b.add_theme_stylebox_override(state, box)
	var focus: StyleBoxFlat = BoardStyle.panel(BoardStyle.INK, Color(0, 0, 0, 0))
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", focus)
	for key: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(key, BoardStyle.LACQUER if primary else BoardStyle.INK)
	return b
