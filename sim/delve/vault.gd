class_name Vault
extends RefCounted
## Koban's vault: Beat the House (specs/delve-map.md section 6 and 8a rule
## 3). A best-of-3 of poker dice against her open hand, with a wager.
##
## Each round:
##   1. Koban rolls her house dice openly (ENEMIES stream). The vault waits
##      in WAGER: you may raise() once, staking part of one haul resource.
##   2. roll() rolls your kit (ROLLS stream) and starts your turn, with the
##      usual reroll and nudge. Place 3 dice in the hand slot.
##   3. end_turn() scores both hands: three of a kind > run > pair > high
##      die. Within a rank the higher triple, run, pair or high die wins,
##      then the odd die (or the next die), then the sum, and the house
##      wins a full tie (poker order, Vanta's call). A hand slot
##      that isn't full loses. Win the round and the haul gets back twice
##      the stake; lose it and the stake is gone.
## First to rounds_to_win takes the vault: WON or LOST.
##
## The vault works on the run's haul (the same object), so every stake
## leaves it on the way in and only what's won comes back. Banking (and
## halving after a loss) happens after the last stake has resolved.
##
## Every move is logged in `moves`; the seed's streams plus the moves
## replay the vault, as for a fight.
##
## planning_copy() gives the board a vault to preview on (Imogen, #27): no
## RNG, and its own Haul, so a preview can't roll or touch the run's haul.

enum State { WAGER, PLAYER_TURN, WON, LOST }

const NUDGE_PERK: String = "nudge"
## Hand ranks, low to high.
const HIGH_DIE: int = 0
const PAIR: int = 1
const RUN: int = 2
const THREE_KIND: int = 3
const RANK_NAMES: Array[String] = ["high die", "pair", "run", "three of a kind"]
## hand_score packs, high bits to low: the rank, the group (the triple's
## face, a run's top die, the pair's face, or the high die), the kicker
## (the odd die beside a pair, or a high die's second die), then the sum.
## Faces fit in 8 bits (GameData checks MAX_FACE) and the sum in 10.
const MAX_FACE: int = 255
const KICKER_SHIFT: int = 10
const GROUP_SHIFT: int = 18
const RANK_SHIFT: int = 26

const Die = DiceTable.Die
const Slot = DiceTable.Slot

var state: State = State.WAGER
var round_number: int = 0
var rounds_to_win: int = 2
var rounds_won: int = 0
var rounds_lost: int = 0
## Koban's dice this round, as rolled.
var house_hand: Array[int] = []
## This round's stake: {resource id: amount}, or {} before a raise.
var stake: Dictionary[String, int] = {}
var raise_divisor: int = 4
## Nudges a whole vault allows (Koban's table, Koban's rules), from
## vaults.json: not one a round. Fights keep their nudge every turn.
var nudges_per_vault: int = 1
var nudges_used: int = 0

## The run's haul (shared): stakes come out of it and winnings go back in.
var haul: Haul
var table: DiceTable
var events: Array[Dictionary] = []
var moves: Array[Dictionary] = []

var _house_faces: Array[Array] = []
var _rng: RngStreams
var _hand_slot: String = ""
## True on planning copies: end_turn scores the round, settles the stake on
## the copy's own haul and stops there, once.
var _is_preview: bool = false
var _preview_spent: bool = false


## Opens the vault on `haul` (the run's own Haul), with the kit's dice
## (Kit.die_specs) less any added die. Returns null if the data is missing.
static func create(data: GameData, loadout_id: String, vault_id: String, rng: RngStreams,
		perks: Array[Dictionary], run_haul: Haul, dice: Array = []) -> Vault:
	if not can_open(data, loadout_id, vault_id) or run_haul == null:
		return null
	var vault_row: Dictionary = data.row("vaults", vault_id)
	var loadout: Dictionary = data.row("loadouts", loadout_id)
	var vault: Vault = Vault.new()
	# An added die (the Spare die) sits out: best 3 of 5 would beat best 3
	# of 4 on every seed, a flat increase (Imogen's #49 audit).
	var played: Array = dice.filter(func(spec: Variant) -> bool:
		return not (spec is Dictionary and bool((spec as Dictionary).get("added", false))))
	vault.table = DiceTable.create(data, played if not played.is_empty() else loadout["dice"] as Array,
		vault_row["slots"] as Array, rng)
	if vault.table == null:
		return null
	for die_id: Variant in vault_row["house_dice"] as Array:
		if not data.has_row("dice", str(die_id)):
			return null
		vault._house_faces.append(data.row("dice", str(die_id))["faces"] as Array)
	vault._rng = rng
	vault._hand_slot = str((vault_row["slots"] as Array)[0])
	vault.haul = run_haul
	vault.table.events = vault.events
	vault.table.moves = vault.moves
	vault.table.rerolls_per_turn = vault_row["rerolls_per_turn"] as int
	vault.rounds_to_win = vault_row["rounds_to_win"] as int
	vault.raise_divisor = vault_row["raise_divisor"] as int
	vault.nudges_per_vault = vault_row["nudges_per_vault"] as int
	for entry: Dictionary in perks:
		if str(entry.get("perk", "")) == NUDGE_PERK and data.has_row("perks", NUDGE_PERK):
			var nudge_row: Dictionary = data.row("perks", NUDGE_PERK)
			vault.table.nudge_perk = NUDGE_PERK
			vault.table.nudge_source = str(entry.get("source", ""))
			vault.table.nudge_amount = int(entry.get("amount", nudge_row["amount"]))
			vault.table.nudge_uses_per_turn = int(entry.get("uses_per_turn", nudge_row["uses_per_turn"]))
			# A happy pearl diver's extra nudge counts in the vault too
			# (Imogen's #49 audit, option a): the vault's allowance grows by it.
			vault.nudges_per_vault += maxi(0, vault.table.nudge_uses_per_turn - int(nudge_row["uses_per_turn"]))
			break
	vault._start_round()
	return vault


## Whether `data` has everything create() needs, without drawing
## anything, so the run can refuse to step into a vault that can't open.
static func can_open(data: GameData, loadout_id: String, vault_id: String) -> bool:
	if not data.has_row("loadouts", loadout_id) or not data.has_row("vaults", vault_id):
		return false
	var vault_row: Dictionary = data.row("vaults", vault_id)
	for slot_id: Variant in vault_row["slots"] as Array:
		if not data.has_row("slots", str(slot_id)):
			return false
	for die_id: Variant in (vault_row["house_dice"] as Array) + (data.row("loadouts", loadout_id)["dice"] as Array):
		if not data.has_row("dice", str(die_id)):
			return false
	return (vault_row["slots"] as Array).size() == 1


## Poker-dice score for comparing hands, in poker order: rank, then group,
## then kicker, then the sum (hand_parts), each in its own bits so a big
## face can't leak into the field above. Three dice only; anything else
## scores -1 (an unfilled hand loses).
static func hand_score(values: Array[int]) -> int:
	if values.size() != 3:
		return -1
	var parts: Array[int] = hand_parts(values)
	return (parts[0] << RANK_SHIFT) | (parts[1] << GROUP_SHIFT) | (parts[2] << KICKER_SHIFT) \
		| (values[0] + values[1] + values[2])


## [rank, group, kicker] for three dice: three 5s are [THREE_KIND, 5, 0],
## a run of 3-4-5 [RUN, 5, 0], a pair of 4s and a 6 [PAIR, 4, 6], and high
## die 6-4-2 [HIGH_DIE, 6, 4].
static func hand_parts(values: Array[int]) -> Array[int]:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var rank: int = hand_rank(sorted)
	match rank:
		THREE_KIND:
			return [rank, sorted[0], 0]
		RUN:
			return [rank, sorted[2], 0]
		PAIR:
			return [rank, sorted[1], sorted[2] if sorted[0] == sorted[1] else sorted[0]]
	return [rank, sorted[2], sorted[1]]


static func hand_rank(values: Array[int]) -> int:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	if sorted[0] == sorted[2]:
		return THREE_KIND
	if sorted[1] == sorted[0] + 1 and sorted[2] == sorted[1] + 1:
		return RUN
	if sorted[0] == sorted[1] or sorted[1] == sorted[2]:
		return PAIR
	return HIGH_DIE


func is_over() -> bool:
	return state == State.WON or state == State.LOST


func hand() -> Slot:
	return table.slot(_hand_slot)


func die(die_id: int) -> Die:
	return table.die(die_id)


## How much a raise on `resource_id` would stake now, or 0 if it can't.
func raise_amount(resource_id: String) -> int:
	if state != State.WAGER or not stake.is_empty() or haul.resource(resource_id) < 1:
		return 0
	return maxi(1, haul.resource(resource_id) / raise_divisor)


## Stakes part of one haul resource on this round. Once a round.
func raise(resource_id: String) -> bool:
	var amount: int = raise_amount(resource_id)
	if amount <= 0 or not haul.take_resource(resource_id, amount):
		return false
	stake[resource_id] = amount
	events.append({"type": "raise", "resource": resource_id, "amount": amount})
	moves.append({"move": "raise", "resource": resource_id})
	return true


## Ends the wager and rolls your dice. A planning copy can't roll.
func roll() -> bool:
	if state != State.WAGER or _rng == null:
		return false
	moves.append({"move": "roll"})
	state = State.PLAYER_TURN
	table.reset_turn()
	table.nudges_left = mini(table.nudges_left, maxi(0, nudges_per_vault - nudges_used))
	var values: Array[int] = table.roll_hand()
	events.append({"type": "turn_start", "round": round_number, "values": values})
	return true


## Why `die_id` can't go in `slot_id` now, or "" if it can.
func place_refusal(die_id: int, slot_id: String) -> String:
	if state != State.PLAYER_TURN:
		return "Roll first."
	return table.place_refusal(die_id, slot_id)


func place(die_id: int, slot_id: String) -> bool:
	return state == State.PLAYER_TURN and table.place(die_id, slot_id)


func take_back(die_id: int) -> bool:
	return state == State.PLAYER_TURN and table.take_back(die_id)


## Why rerolling by discarding `discard_id` isn't allowed, or "" if it is.
func reroll_refusal(discard_id: int) -> String:
	if state != State.PLAYER_TURN:
		return "Roll first."
	return table.reroll_refusal(discard_id)


func reroll(discard_id: int) -> bool:
	return state == State.PLAYER_TURN and table.reroll(discard_id)


func nudge(die_id: int) -> bool:
	if state != State.PLAYER_TURN or not table.nudge(die_id):
		return false
	nudges_used += 1
	return true


## Scores the round, settles the stake, and starts the next round or ends
## the vault.
func end_turn() -> bool:
	if state != State.PLAYER_TURN or _preview_spent:
		return false
	if _is_preview:
		_preview_spent = true
	else:
		moves.append({"move": "end_turn"})
	var yours: Array[int] = table.values_in(hand())
	var won: bool = hand_score(yours) > hand_score(house_hand)
	events.append({"type": "round", "round": round_number, "won": won, "yours": yours, "house": house_hand.duplicate()})
	for id: String in stake:
		if won:
			haul.add_resource(id, stake[id] * 2)
			events.append({"type": "stake", "resource": id, "amount": stake[id] * 2, "won": true})
		else:
			events.append({"type": "stake", "resource": id, "amount": stake[id], "won": false})
	stake = {}
	if won:
		rounds_won += 1
	else:
		rounds_lost += 1
	if rounds_won >= rounds_to_win:
		state = State.WON
		events.append({"type": "won"})
	elif rounds_lost >= rounds_to_win:
		state = State.LOST
		events.append({"type": "lost"})
	elif _is_preview:
		# Scored; the next round would need Koban's roll, which a copy can't make.
		state = State.WAGER
	else:
		_start_round()
	return true


## A copy to plan on (Imogen, #27): no RNG, so it can't roll, reroll or
## start the next round, and its own copy of the haul, so a preview raise
## or stake never touches the run's. Its end_turn settles the round on that
## copy and stops, once.
func planning_copy() -> Vault:
	var copy: Vault = Vault.new()
	copy._is_preview = true
	copy.state = state
	copy.round_number = round_number
	copy.rounds_to_win = rounds_to_win
	copy.rounds_won = rounds_won
	copy.rounds_lost = rounds_lost
	copy.house_hand = house_hand.duplicate()
	copy.stake = stake.duplicate()
	copy.raise_divisor = raise_divisor
	copy.nudges_per_vault = nudges_per_vault
	copy.nudges_used = nudges_used
	copy.haul = haul.copy()
	copy.table = table.copy(copy.events, copy.moves)
	copy._hand_slot = _hand_slot
	return copy


## Replays a move log. Returns false at the first move the vault refuses.
func apply_moves(log_moves: Array[Dictionary]) -> bool:
	for entry: Dictionary in log_moves:
		var ok: bool = false
		match str(entry.get("move", "")):
			"raise":
				ok = raise(str(entry.get("resource", "")))
			"roll":
				ok = roll()
			"place":
				ok = place(int(entry.get("die", -1)), str(entry.get("slot", "")))
			"take_back":
				ok = take_back(int(entry.get("die", -1)))
			"reroll":
				ok = reroll(int(entry.get("die", -1)))
			"nudge":
				ok = nudge(int(entry.get("die", -1)))
			"end_turn":
				ok = end_turn()
		if not ok:
			return false
	return true


func _start_round() -> void:
	round_number += 1
	state = State.WAGER
	house_hand.clear()
	for faces: Array in _house_faces:
		house_hand.append(faces[_rng.index(RngStreams.Stream.ENEMIES, faces.size())] as int)
	events.append({"type": "house_roll", "round": round_number, "values": house_hand.duplicate(),
		"rank": RANK_NAMES[hand_rank(house_hand)]})
