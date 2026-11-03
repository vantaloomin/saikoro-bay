class_name VaultBoard
extends Control
## Koban's vault, Beat the House (specs/delve-map.md section 6; Mara's map
## review #8). Best of three: each round Koban rolls her hand openly, you may
## raise, then you roll your kit and put 3 dice in your hand.
##
## What the board shows (Mara #8):
##   - the hand ladder (three of a kind > run > pair > high die), with
##     Koban's hand and yours marked on it, yours live as you place dice
##   - the raise, which starts at none and is never pre-selected; picking
##     one previews "Raise 3 pearls: win +3 · lose -3" (net, Mara #31)
##   - the round score as pips, one per round of the best of three
## Same dice, moves and inputs as the other boards. It only calls the
## vault's moves; previews come from Vault.planning_copy(), which has no RNG
## and its own haul (Imogen, #27). Each round ends on a panel showing both
## hands; Continue after the last one emits finished.

signal finished

const RESULT_GUARD_MS: int = 400
## Ladder rows, top to bottom, with an example hand each.
const LADDER: Array[Array] = [
	[Vault.THREE_KIND, "Three of a kind", "5 5 5"],
	[Vault.RUN, "Run", "3 4 5"],
	[Vault.PAIR, "Pair", "4 4 6"],
	[Vault.HIGH_DIE, "High die", "6 4 2"],
]
const INTRO: String = "Best of three. Beat Koban's hand with three of your dice."


## The round score (Mara #8): a pip per round of the best of three. Won is
## jade with a check, lost is red with a cross, the round being played has
## a gold ring, and rounds still to come are dim. Shape carries it in
## greyscale.
class PipsView:
	extends Control
	var results: Array[bool] = []
	var total: int = 3
	var current: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(3 * 64, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i: int in total:
			var c: Vector2 = Vector2(32 + i * 64, size.y / 2.0)
			if i < results.size():
				var won: bool = results[i]
				draw_circle(c, 20, BoardStyle.JADE if won else BoardStyle.DANGER)
				if won:
					draw_polyline(PackedVector2Array([c + Vector2(-9, 0), c + Vector2(-2, 8), c + Vector2(10, -8)]),
						BoardStyle.LACQUER, 4.0, true)
				else:
					draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), BoardStyle.LACQUER, 4.0, true)
					draw_line(c + Vector2(8, -8), c + Vector2(-8, 8), BoardStyle.LACQUER, 4.0, true)
			elif i == current:
				draw_arc(c, 20, 0, TAU, 40, BoardStyle.GOLD, 4.0, true)
			else:
				draw_arc(c, 20, 0, TAU, 40, BoardStyle.DIM, 2.0, true)


## Koban's three dice, drawn (they can't be picked up).
class HouseDice:
	extends Control
	var values: Array[int] = []
	## How many have landed; the rest show as empty outlines.
	var shown: int = 3

	func _init() -> void:
		custom_minimum_size = Vector2(3 * 112, 100)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i: int in values.size():
			var r: Rect2 = Rect2(Vector2(8 + i * 112, 2), Vector2(96, 96))
			if i < shown:
				BoardStyle.draw_die(self, r, values[i])
			else:
				draw_rect(r, BoardStyle.DIM, false, 2.0)


var vault: Vault
var data: GameData
## The landmark's name ("Café"), for the title and the win copy.
var prize: String = ""
## Room left free above the board for the haul strip.
var top_inset: int = 0

var _selected: int = -1
var _reroll_mode: bool = false
var _reroll_discard: int = -1
## The raise picked for the coming roll ("" for none). It's only staked
## when you roll, so you can change your mind until then.
var _raise_pick: String = ""
## The last round's "round" event while its panel is up, else {}.
var _round_event: Dictionary = {}
## That round's stake events.
var _round_stakes: Array = []

var _pips: PipsView
var _round_label: Label
var _house_dice: HouseDice
var _house_text: Label
var _ladder_rows: Array[PanelContainer] = []
var _ladder_koban: Array[Label] = []
var _ladder_you: Array[Label] = []
var _ladder_dice: Array[Label] = []
var _ladder_tie: Array[Label] = []
var _ladder_footer: Label
var _card: SlotCard
var _message: Label
var _stake_label: Label
var _wager_box: VBoxContainer
var _raise_buttons: Dictionary[String, Button] = {}
var _hand_row: HBoxContainer
var _dice: Array[DieView] = []
var _preview: Label
var _detail: Label
var _nudge: Button
var _nudge_chip: FaceChip
var _reroll: Button
var _verb: Button
var _verbs: VBoxContainer
var _panel: PanelContainer
var _panel_text: Label
var _continue: Button
var _sounds: BoardSounds
var _panel_shown_at: int = 0
var _finished: bool = false


func setup(new_vault: Vault, game_data: GameData, prize_name: String = "") -> void:
	vault = new_vault
	data = game_data
	prize = prize_name


func _ready() -> void:
	FightBoard._ensure_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BoardStyle.theme()
	_sounds = BoardSounds.new()
	add_child(_sounds)
	_build()
	_refresh()
	_verb.grab_focus()
	_reveal_house()
	PlaytestLog.log_event("vault_round_start", {"round": vault.round_number, "house": vault.house_hand.duplicate()})


## Koban's dice land one at a time, about 250 ms apart, so her roll feels
## heavier than yours (Mara, #31). Instant with reduce motion.
func _reveal_house() -> void:
	if Settings.reduce_motion or not is_inside_tree():
		_house_dice.shown = 3
		_house_dice.queue_redraw()
		return
	_house_dice.shown = 0
	_house_dice.queue_redraw()
	var tween: Tween = create_tween()
	for i: int in 3:
		tween.tween_interval(0.25)
		tween.tween_callback(func() -> void:
			_house_dice.shown = i + 1
			_house_dice.queue_redraw()
			_sounds.play("land"))


# --- Words ---------------------------------------------------------------------

## A hand in words: "three 5s", "a run of 3-4-5", "a pair of 4s and a 6",
## "high die 6-4-2". Fewer than 3 dice say what they make so far.
static func describe_hand(values: Array[int]) -> String:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	sorted.reverse()
	if sorted.is_empty():
		return "no dice yet"
	if sorted.size() < 3:
		if sorted.size() == 2 and sorted[0] == sorted[1]:
			return "a pair of %ds so far" % sorted[0]
		var shown: PackedStringArray = []
		for v: int in sorted:
			shown.append(str(v))
		return "%s so far" % ", ".join(shown)
	match Vault.hand_rank(sorted):
		Vault.THREE_KIND:
			return "three %ds" % sorted[0]
		Vault.RUN:
			return "a run of %d-%d-%d" % [sorted[2], sorted[1], sorted[0]]
		Vault.PAIR:
			var paired: int = sorted[1]
			var odd: int = sorted[2] if sorted[0] == sorted[1] else sorted[0]
			return "a pair of %ds and a %d" % [paired, odd]
	return "high die %d-%d-%d" % [sorted[0], sorted[1], sorted[2]]


## Why one hand beats the other, in a sentence.
static func compare_text(yours: Array[int], house: Array[int]) -> String:
	if yours.size() < 3:
		return "A hand needs 3 dice. A short hand loses."
	var mine: int = Vault.hand_rank(yours)
	var hers: int = Vault.hand_rank(house)
	if mine != hers:
		var first: Array[int] = yours if mine > hers else house
		var second: Array[int] = house if mine > hers else yours
		# "three 6s" is plural: they beat.
		var verb: String = "beat" if Vault.hand_rank(first) == Vault.THREE_KIND else "beats"
		var line: String = "Your %s %s her %s." if mine > hers else "Her %s %s your %s."
		return line % [_bare(first), verb, _bare(second)]
	var my_total: int = _total(yours)
	var her_total: int = _total(house)
	if my_total > her_total:
		return "Same rank. Your total of %d beats her %d." % [my_total, her_total]
	if my_total < her_total:
		return "Same rank. Her total of %d beats your %d." % [her_total, my_total]
	return "Same rank, same total of %d. A full tie goes to Koban." % my_total


## describe_hand without its article, for "your run of 2-3-4".
static func _bare(values: Array[int]) -> String:
	return describe_hand(values).trim_prefix("a ")


## Dice as the ladder shows them, high first: "6 6 4".
static func _dice_text(values: Array[int]) -> String:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	sorted.reverse()
	var out: PackedStringArray = []
	for v: int in sorted:
		out.append(str(v))
	return " ".join(out)


static func _total(values: Array[int]) -> int:
	var total: int = 0
	for v: int in values:
		total += v
	return total


func _resource_name(id: String) -> String:
	return str(data.row("resources", id)["name"]).to_lower() if data.has_row("resources", id) else id


## "3 pearls", "1 pearl".
func _amount(amount: int, id: String) -> String:
	var name: String = _resource_name(id)
	return "%d %s" % [amount, name.trim_suffix("s") if amount == 1 else name]


## What the big button would do now, from the vault's own rules on a
## planning copy. Keys: headline, detail.
func turn_preview() -> Dictionary:
	var copy: Vault = vault.planning_copy()
	if vault.state == Vault.State.WAGER:
		if _raise_pick.is_empty() or not copy.raise(_raise_pick):
			return {"headline": "No raise", "detail": "Stake a quarter of one resource on this round. Win it and the stake comes back doubled."}
		var amount: int = copy.stake[_raise_pick]
		# Net either way, so even money reads as even money (Mara, #31).
		return {"headline": "Raise %s: win +%d · lose −%d" % [_amount(amount, _raise_pick), amount, amount],
			"detail": "The %s leave%s your haul when you roll. Win the round and %d come back." % [_amount(amount, _raise_pick), "s" if amount == 1 else "", amount * 2]}
	var won_before: int = copy.rounds_won
	copy.end_turn()
	var won: bool = copy.rounds_won > won_before
	var parts: PackedStringArray = ["Beats Koban" if won else "Loses to Koban"]
	for id: String in vault.stake:
		parts.append("+%s back" % _amount(vault.stake[id] * 2, id) if won else "lose %s" % _amount(vault.stake[id], id))
	if copy.state == Vault.State.WON:
		parts.append("takes the vault")
	elif copy.state == Vault.State.LOST:
		parts.append("Koban takes the vault")
	return {"headline": " · ".join(parts), "detail": compare_text(vault.table.values_in(vault.hand()), vault.house_hand)}


## The hand slot's footer: what the dice in it make, or would with the held
## die added.
func slot_preview() -> Dictionary:
	if vault.state != Vault.State.PLAYER_TURN:
		return {"text": "", "tone": "ok", "fit": 0}
	var s: DiceTable.Slot = vault.hand()
	var values: Array[int] = vault.table.values_in(s)
	if _selected >= 0 and s.dice.size() >= s.max_dice():
		return {"text": "Full · " + describe_hand(values), "tone": "ok", "fit": -1}
	var fit: int = 0
	if _selected >= 0:
		var reason: String = vault.place_refusal(_selected, s.id)
		if not reason.is_empty():
			return {"text": reason, "tone": "error", "fit": -1}
		fit = 1
		values.append(vault.die(_selected).value)
	if values.is_empty():
		return {"text": "Needs 3 dice", "tone": "wait", "fit": fit}
	if values.size() < 3:
		var more: String = "needs %d more" % (3 - values.size())
		if values.size() == 2 and values[0] == values[1]:
			return {"text": "Pair of %ds · %s" % [values[0], more], "tone": "wait", "fit": fit}
		return {"text": "Needs %d more" % (3 - values.size()), "tone": "wait", "fit": fit}
	return {"text": describe_hand(values), "tone": "ok", "fit": fit}


## What happened to the round's stake: "+6 pearls back" or "Koban keeps
## your 3 pearls".
func stake_lines(stake_events: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for event: Dictionary in stake_events:
		var said: String = _amount(event["amount"] as int, str(event["resource"]))
		out.append("+%s back" % said if event["won"] else "Koban keeps your %s" % said)
	return out


## A haul's resources in the data's order: "41 driftwood, 8 pearls".
func _haul_text(haul: Haul) -> String:
	var parts: PackedStringArray = []
	for id: String in data.ids("resources"):
		if haul.resource(id) > 0:
			parts.append(_amount(haul.resource(id), id))
	return ", ".join(parts)


## The panel at the end of a round (and of the vault).
func round_text(round_event: Dictionary, stake_events: Array) -> String:
	var lines: PackedStringArray = []
	var won: bool = round_event["won"]
	lines.append("You take round %d." % round_event["round"] if won else "Koban takes round %d." % round_event["round"])
	var yours: Array[int] = []
	yours.assign(round_event["yours"] as Array)
	var house: Array[int] = []
	house.assign(round_event["house"] as Array)
	lines.append(compare_text(yours, house))
	for line: String in stake_lines(stake_events):
		lines.append(line + ".")
	# The match's end names what it means for the haul (Mara, #31).
	if vault.state == Vault.State.WON:
		var won_line: String = "You win the %s." % prize if not prize.is_empty() else "You win the vault."
		var carried: String = _haul_text(vault.haul)
		lines.append(won_line + (" Your haul: %s." % carried if not carried.is_empty() else ""))
	elif vault.state == Vault.State.LOST:
		var kept: String = _haul_text(vault.haul.halved())
		lines.append("Koban wins. You wash up in the barrel" + (" and keep half: %s." % kept if not kept.is_empty() else "."))
	return "\n".join(lines)


# --- Input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if vault == null or vault.is_over() or _panel.visible:
		return
	if event.is_action_pressed(FightBoard.COMMIT_ACTION):
		_on_verb()
	elif vault.state != Vault.State.PLAYER_TURN:
		return
	elif event.is_action_pressed(FightBoard.CONTEXT_ACTION):
		_on_nudge()
	elif event.is_action_pressed(FightBoard.REROLL_ACTION):
		_on_reroll()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _turn_open() -> bool:
	return vault.state == Vault.State.PLAYER_TURN and not _panel.visible


func _on_raise_toggled(resource_id: String) -> void:
	if vault.state != Vault.State.WAGER or _panel.visible:
		return
	_raise_pick = "" if _raise_pick == resource_id else resource_id
	_refresh()


func _on_die_pressed(die_id: int) -> void:
	if not _turn_open():
		return
	if _reroll_mode:
		var reason: String = vault.reroll_refusal(die_id)
		if not reason.is_empty():
			_say(reason, true)
			return
		_reroll_discard = die_id
		_refresh()
		return
	if not vault.die(die_id).slot_id.is_empty():
		_take_back(die_id)
		return
	_selected = -1 if _selected == die_id else die_id
	_refresh()


func _on_die_drag_started(die_id: int) -> void:
	if not _reroll_mode and _selected != die_id:
		_on_die_pressed(die_id)


func _on_die_dropped(die_id: int) -> void:
	if _reroll_mode or not vault.die(die_id).is_free():
		return
	_selected = die_id
	_on_slot_pressed()


func _on_slot_pressed() -> void:
	if not _turn_open():
		return
	if _selected < 0:
		_say("Pick a die first.", false)
		return
	var slot_id: String = vault.hand().id
	var reason: String = vault.place_refusal(_selected, slot_id)
	if not reason.is_empty():
		PlaytestLog.log_event("invalid_drop", {"die": _selected, "value": vault.die(_selected).value, "slot": slot_id, "room": "vault"})
		_card.preview_text = reason
		_card.preview_tone = "error"
		_card.queue_redraw()
		_sounds.play("invalid")
		return
	vault.place(_selected, slot_id)
	PlaytestLog.log_event("place", {"die": _selected, "slot": slot_id, "room": "vault"})
	_sounds.play("place")
	_selected = -1
	_say("", false)
	_refresh()
	_focus_first_free_die()


func _on_slot_secondary() -> void:
	var s: DiceTable.Slot = vault.hand()
	if not _turn_open() or s.dice.is_empty():
		_cancel()
		return
	_take_back(s.dice[s.dice.size() - 1])


func _take_back(die_id: int) -> void:
	if vault.take_back(die_id):
		PlaytestLog.log_event("take_back", {"die": die_id, "round": vault.round_number, "room": "vault"})
		_sounds.play("take_back")
		_refresh()


func _on_nudge() -> void:
	if not _turn_open() or vault.table.nudge_perk.is_empty():
		return
	var target: int = _selected
	if target < 0:
		var focused: DieView = get_viewport().gui_get_focus_owner() as DieView
		target = focused.die_id if focused != null else -1
	if target < 0:
		_say("Pick a die to nudge.", false)
		return
	if not vault.nudge(target):
		_say("Nudge: once a turn, on an unplaced die below 6.", true)
		return
	_refresh()


func _on_reroll() -> void:
	if not _turn_open():
		return
	if not _reroll_mode:
		if vault.table.rerolls_left <= 0:
			_say("No rerolls left this round.", true)
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
	vault.reroll(_reroll_discard)
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


## Roll (in the wager) or Play hand (in your turn).
func _on_verb() -> void:
	if _panel.visible or vault.is_over():
		return
	if vault.state == Vault.State.WAGER:
		if not _raise_pick.is_empty():
			# Never roll without the stake the preview promised (Imogen, #31).
			if not vault.raise(_raise_pick):
				_raise_pick = ""
				_say("That raise can't be made now. Pick again, or roll with no raise.", true)
				_refresh()
				return
			PlaytestLog.log_event("vault_raise", {"round": vault.round_number, "stake": vault.stake.duplicate()})
		_raise_pick = ""
		vault.roll()
		_sounds.play("roll")
		_sounds.play("land")
		_refresh()
		_focus_first_free_die()
		return
	_cancel()
	var start: int = vault.events.size()
	vault.end_turn()
	var stake_events: Array = []
	for event: Dictionary in vault.events.slice(start):
		if event["type"] == "round":
			_round_event = event
		elif event["type"] == "stake":
			stake_events.append(event)
	_round_stakes = stake_events
	_show_panel(stake_events)


func _on_continue() -> void:
	# A press meant for Play hand can't skip the result (Mara, #30).
	if Time.get_ticks_msec() < _panel_shown_at + RESULT_GUARD_MS:
		return
	if vault.is_over():
		if not _finished:
			_finished = true
			finished.emit()
		return
	_panel.visible = false
	_round_event = {}
	_round_stakes = []
	_refresh()
	_verb.grab_focus()
	_reveal_house()
	PlaytestLog.log_event("vault_round_start", {"round": vault.round_number, "house": vault.house_hand.duplicate()})


func _show_panel(stake_events: Array) -> void:
	_panel_text.text = round_text(_round_event, stake_events)
	_continue.text = "Continue" if vault.is_over() else "Next round"
	_panel.visible = true
	_panel_shown_at = Time.get_ticks_msec()
	_refresh()
	_continue.grab_focus()
	PlaytestLog.log_event("vault_round", {"round": _round_event["round"], "won": _round_event["won"],
		"yours": _round_event["yours"], "house": _round_event["house"], "over": vault.is_over()})


# --- Drawing state -----------------------------------------------------------------

## The hands to show: the finished round's while its panel is up (Koban has
## already rolled the next one), else the live ones.
func _shown_house() -> Array[int]:
	var out: Array[int] = []
	if not _round_event.is_empty():
		out.assign(_round_event["house"] as Array)
	else:
		out.assign(vault.house_hand)
	return out


func _shown_yours() -> Array[int]:
	var out: Array[int] = []
	if not _round_event.is_empty():
		out.assign(_round_event["yours"] as Array)
	elif vault.state == Vault.State.PLAYER_TURN:
		out = vault.table.values_in(vault.hand())
	return out


func _round_results() -> Array[bool]:
	var out: Array[bool] = []
	for event: Dictionary in vault.events:
		if event["type"] == "round":
			out.append(event["won"] as bool)
	return out


func _refresh() -> void:
	var wager: bool = vault.state == Vault.State.WAGER and _round_event.is_empty()
	var turn: bool = vault.state == Vault.State.PLAYER_TURN or not _round_event.is_empty()
	# The round score.
	_pips.results = _round_results()
	_pips.total = vault.rounds_to_win * 2 - 1
	_pips.current = vault.round_number - 1 if _round_event.is_empty() and not vault.is_over() else -1
	_pips.queue_redraw()
	var shown_round: int = _round_event["round"] if not _round_event.is_empty() else vault.round_number
	_round_label.text = "Round %d · You %d · Koban %d · first to %d" % [shown_round, vault.rounds_won, vault.rounds_lost, vault.rounds_to_win]

	# Both hands, and the ladder.
	var house: Array[int] = _shown_house()
	var yours: Array[int] = _shown_yours()
	_house_dice.values = house
	_house_dice.queue_redraw()
	var said: String = describe_hand(house)
	_house_text.text = said.substr(0, 1).to_upper() + said.substr(1) + " · total %d" % _total(house)
	var my_rank: int = -1
	if not yours.is_empty():
		my_rank = Vault.hand_rank(yours) if yours.size() == 3 else (Vault.PAIR if yours.size() == 2 and yours[0] == yours[1] else Vault.HIGH_DIE)
	for i: int in LADDER.size():
		var rank: int = LADDER[i][0]
		var hers: bool = Vault.hand_rank(house) == rank
		var mine: bool = turn and rank == my_rank
		_ladder_koban[i].text = "KOBAN" if hers else ""
		_ladder_you[i].text = ("YOU" if yours.size() == 3 else "YOU SO FAR") if mine else ""
		# A marked row shows the real dice, not the example (Mara, #31).
		if hers and mine:
			_ladder_dice[i].text = "her %s · your %s" % [_dice_text(house), _dice_text(yours)]
		elif hers:
			_ladder_dice[i].text = _dice_text(house)
		elif mine:
			_ladder_dice[i].text = _dice_text(yours)
		else:
			_ladder_dice[i].text = LADDER[i][2]
		_ladder_dice[i].add_theme_color_override("font_color", BoardStyle.INK if hers or mine else BoardStyle.DIM)
		_ladder_tie[i].visible = hers and mine
		var border: Color = BoardStyle.JADE if mine else (BoardStyle.AMBER if hers else BoardStyle.DIM)
		var box: StyleBoxFlat = BoardStyle.panel(border, BoardStyle.FELT if mine or hers else BoardStyle.LACQUER)
		box.set_border_width_all(4 if mine or hers else 2)
		box.content_margin_left = 16
		box.content_margin_right = 16
		_ladder_rows[i].add_theme_stylebox_override("panel", box)

	var tie_shown: bool = false
	for tie: Label in _ladder_tie:
		tie_shown = tie_shown or tie.visible
	_ladder_footer.visible = not tie_shown

	# Your hand slot.
	_card.placed_values.clear()
	if turn:
		_card.placed_values.assign(yours)
	var p: Dictionary = slot_preview()
	var footer: String = p["text"] if _round_event.is_empty() else describe_hand(yours)
	_card.preview_text = footer.substr(0, 1).to_upper() + footer.substr(1)
	_card.preview_tone = p["tone"]
	_card.held_fit = p["fit"]
	_card.held_value = vault.die(_selected).value if _selected >= 0 else 0
	_card.queue_redraw()

	# The wager, or your dice.
	# The round panel sits over the dice row and the buttons: hide them.
	_wager_box.visible = wager
	_hand_row.visible = not wager and _round_event.is_empty()
	_verbs.visible = _round_event.is_empty()
	for id: String in _raise_buttons:
		var b: Button = _raise_buttons[id]
		var amount: int = vault.raise_amount(id)
		b.visible = amount > 0
		b.text = "Raise " + _amount(amount, id)
		b.button_pressed = _raise_pick == id
	if not _round_event.is_empty():
		var settled: PackedStringArray = stake_lines(_round_stakes)
		_stake_label.text = "\n".join(settled) if not settled.is_empty() else "No raise this round"
	elif vault.stake.is_empty():
		_stake_label.text = "No raise this round" if not wager else "Nothing staked yet"
	else:
		var staked: PackedStringArray = []
		for id: String in vault.stake:
			staked.append(_amount(vault.stake[id], id))
		_stake_label.text = "At stake: " + ", ".join(staked)
	for view: DieView in _dice:
		var d: DiceTable.Die = vault.die(view.die_id)
		view.value = d.value
		view.locked = d.locked
		view.discarded = d.discarded
		view.selected = view.die_id == _selected or view.die_id == _reroll_discard
		view.placed = not d.slot_id.is_empty()
		view.placed_order = 1 if view.placed else 0

	# The big button.
	var t: Dictionary = turn_preview() if _round_event.is_empty() and not vault.is_over() else {"headline": "", "detail": ""}
	_preview.text = t["headline"]
	_detail.text = t["detail"]
	_verb.text = "Roll" if wager else "Play hand"
	_verb.disabled = vault.is_over() or not _round_event.is_empty()
	_reroll.visible = not wager and vault.table.rerolls_per_turn > 0
	_reroll.disabled = vault.table.rerolls_left <= 0 and not _reroll_mode
	if _reroll_mode:
		_reroll.text = "Confirm: discard %d, reroll the rest" % vault.die(_reroll_discard).value if _reroll_discard >= 0 else "Pick a die to discard"
	else:
		_reroll.text = "Reroll (%d left)" % vault.table.rerolls_left
	var nudger: String = vault.table.nudge_source
	_nudge.visible = not wager and not vault.table.nudge_perk.is_empty()
	_nudge.disabled = vault.table.nudges_left <= 0
	var nudger_name: String = str(data.row("villagers", nudger)["role"]) if data.has_row("villagers", nudger) else nudger
	_nudge.text = "Nudge +1 · %s" % nudger_name if vault.table.nudges_left > 0 else "Nudge used · %s" % nudger_name
	_nudge_chip.villager_id = nudger
	_nudge_chip.role = nudger_name
	_nudge_chip.dimmed = vault.table.nudges_left <= 0


func _say(text: String, is_error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", BoardStyle.DANGER if is_error else BoardStyle.INK)


func _focus_first_free_die() -> void:
	for view: DieView in _dice:
		if not view.placed and not view.discarded:
			view.grab_focus()
			return
	_verb.grab_focus()


# --- Layout --------------------------------------------------------------------

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
	margin.add_theme_constant_override("margin_top", 28 + top_inset)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	# Title, the rules in a line, and the round score.
	# The map's vault node has a double gold rim; so does the vault's header,
	# so it reads as the finale (Mara, #31).
	var rim: PanelContainer = PanelContainer.new()
	var rim_box: StyleBoxFlat = BoardStyle.panel(BoardStyle.GOLD, BoardStyle.BACKGROUND)
	rim_box.set_content_margin_all(6)
	rim.add_theme_stylebox_override("panel", rim_box)
	column.add_child(rim)
	var head: PanelContainer = PanelContainer.new()
	head.add_theme_stylebox_override("panel", BoardStyle.panel())
	rim.add_child(head)
	var head_inner: HBoxContainer = HBoxContainer.new()
	head_inner.add_theme_constant_override("separation", 32)
	head.add_child(head_inner)
	var head_text: VBoxContainer = VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_inner.add_child(head_text)
	var title: Label = BoardStyle.label("Koban's vault" + (" · the %s" % prize if not prize.is_empty() else ""), BoardStyle.NUMBER, BoardStyle.GOLD)
	title.add_theme_font_override("font", BoardStyle.title_font())
	head_text.add_child(title)
	head_text.add_child(BoardStyle.label(INTRO, BoardStyle.BODY, BoardStyle.INK))
	var score: VBoxContainer = VBoxContainer.new()
	score.alignment = BoxContainer.ALIGNMENT_CENTER
	head_inner.add_child(score)
	_pips = PipsView.new()
	_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	score.add_child(_pips)
	_round_label = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.INK)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_child(_round_label)

	# Koban's hand, the ladder, and yours.
	var middle: HBoxContainer = HBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_theme_constant_override("separation", 32)
	column.add_child(middle)
	var house_panel: PanelContainer = PanelContainer.new()
	house_panel.add_theme_stylebox_override("panel", BoardStyle.panel(BoardStyle.AMBER))
	house_panel.custom_minimum_size = Vector2(460, 388)
	middle.add_child(house_panel)
	var house_box: VBoxContainer = VBoxContainer.new()
	house_box.add_theme_constant_override("separation", 16)
	house_panel.add_child(house_box)
	house_box.add_child(BoardStyle.label("Koban's hand", BoardStyle.NUMBER, BoardStyle.AMBER))
	_house_dice = HouseDice.new()
	_house_dice.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	house_box.add_child(_house_dice)
	_house_text = BoardStyle.label("", BoardStyle.BODY, BoardStyle.INK)
	_house_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_house_text.custom_minimum_size = Vector2(420, 0)
	house_box.add_child(_house_text)
	house_box.add_child(BoardStyle.label("She rolls first, in the open.", BoardStyle.SMALL, BoardStyle.DIM))

	var ladder: VBoxContainer = VBoxContainer.new()
	ladder.add_theme_constant_override("separation", 8)
	ladder.custom_minimum_size = Vector2(720, 0)
	middle.add_child(ladder)
	ladder.add_child(BoardStyle.label("Best hand wins", BoardStyle.BODY, BoardStyle.GOLD))
	for entry: Array in LADDER:
		var row: PanelContainer = PanelContainer.new()
		row.custom_minimum_size = Vector2(720, 66)
		ladder.add_child(row)
		_ladder_rows.append(row)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(stack)
		var inner: HBoxContainer = HBoxContainer.new()
		inner.add_theme_constant_override("separation", 12)
		stack.add_child(inner)
		var koban_tag: Label = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.AMBER)
		koban_tag.add_theme_font_override("font", BoardStyle.strong_font())
		koban_tag.custom_minimum_size = Vector2(80, 0)
		inner.add_child(koban_tag)
		_ladder_koban.append(koban_tag)
		var name_label: Label = BoardStyle.label(entry[1], BoardStyle.BODY, BoardStyle.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(name_label)
		var dice_label: Label = BoardStyle.label(entry[2], BoardStyle.SMALL, BoardStyle.DIM)
		inner.add_child(dice_label)
		_ladder_dice.append(dice_label)
		var you_tag: Label = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.JADE)
		you_tag.add_theme_font_override("font", BoardStyle.strong_font())
		you_tag.custom_minimum_size = Vector2(130, 0)
		you_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		inner.add_child(you_tag)
		_ladder_you.append(you_tag)
		# On the row itself when both hands share it: her house edge (Mara, #31).
		var tie: Label = BoardStyle.label("Same rank · higher total wins · ties go to Koban", BoardStyle.SMALL, BoardStyle.AMBER)
		tie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tie.visible = false
		stack.add_child(tie)
		_ladder_tie.append(tie)
	_ladder_footer = BoardStyle.label("Same rank: the higher total wins. A full tie goes to Koban.", BoardStyle.SMALL, BoardStyle.DIM)
	ladder.add_child(_ladder_footer)

	var s: DiceTable.Slot = vault.hand()
	_card = SlotCard.new()
	_card.slot_id = s.id
	_card.order = 1
	_card.title = str(s.row["name"])
	_card.rule_text = str(s.row["text"])
	_card.sockets = s.max_dice()
	_card.pressed.connect(_on_slot_pressed)
	_card.secondary_pressed.connect(_on_slot_secondary)
	_card.die_dropped.connect(_on_die_dropped)
	middle.add_child(_card)

	_message = BoardStyle.label("", BoardStyle.BODY)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(0, 36)
	column.add_child(_message)

	# The wager (before the roll) or your dice, then the big button.
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 40)
	column.add_child(bottom)
	var stake_panel: PanelContainer = PanelContainer.new()
	stake_panel.add_theme_stylebox_override("panel", BoardStyle.panel(BoardStyle.JADE))
	stake_panel.custom_minimum_size = Vector2(300, 0)
	bottom.add_child(stake_panel)
	var stake_box: VBoxContainer = VBoxContainer.new()
	stake_panel.add_child(stake_box)
	stake_box.add_child(BoardStyle.label("You", BoardStyle.BODY, BoardStyle.JADE))
	_stake_label = BoardStyle.label("", BoardStyle.BODY)
	_stake_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stake_label.custom_minimum_size = Vector2(260, 0)
	stake_box.add_child(_stake_label)

	var middle_bottom: Control = Control.new()
	middle_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_bottom.custom_minimum_size = Vector2(0, 170)
	bottom.add_child(middle_bottom)
	_wager_box = VBoxContainer.new()
	_wager_box.add_theme_constant_override("separation", 12)
	middle_bottom.add_child(_wager_box)
	_wager_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wager_box.add_child(BoardStyle.label("Raise before you roll? Optional.", BoardStyle.BODY, BoardStyle.INK))
	var raise_row: HBoxContainer = HBoxContainer.new()
	raise_row.add_theme_constant_override("separation", 12)
	_wager_box.add_child(raise_row)
	for id: String in data.ids("resources"):
		var b: Button = RoomBoard._button("", 72)
		b.toggle_mode = true
		var picked: StyleBoxFlat = BoardStyle.panel(BoardStyle.JADE, BoardStyle.FELT)
		picked.set_border_width_all(5)
		picked.set_content_margin_all(8)
		b.add_theme_stylebox_override("pressed", picked)
		b.pressed.connect(_on_raise_toggled.bind(id))
		raise_row.add_child(b)
		_raise_buttons[id] = b
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override("separation", 20)
	middle_bottom.add_child(_hand_row)
	_hand_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for d: DiceTable.Die in vault.table.hand:
		var view: DieView = DieView.new()
		view.die_id = d.id
		view.custom_minimum_size = Vector2(150, 150)
		view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		view.pressed.connect(_on_die_pressed.bind(d.id))
		view.secondary_pressed.connect(_cancel)
		view.drag_started.connect(_on_die_drag_started.bind(d.id))
		_hand_row.add_child(view)
		_dice.append(view)

	var verbs: VBoxContainer = VBoxContainer.new()
	_verbs = verbs
	verbs.custom_minimum_size = Vector2(560, 0)
	verbs.add_theme_constant_override("separation", 10)
	bottom.add_child(verbs)
	_preview = BoardStyle.label("", BoardStyle.NUMBER, BoardStyle.INK)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(560, 0)
	verbs.add_child(_preview)
	_detail = BoardStyle.label("", BoardStyle.SMALL, BoardStyle.DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(560, 0)
	verbs.add_child(_detail)
	var verb_row: HBoxContainer = HBoxContainer.new()
	verb_row.add_theme_constant_override("separation", 12)
	verbs.add_child(verb_row)
	_nudge = RoomBoard._button("Nudge +1", 0)
	_nudge.pressed.connect(_on_nudge)
	verb_row.add_child(_nudge)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		(_nudge.get_theme_stylebox(state) as StyleBoxFlat).content_margin_left = 60
	_nudge_chip = FaceChip.new()
	_nudge.add_child(_nudge_chip)
	_nudge_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_KEEP_SIZE, 10)
	_reroll = RoomBoard._button("Reroll", 0)
	_reroll.pressed.connect(_on_reroll)
	verb_row.add_child(_reroll)
	_verb = RoomBoard._button("Roll", 80, true)
	_verb.pressed.connect(_on_verb)
	verbs.add_child(_verb)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", BoardStyle.panel())
	_panel.visible = false
	add_child(_panel)
	# Over the dice row, so both hands and the ladder stay in view.
	_panel.custom_minimum_size = Vector2(820, 0)
	_panel.position = Vector2(550, 640 + top_inset)
	var panel_box: VBoxContainer = VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 20)
	_panel.add_child(panel_box)
	_panel_text = BoardStyle.label("", BoardStyle.NUMBER)
	_panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_text.custom_minimum_size = Vector2(780, 0)
	panel_box.add_child(_panel_text)
	_continue = RoomBoard._button("Next round", 72)
	_continue.pressed.connect(_on_continue)
	panel_box.add_child(_continue)
