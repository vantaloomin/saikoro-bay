class_name DiceTable
extends RefCounted
## The dice half of any room that's played with dice: a hand, a row of
## slots, and the moves on them (place, take back, reroll, nudge). A fight
## owns one, and so will treasure, rest and rescue rooms, so the rules for
## those moves live in one place.
##
## The table owns all dice state: the hand, what's in each slot, and the
## per-turn counters. Its owner owns everything else (HP, the enemy, what a
## slot does when it resolves) and decides when a turn starts and ends.
##
## One log per room: the table appends to the owner's `events` and `moves`
## arrays (passed in by reference), so table moves and room moves interleave
## in a single ordered sequence.
##
## Rule hooks are data, not names: the owner picks a lock policy (the House
## lock is LOCK_HIGHEST_FREE) and the nudge amount, so the table never checks
## which enemy or perk asked for them.
##
## Randomness: rolls use the ROLLS stream only. A copy has no streams, so it
## can't reroll or peek at a future roll.

## Which die, if any, the owner's lock rule locks after each roll.
enum LockPolicy { NONE, LOCK_HIGHEST_FREE }


class Die:
	extends RefCounted
	var id: int = 0
	var type_id: String = ""
	var faces: Array[int] = []
	var value: int = 0
	## The lock policy stops this die being placed this turn.
	var locked: bool = false
	## Spent to pay for a reroll this turn.
	var discarded: bool = false
	## Slot it's planned for this turn, or "".
	var slot_id: String = ""

	func max_face() -> int:
		return faces.max() as int

	func is_free() -> bool:
		return slot_id.is_empty() and not discarded


class Slot:
	extends RefCounted
	var id: String = ""
	var row: Dictionary = {}
	var dice: Array[int] = []

	## Fewest dice the slot fires with.
	func min_dice() -> int:
		return row["min_dice"] as int

	## Most dice it takes; place refuses once it's reached.
	func max_dice() -> int:
		return row["max_dice"] as int

	## Enough dice to fire. Each die's rule is checked as it goes in.
	func is_complete() -> bool:
		return dice.size() >= min_dice()


var hand: Array[Die] = []
var slots: Array[Slot] = []
var rerolls_left: int = 0
var nudges_left: int = 0

var rerolls_per_turn: int = 0
var lock_policy: LockPolicy = LockPolicy.NONE
## Named in the lock's event ({"type": "twist", "twist": lock_source}).
var lock_source: String = ""
## The nudge perk: uses per turn (0 = none), how far it raises a die, and
## who granted it, for the event's source badge.
var nudge_uses_per_turn: int = 0
var nudge_amount: int = 0
var nudge_perk: String = ""
var nudge_source: String = ""

## The owner's logs, shared by reference.
var events: Array[Dictionary] = []
var moves: Array[Dictionary] = []

var _rng: RngStreams


## A table with the loadout's dice and slots. Returns null if `data` lacks
## any of them.
static func create(data: GameData, dice_ids: Array, slot_ids: Array, rng: RngStreams) -> DiceTable:
	var table: DiceTable = DiceTable.new()
	table._rng = rng
	var index: int = 0
	for type_id: Variant in dice_ids:
		if not data.has_row("dice", str(type_id)):
			return null
		var d: Die = Die.new()
		d.id = index
		d.type_id = type_id as String
		d.faces.assign(data.row("dice", type_id as String)["faces"] as Array)
		d.faces.make_read_only()
		table.hand.append(d)
		index += 1
	for slot_ref: Variant in slot_ids:
		if not data.has_row("slots", str(slot_ref)):
			return null
		var s: Slot = Slot.new()
		s.id = slot_ref as String
		s.row = data.row("slots", slot_ref as String)
		table.slots.append(s)
	return table


func die(die_id: int) -> Die:
	return hand[die_id] if die_id >= 0 and die_id < hand.size() else null


func slot(slot_id: String) -> Slot:
	for candidate: Slot in slots:
		if candidate.id == slot_id:
			return candidate
	return null


func can_roll() -> bool:
	return _rng != null


# --- Turn -----------------------------------------------------------------------

## Empties the slots and resets the per-turn counters. Doesn't roll.
func reset_turn() -> void:
	rerolls_left = rerolls_per_turn
	nudges_left = nudge_uses_per_turn
	for s: Slot in slots:
		s.dice.clear()


## Rolls every die in die-id order and returns the values. The owner logs
## the turn start, then calls apply_lock().
func roll_hand() -> Array[int]:
	var values: Array[int] = []
	for d: Die in hand:
		d.slot_id = ""
		d.discarded = false
		d.locked = false
		d.value = _roll(d)
		values.append(d.value)
	return values


## Runs the lock policy: after the roll and after a reroll, never after a
## nudge. LOCK_HIGHEST_FREE locks the highest free die, lowest id on ties.
func apply_lock() -> void:
	if lock_policy == LockPolicy.NONE:
		return
	var highest: Die = null
	for d: Die in hand:
		d.locked = false
	for d: Die in hand:
		if d.is_free() and (highest == null or d.value > highest.value):
			highest = d
	if highest != null:
		highest.locked = true
		events.append({"type": "twist", "twist": lock_source, "die": highest.id})


# --- Moves ----------------------------------------------------------------------

## Why `die_id` can't go in `slot_id`, or "" if it can. The owner checks
## first whether moves are allowed at all.
func place_refusal(die_id: int, slot_id: String) -> String:
	var d: Die = die(die_id)
	var s: Slot = slot(slot_id)
	if d == null or s == null:
		return "No such die or slot."
	if d.discarded:
		return "That die was spent on a reroll."
	if not d.slot_id.is_empty():
		return "That die is already placed."
	if d.locked:
		return "House lock: this die is locked this turn."
	if s.dice.size() >= s.max_dice():
		return "This slot is full."
	match s.row["accepts"] as String:
		"range":
			if d.value < (s.row["min"] as int) or d.value > (s.row["max"] as int):
				return "Needs %d to %d." % [s.row["min"], s.row["max"]]
		"even":
			if d.value % 2 != 0:
				return "Needs an even number."
		"odd":
			if d.value % 2 == 0:
				return "Needs an odd number."
		"exact":
			if d.value != (s.row["min"] as int):
				return "Needs exactly %d." % s.row["min"]
		"pair":
			if not s.dice.is_empty() and hand[s.dice[0]].value != d.value:
				return "Needs a %d to match." % hand[s.dice[0]].value
	return ""


func place(die_id: int, slot_id: String) -> bool:
	if not place_refusal(die_id, slot_id).is_empty():
		return false
	hand[die_id].slot_id = slot_id
	slot(slot_id).dice.append(die_id)
	events.append({"type": "place", "die": die_id, "slot": slot_id})
	moves.append({"move": "place", "die": die_id, "slot": slot_id})
	return true


## Returns a placed die to the hand. Free, any number of times.
func take_back(die_id: int) -> bool:
	var d: Die = die(die_id)
	if d == null or d.slot_id.is_empty():
		return false
	slot(d.slot_id).dice.erase(die_id)
	events.append({"type": "take_back", "die": die_id, "slot": d.slot_id})
	moves.append({"move": "take_back", "die": die_id})
	d.slot_id = ""
	return true


## Why rerolling by discarding `discard_id` isn't allowed, or "" if it is.
func reroll_refusal(discard_id: int) -> String:
	var d: Die = die(discard_id)
	if rerolls_left <= 0:
		return "No rerolls left this turn."
	if d == null or not d.is_free():
		return "Pick an unplaced die to discard."
	if d.locked:
		return "A locked die can't pay for a reroll."
	if _rng == null:
		return "Planning copies can't reroll."
	if rerollable_count() < 2:
		return "Nothing left to reroll."
	return ""


## Spends `discard_id` to reroll every other free, unlocked die, in die-id
## order. The lock policy then runs again.
func reroll(discard_id: int) -> bool:
	if not reroll_refusal(discard_id).is_empty():
		return false
	rerolls_left -= 1
	hand[discard_id].discarded = true
	var rerolled: Array[int] = []
	for other: Die in hand:
		if other.is_free() and not other.locked:
			other.value = _roll(other)
			rerolled.append(other.id)
	events.append({"type": "reroll", "discarded": discard_id, "dice": rerolled})
	moves.append({"move": "reroll", "die": discard_id})
	apply_lock()
	return true


## The nudge perk: +nudge_amount to a free die, up to its highest face.
func nudge(die_id: int) -> bool:
	var d: Die = die(die_id)
	if nudges_left <= 0:
		return false
	if d == null or not d.is_free() or d.locked or d.value >= d.max_face():
		return false
	nudges_left -= 1
	d.value = mini(d.value + nudge_amount, d.max_face())
	events.append({"type": "perk", "perk": nudge_perk, "source": nudge_source, "die": die_id, "amount": nudge_amount})
	moves.append({"move": "nudge", "die": die_id})
	return true


# --- Reading the table ------------------------------------------------------------

## The values of the dice in `s`, in the order they went in.
func values_in(s: Slot) -> Array[int]:
	var values: Array[int] = []
	for placed: int in s.dice:
		values.append(hand[placed].value)
	return values


## Dice that do nothing this turn: not discarded, and not in a complete slot.
func unused_dice() -> Array[Die]:
	var unused: Array[Die] = []
	for d: Die in hand:
		if d.discarded:
			continue
		if d.slot_id.is_empty() or not slot(d.slot_id).is_complete():
			unused.append(d)
	return unused


## Free, unlocked dice other than `except_id` showing `value`.
func matching_free_dice(except_id: int, value: int) -> int:
	var count: int = 0
	for d: Die in hand:
		if d.id != except_id and d.is_free() and not d.locked and d.value == value:
			count += 1
	return count


func rerollable_count() -> int:
	var count: int = 0
	for d: Die in hand:
		if d.is_free() and not d.locked:
			count += 1
	return count


## A slot's amount for these dice values: total x mult + add, never below 0.
static func amount(s: Slot, values: Array[int]) -> int:
	var total: int = 0
	for v: int in values:
		total += v
	return maxi(0, total * (s.row["mult"] as int) + (s.row["add"] as int))


## A deep copy with no RNG, logging into `into_events` and `into_moves`.
func copy(into_events: Array[Dictionary], into_moves: Array[Dictionary]) -> DiceTable:
	var t: DiceTable = DiceTable.new()
	t.rerolls_left = rerolls_left
	t.nudges_left = nudges_left
	t.rerolls_per_turn = rerolls_per_turn
	t.lock_policy = lock_policy
	t.lock_source = lock_source
	t.nudge_uses_per_turn = nudge_uses_per_turn
	t.nudge_amount = nudge_amount
	t.nudge_perk = nudge_perk
	t.nudge_source = nudge_source
	t.events = into_events
	t.moves = into_moves
	for d: Die in hand:
		var dd: Die = Die.new()
		dd.id = d.id
		dd.type_id = d.type_id
		dd.faces = d.faces
		dd.value = d.value
		dd.locked = d.locked
		dd.discarded = d.discarded
		dd.slot_id = d.slot_id
		t.hand.append(dd)
	for s: Slot in slots:
		var ss: Slot = Slot.new()
		ss.id = s.id
		ss.row = s.row
		ss.dice = s.dice.duplicate()
		t.slots.append(ss)
	return t


func _roll(d: Die) -> int:
	return d.faces[_rng.index(RngStreams.Stream.ROLLS, d.faces.size())]
