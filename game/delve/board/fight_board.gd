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
##   R or Slow pour (Tea stall's perk)          reroll every free die, no discard
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
	## Who chummed the water ("Bait shop"), for the badge after an attack
	## Chum raised: "8 ↑(+1 · Bait shop)" (specs/bridge.md section 5).
	var chum_source: String = ""

	func _init() -> void:
		custom_minimum_size = Vector2(420, 150)

	func _draw() -> void:
		var font: Font = get_theme_default_font()
		var x: float = 0
		for kind: String in ["attack", "guard"]:
			if current.has(kind):
				BoardStyle.draw_intent_glyph(self, Rect2(x, 10, 72, 72), kind, BoardStyle.INK)
				draw_string(font, Vector2(x + 80, 70), str(current[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BIG, BoardStyle.INK)
				var after: float = x + 80 + font.get_string_size(str(current[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BIG).x + 8
				if kind == "attack" and current.has("raised"):
					# Rising stakes, shown climbing (Mara, #32).
					after = _draw_raise(font, Vector2(after, 70), current["raised"] as int, BoardStyle.BODY, BoardStyle.AMBER) + 8
				if kind == "attack" and current.has("chum"):
					# Chum's cost, named so the extra damage has a cause.
					var label: String = str(current["chum"]) if chum_source.is_empty() else "%d · %s" % [current["chum"], chum_source]
					after = _draw_raise(font, Vector2(after, 70), 0, BoardStyle.BODY, BoardStyle.GOLD, label) + 8
				x = maxf(x + 190, after + 24)
		draw_string(font, Vector2(0, 128), "next", HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.SMALL, BoardStyle.DIM)
		x = 60
		for kind: String in ["attack", "guard"]:
			if next.has(kind):
				BoardStyle.draw_intent_glyph(self, Rect2(x, 104, 32, 32), kind, BoardStyle.DIM)
				draw_string(font, Vector2(x + 36, 130), str(next[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY, BoardStyle.DIM)
				var bump: int = int(next.get("raised", 0)) + int(next.get("chum", 0))
				var after: float = x + 36 + font.get_string_size(str(next[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, BoardStyle.BODY).x + 6
				if kind == "attack" and bump > 0:
					after = _draw_raise(font, Vector2(after, 130), bump, BoardStyle.SMALL, BoardStyle.DIM) + 6
				x = maxf(x + 90, after + 20)

	## "(+2)" after an attack raised by Rising stakes (or "(+1 · Bait shop)"
	## by Chum, from `label`), with a small up arrow drawn in front so it
	## reads as climbing, not as the base number. Returns where it ends.
	func _draw_raise(font: Font, at: Vector2, amount: int, font_size: int, color: Color, label: String = "") -> float:
		var h: float = font_size * 0.5
		var tip: Vector2 = at + Vector2(h * 0.5, -font_size * 0.75)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(h * 0.5, h * 0.6), tip + Vector2(-h * 0.5, h * 0.6)]), color)
		draw_line(tip + Vector2(0, h * 0.5), tip + Vector2(0, h * 1.3), color, 3.0)
		var text: String = "(+%s)" % (label if not label.is_empty() else str(amount))
		draw_string(font, at + Vector2(h + 4, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		return at.x + h + 4 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


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
var _enemy_bar: HpBar
var _enemy_block: Label
var _intent: IntentView
var _twist: Label
var _message: Label
var _badge: Label
var _sounds: BoardSounds
var _nudge_chip: FaceChip
var _slot_cards: Dictionary[String, SlotCard] = {}
var _dice: Array[DieView] = []
var _player_hp: Label
var _player_bar: HpBar
var _player_block: Label
var _end_turn: Button
var _end_preview: Label
var _end_detail: Label
var _last_turn: Label
var _turn: Dictionary = {}
var _reroll: Button
var _nudge: Button
var _results: PanelContainer
var _results_text: Label
var _again: Button
var _leave: Button
## The results panel's buttons: what "again" says, and whether "Return to
## town" shows. Set before adding the board to the tree.
var again_text: String = "Fight again"
var leave_shown: bool = true
## Room left free above the board for the delve's haul strip. Set before
## adding the board to the tree.
var top_inset: int = 0


## Show the one-line banner for this enemy's twist (the first meeting).
## Set before adding the board to the tree.
var twist_banner: bool = false
var _banner: PanelContainer

## Builds the board for `new_fight`. Call before adding it to the tree.
func setup(new_fight: Fight, game_data: GameData) -> void:
	fight = new_fight
	data = game_data


func _ready() -> void:
	_ensure_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BoardStyle.theme()
	_sounds = BoardSounds.new()
	add_child(_sounds)
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


## Dragging holds the die, so every slot previews it during the drag.
func _on_die_drag_started(die_id: int) -> void:
	if _reroll_mode or _selected == die_id:
		return
	_on_die_pressed(die_id)


func _on_die_dropped(die_id: int, slot_id: String) -> void:
	if _reroll_mode or not fight.die(die_id).is_free():
		return
	_selected = die_id
	_on_slot_pressed(slot_id)


func _on_slot_pressed(slot_id: String) -> void:
	if _busy or fight.state != Fight.State.PLAYER_TURN:
		return
	if _selected < 0:
		_say("Pick a die first.", false)
		return
	var reason: String = fight.place_refusal(_selected, slot_id)
	if not reason.is_empty():
		PlaytestLog.log_event("invalid_drop", {"die": _selected, "value": fight.die(_selected).value, "slot": slot_id})
		var card: SlotCard = _slot_cards[slot_id]
		card.preview_text = reason
		card.preview_tone = "error"
		_pulse(card, fight.slot(slot_id).dice.size() >= fight.slot(slot_id).max_dice())
		_sounds.play("invalid")
		return
	PlaytestLog.log_event("place", {"die": _selected, "slot": slot_id, "hover_ms": Time.get_ticks_msec() - _selected_at_ms})
	fight.place(_selected, slot_id)
	_sounds.play("place")
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
		_sounds.play("take_back")
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
	if fight.table.is_pouring():
		var refusal: String = fight.pour_refusal()
		if not refusal.is_empty():
			_say(refusal, true)
			return
		_selected = -1
		fight.pour()
		_roll_sound()
		_say("", false)
		_refresh_all()
		_show_badge(fight.events.back())
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
	_roll_sound()
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
	_banner.visible = false
	var start: int = fight.events.size()
	fight.end_turn()
	var turn_events: Array[Dictionary] = fight.events.slice(start)
	await _play(turn_events)
	if fight.state == Fight.State.PLAYER_TURN:
		_roll_sound()
	_last_turn.text = "Last turn: " + _describe(turn_events)
	_moves_seen = fight.moves.size()
	_refresh_all()
	if fight.state != Fight.State.PLAYER_TURN:
		_show_results()


## The rattle of a roll, then the dice landing.
func _roll_sound() -> void:
	_sounds.play("roll")
	_sounds.play("land")


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
		Fight.POUR_PERK:
			var uses: int = fight.perk_amount(Fight.POUR_PERK)
			what = "Slow pour · used %d of %d" % [uses - int(event["left"]), uses]
	_badge.text = "%s · %s" % [_source_name(str(event["source"])), what]
	_badge.visible = true


func _source_name(source: String) -> String:
	if data != null and data.has_row("villagers", source):
		return str(data.row("villagers", source)["role"])
	if data != null and data.has_row("buildings", source):
		return str(data.row("buildings", source)["name"])
	return source.capitalize()


# --- Drawing state ------------------------------------------------------------

var _moves_seen: int = 0


func _refresh_all() -> void:
	if fight.moves.size() != _moves_seen:
		_moves_seen = fight.moves.size()
		if not _busy:
			_last_turn.text = ""
	_shown_enemy_hp = fight.enemy_hp
	_shown_enemy_block = fight.enemy_block
	_shown_player_hp = fight.player_hp
	_shown_player_block = fight.player_block
	_refresh_numbers()
	_intent.chum_source = _source_name(fight.perk_source(Fight.CHUM_PERK)) if fight.has_perk(Fight.CHUM_PERK) else ""
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
		view.placed_order = _slot_cards[d.slot_id].order if view.placed else 0
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
	if fight.table.is_pouring():
		_reroll.disabled = fight.table.pours_left <= 0
		_reroll.text = "Slow pour (%d left)" % fight.table.pours_left
	elif _reroll_mode:
		var others: int = 0
		for d: Fight.Die in fight.hand:
			if d.is_free() and not d.locked and d.id != _reroll_discard:
				others += 1
		_reroll.text = "Confirm: discard %d, reroll %d" % [fight.die(_reroll_discard).value, others] if _reroll_discard >= 0 else "Pick a die to discard"
	else:
		_reroll.text = "Reroll (%d left)" % fight.rerolls_left
	_nudge.visible = fight.has_perk(Fight.NUDGE_PERK)
	_nudge.disabled = fight.nudges_left <= 0
	var nudge_source: String = fight.perk_source(Fight.NUDGE_PERK)
	var nudger: String = _source_name(nudge_source) if fight.has_perk(Fight.NUDGE_PERK) else ""
	_nudge_chip.villager_id = nudge_source
	_nudge_chip.role = nudger
	_nudge_chip.dimmed = fight.nudges_left <= 0
	_nudge.text = "Nudge +1 · %s" % nudger if fight.nudges_left > 0 else "Nudge used · %s" % nudger
	_turn = turn_preview()
	_end_preview.text = end_turn_summary()
	_end_detail.text = _turn["detail"]
	_refresh_numbers()


func _refresh_numbers() -> void:
	var planning: bool = not _busy and not _turn.is_empty()
	_enemy_name.text = fight.enemy_name
	_enemy_bar.max_hp = fight.enemy_max_hp
	_enemy_bar.hp = _shown_enemy_hp
	_enemy_bar.ghost = _turn["enemy_lost"] if planning else 0
	_enemy_hp.text = "HP %d / %d" % [_shown_enemy_hp, fight.enemy_max_hp]
	_enemy_block.text = "Guard %d" % _shown_enemy_block if _shown_enemy_block > 0 else ""
	_player_bar.max_hp = fight.player_max_hp
	_player_bar.hp = _shown_player_hp
	_player_bar.ghost = _turn["lost"] if planning else 0
	_player_hp.text = "HP %d / %d" % [_shown_player_hp, fight.player_max_hp]
	var gain: int = _turn["block"] if planning else 0
	var spined: int = _turn["spined"] if planning else 0
	_player_block.text = "Block %d  (+%d)" % [_shown_player_block, gain] if gain > 0 else "Block %d" % _shown_player_block
	if spined > 0:
		# The cost of Spines sits on the stat it changes (Mara, #32).
		_player_block.text = "Block %d  (+%d · spines stop %d)" % [_shown_player_block, gain, spined]


func _set_preview(card: SlotCard, s: Fight.Slot) -> void:
	card.preview_text = ""
	card.preview_tone = "ok"
	card.held_value = fight.die(_selected).value if _selected >= 0 else 0
	card.held_fit = 0
	if s.sealed:
		# Fired on the turn it completed; it won't fire again.
		card.preview_text = "Done"
		if _selected >= 0:
			card.held_fit = -1
		return
	if s.is_complete():
		card.preview_text = _effect_text(s.row["effect"] as String, fight.slot_amount(s), -1)
		if _selected >= 0:
			card.held_fit = -1
		return
	if _selected < 0:
		if s.dice.size() > 0:
			card.preview_text = "Waits for a %d" % fight.die(s.dice[0]).value
			card.preview_tone = "wait"
		return
	var p: Dictionary = fight.preview(_selected, s.id)
	card.held_fit = 1 if p["ok"] else -1
	if not p["ok"]:
		card.preview_text = p["reason"]
		card.preview_tone = "error"
	elif not p["complete"]:
		var value: int = fight.die(_selected).value
		card.preview_tone = "wait"
		if p["can_complete"]:
			card.preview_text = "Waits for a %d · %s" % [value, _effect_text(p["effect"] as String, p["amount"] as int, p["blocked"] as int, true)]
		else:
			card.preview_text = "Waits for a %d (none in hand)" % value
	else:
		card.preview_text = _effect_text(p["effect"] as String, p["amount"] as int, p["blocked"] as int)


## `short` abbreviates for a footer that also carries a condition.
func _effect_text(effect: String, amount: int, blocked: int, short: bool = false) -> String:
	match effect:
		"damage":
			var unit: String = "dmg" if short else "damage"
			if blocked > 0:
				return "%d %s (%d into guard)" % [amount, unit, blocked]
			return "%d %s" % [amount, unit]
		"block":
			return "Block %d" % amount
		"heal":
			return "Heal %d" % amount
	return ""


## What End turn would do, from the real pipeline on a copy. Keys: dealt,
## into_guard, block, bites, hit, lost (all HP you'd lose, bites included),
## enemy_lost, state, detail (the full breakdown line).
func turn_preview() -> Dictionary:
	var preview: Dictionary = fight.preview_end_turn()
	var t: Dictionary = {"dealt": 0, "into_guard": 0, "block": 0, "bites": 0, "hit": 0, "hit_taken": 0, "spined": 0}
	for event: Dictionary in preview["events"] as Array[Dictionary]:
		match event["type"] as String:
			"damage":
				if event["target"] == "enemy":
					t["dealt"] += (event["amount"] as int) + (event["blocked"] as int)
					t["into_guard"] += event["blocked"] as int
				elif event["source"] == "enemy":
					t["hit"] = (event["amount"] as int) + (event["blocked"] as int)
					t["hit_taken"] = event["amount"] as int
				else:
					t["bites"] += event["amount"] as int
			"block":
				if event["target"] == "player":
					t["block"] += event["amount"] as int
			"twist":
				if event["twist"] == "spines":
					t["spined"] += event["amount"] as int
	t["lost"] = fight.player_hp - (preview["player_hp"] as int)
	t["enemy_lost"] = fight.enemy_hp - (preview["enemy_hp"] as int)
	t["state"] = preview["state"]
	var parts: PackedStringArray = []
	parts.append("Deal %d (%d into guard)" % [t["dealt"], t["into_guard"]] if (t["into_guard"] as int) > 0 else "Deal %d" % t["dealt"])
	if (t["block"] as int) > 0:
		parts.append("block +%d" % t["block"])
	if (t["spined"] as int) > 0:
		parts.append("spines stop %d block" % t["spined"])
	if preview["state"] == Fight.State.WON:
		parts.append("%s goes down first" % fight.enemy_name)
	else:
		if (t["hit"] as int) > 0:
			parts.append("%s hits %d" % [fight.enemy_name, t["hit"]])
		if (t["bites"] as int) > 0:
			parts.append("bite %d" % t["bites"])
		parts.append("you lose %d" % t["lost"])
	t["detail"] = " · ".join(parts)
	return t


## The End turn headline (Mara): two big numbers, "Deal 8 · Lose 4", or the
## outcome when the turn ends the fight.
func end_turn_summary() -> String:
	var t: Dictionary = turn_preview()
	match t["state"] as Fight.State:
		Fight.State.WON:
			return "Deal %d · Win" % t["dealt"]
		Fight.State.LOST:
			return "Deal %d · Lose %d · Down" % [t["dealt"], t["lost"]]
	return "Deal %d · Lose %d" % [t["dealt"], t["lost"]]


## One dimmed line about what a resolved turn did.
func _describe(turn_events: Array[Dictionary]) -> String:
	var dealt: int = 0
	var hit: int = 0
	var bites: int = 0
	for event: Dictionary in turn_events:
		if event["type"] == "turn_start":
			break
		if event["type"] == "damage":
			if event["target"] == "enemy":
				dealt += event["amount"] as int
			elif event["source"] == "enemy":
				hit += event["amount"] as int
			else:
				bites += event["amount"] as int
	var parts: PackedStringArray = ["you dealt %d" % dealt]
	if hit > 0:
		parts.append("%s hit you for %d" % [fight.enemy_name, hit])
	if bites > 0:
		parts.append("bite %d" % bites)
	return " · ".join(parts)


func _say(text: String, is_error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", BoardStyle.DANGER if is_error else BoardStyle.INK)


func _pulse(card: SlotCard, sockets: bool) -> void:
	card.pulsing = not sockets
	card.pulsing_sockets = sockets
	card.queue_redraw()
	await get_tree().create_timer(0.3 if not Settings.reduce_motion else 0.15).timeout
	card.pulsing = false
	card.pulsing_sockets = false
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
	margin.add_theme_constant_override("margin_top", 40 + top_inset)
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
	enemy_panel.custom_minimum_size = Vector2(1100, 0)
	enemy_row.add_child(enemy_panel)
	var enemy_inner: HBoxContainer = HBoxContainer.new()
	enemy_inner.add_theme_constant_override("separation", 40)
	enemy_panel.add_child(enemy_inner)
	var enemy_box: VBoxContainer = VBoxContainer.new()
	enemy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_inner.add_child(enemy_box)
	_enemy_name = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.GOLD)
	_enemy_name.add_theme_font_override("font", BoardStyle.title_font())
	enemy_box.add_child(_enemy_name)
	_enemy_bar = HpBar.new()
	_enemy_bar.fill = BoardStyle.DANGER
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
	enemy_inner.add_child(_intent)

	# First meeting with a twist: one line, gone after the first turn.
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", BoardStyle.panel(BoardStyle.AMBER, BoardStyle.FELT))
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.visible = twist_banner and not _twist.text.is_empty()
	_banner.add_child(BoardStyle.label("New twist · " + _twist.text, BoardStyle.BODY, BoardStyle.AMBER))

	var lines: HBoxContainer = HBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 40)
	# Tall enough for the twist banner, so nothing jumps when it goes.
	lines.custom_minimum_size = Vector2(0, 68)
	column.add_child(lines)
	lines.add_child(_banner)
	_last_turn = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	lines.add_child(_last_turn)
	_message = BoardStyle.label("", BoardStyle.BODY)
	lines.add_child(_message)

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
		card.sockets = s.max_dice()
		card.is_pair = s.row["accepts"] == "pair"
		for face: int in 6:
			card.accepted[face] = _accepts_face(s.row, face + 1)
		card.pressed.connect(_on_slot_pressed.bind(s.id))
		card.secondary_pressed.connect(_on_slot_secondary.bind(s.id))
		card.die_dropped.connect(_on_die_dropped.bind(s.id))
		slot_row.add_child(card)
		_slot_cards[s.id] = card
		order += 1

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
	_player_bar = HpBar.new()
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
		view.show_type(data, d.type_id)
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
	BoardStyle.reserve_lines(_end_preview, 1)
	verbs.add_child(_end_preview)
	_end_detail = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	_end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	BoardStyle.reserve_lines(_end_detail, 2)
	verbs.add_child(_end_detail)
	_set_detail(false)
	var verb_row: HBoxContainer = HBoxContainer.new()
	verb_row.add_theme_constant_override("separation", 12)
	verbs.add_child(verb_row)
	_nudge = _button("Nudge +1", 0)
	_nudge.pressed.connect(_on_nudge)
	verb_row.add_child(_nudge)
	# The chip of the villager who gives Nudge sits at the button's left edge.
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		(_nudge.get_theme_stylebox(state) as StyleBoxFlat).content_margin_left = 60
	_nudge_chip = FaceChip.new()
	_nudge.add_child(_nudge_chip)
	_nudge_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_KEEP_SIZE, 10)
	_reroll = _button("Reroll", 0)
	_reroll.pressed.connect(_on_reroll)
	verb_row.add_child(_reroll)
	_end_turn = _button("End turn", 80, true)
	_end_turn.pressed.connect(_on_end_turn)
	# The full breakdown shows while End turn is hovered or focused.
	_end_turn.mouse_entered.connect(_set_detail.bind(true))
	_end_turn.mouse_exited.connect(_set_detail.bind(false))
	_end_turn.focus_entered.connect(_set_detail.bind(true))
	_end_turn.focus_exited.connect(_set_detail.bind(false))
	verbs.add_child(_end_turn)
	var trailing: Control = Control.new()
	trailing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(trailing)

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
	_again = _button(again_text, 72)
	_again.pressed.connect(again_requested.emit)
	results_box.add_child(_again)
	_leave = _button("Return to town", 64)
	_leave.pressed.connect(leave_requested.emit)
	_leave.visible = leave_shown
	results_box.add_child(_leave)


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


## The breakdown fades in and out in place: its lines stay reserved, so
## the buttons under it never move.
func _set_detail(shown: bool) -> void:
	_end_detail.modulate.a = 1.0 if shown else 0.0


func _button(text: String, height: int, primary: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", BoardStyle.BODY)
	b.add_theme_font_override("font", BoardStyle.strong_font())
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
		if primary and state != "disabled":
			box.bg_color = BoardStyle.GOLD if state == "normal" else BoardStyle.GOLD.lightened(0.15)
		b.add_theme_stylebox_override(state, box)
	var focus: StyleBoxFlat = BoardStyle.panel(BoardStyle.INK, Color(0, 0, 0, 0))
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", BoardStyle.LACQUER if primary else BoardStyle.INK)
	b.add_theme_color_override("font_hover_color", BoardStyle.LACQUER if primary else BoardStyle.INK)
	b.add_theme_color_override("font_focus_color", BoardStyle.LACQUER if primary else BoardStyle.INK)
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
