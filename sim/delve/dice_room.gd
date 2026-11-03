class_name DiceRoom
extends RefCounted
## A delve room played with your dice that isn't a fight: treasure, rest and
## rescue (specs/delve-map.md section 3). Its rules come from a dice_rooms
## row: which slots it has, how many turns it lasts, its rerolls, whether
## every slot must open (the rescue cage) and the tide damage while it
## hasn't.
##
## The moves are a fight's: place, take_back, reroll and nudge go to the
## DiceTable, and end_turn() commits the turn (the board calls it Open, or
## Soak). Each returns false and changes nothing when it isn't allowed.
##
## end_turn() runs one fixed pipeline:
##   1. complete slots that aren't already open resolve in card order:
##      heal (capped at max HP), resource (into `payout`), open (nothing
##      now: a persistent slot stays open from here on)
##   2. success check: an open_all room succeeds once every slot is open,
##      and ends there
##   3. tide: an open_all room that hasn't succeeded loses tide_damage HP,
##      ignoring block; at 0 HP the room is LOST
##   4. after the last turn the room is DONE (an open_all room failed);
##      otherwise the next turn rolls
##
## Randomness: rolls use the ROLLS stream only. `moves` with the RNG state
## and HP the room started with replays it, as for a fight.

enum State { PLAYER_TURN, DONE, LOST }

const NUDGE_PERK: String = "nudge"

const Die = DiceTable.Die
const Slot = DiceTable.Slot

var room_id: String = ""
var state: State = State.PLAYER_TURN
var turn: int = 0
var turns: int = 0
var open_all: bool = false
var tide_damage: int = 0
## True once every slot of an open_all room is open.
var succeeded: bool = false

var hp: int = 0
var max_hp: int = 0
## What the room has paid so far: {resource id: amount}.
var payout: Dictionary[String, int] = {}

var table: DiceTable
var events: Array[Dictionary] = []
var moves: Array[Dictionary] = []

var start_rng: Dictionary = {}
var start_hp: int = 0

## True on planning copies: end_turn resolves the turn and stops there,
## once (a second call would pay the same slots again).
var _is_preview: bool = false
var _preview_spent: bool = false


## Builds the room with the loadout's dice, or returns null if the data is
## missing or the player comes in at 0 HP. `perks` is the list Fight takes.
static func create(data: GameData, loadout_id: String, room_ref: String, rng: RngStreams,
		perks: Array[Dictionary], hp_in: int) -> DiceRoom:
	if not data.has_row("loadouts", loadout_id) or not data.has_row("dice_rooms", room_ref) or hp_in <= 0:
		return null
	var room_row: Dictionary = data.row("dice_rooms", room_ref)
	var loadout: Dictionary = data.row("loadouts", loadout_id)
	var room: DiceRoom = DiceRoom.new()
	room.table = DiceTable.create(data, loadout["dice"] as Array, room_row["slots"] as Array, rng)
	if room.table == null:
		return null
	room.room_id = room_ref
	room.table.events = room.events
	room.table.moves = room.moves
	room.table.rerolls_per_turn = room_row["rerolls_per_turn"] as int
	room.turns = room_row["turns"] as int
	room.open_all = room_row["open_all"] as bool
	room.tide_damage = room_row["tide_damage"] as int
	room.max_hp = loadout["hp"] as int
	room.hp = mini(hp_in, room.max_hp)
	for entry: Dictionary in perks:
		if str(entry.get("perk", "")) == NUDGE_PERK and data.has_row("perks", NUDGE_PERK):
			var nudge_row: Dictionary = data.row("perks", NUDGE_PERK)
			room.table.nudge_perk = NUDGE_PERK
			room.table.nudge_source = str(entry.get("source", ""))
			room.table.nudge_amount = nudge_row["amount"] as int
			room.table.nudge_uses_per_turn = nudge_row["uses_per_turn"] as int
			break
	room.start_hp = room.hp
	room.start_rng = rng.to_dict()
	room._start_turn()
	return room


var hand: Array[Die]:
	get:
		return table.hand
var slots: Array[Slot]:
	get:
		return table.slots


func die(die_id: int) -> Die:
	return table.die(die_id)


func slot(slot_id: String) -> Slot:
	return table.slot(slot_id)


## A slot that has opened and stays open (sealed), or is complete now.
func is_open(s: Slot) -> bool:
	return s.is_complete()


func open_count() -> int:
	var count: int = 0
	for s: Slot in slots:
		if is_open(s):
			count += 1
	return count


func turns_left() -> int:
	return turns - turn + 1


# --- Moves ----------------------------------------------------------------------

func place_refusal(die_id: int, slot_id: String) -> String:
	if state != State.PLAYER_TURN:
		return "The room is done."
	return table.place_refusal(die_id, slot_id)


func place(die_id: int, slot_id: String) -> bool:
	return state == State.PLAYER_TURN and table.place(die_id, slot_id)


func take_back(die_id: int) -> bool:
	return state == State.PLAYER_TURN and table.take_back(die_id)


func reroll_refusal(discard_id: int) -> String:
	if state != State.PLAYER_TURN:
		return "The room is done."
	return table.reroll_refusal(discard_id)


func reroll(discard_id: int) -> bool:
	return state == State.PLAYER_TURN and table.reroll(discard_id)


func nudge(die_id: int) -> bool:
	return state == State.PLAYER_TURN and table.nudge(die_id)


## What a complete slot that isn't open yet does this turn, or 0.
func slot_amount(s: Slot) -> int:
	if s.sealed or not s.is_complete():
		return 0
	return DiceTable.amount(s, table.values_in(s))


## Commits the turn through the pipeline in the header.
func end_turn() -> bool:
	if state != State.PLAYER_TURN or _preview_spent:
		return false
	if _is_preview:
		_preview_spent = true
	else:
		moves.append({"move": "end_turn"})

	# 1. Slots, in card order.
	for s: Slot in slots:
		if s.sealed or not s.is_complete():
			continue
		var amount: int = slot_amount(s)
		match s.row["effect"] as String:
			"heal":
				var healed: int = mini(amount, max_hp - hp)
				hp += healed
				events.append({"type": "heal", "target": "player", "amount": healed, "source": "slot:" + s.id})
			"resource":
				var resource_id: String = s.row["resource"]
				if amount > 0:
					payout[resource_id] = payout.get(resource_id, 0) + amount
					events.append({"type": "loot", "resource": resource_id, "amount": amount, "source": "slot:" + s.id})
			"open":
				events.append({"type": "open", "source": "slot:" + s.id})

	# 2. Success.
	if open_all and open_count() == slots.size():
		succeeded = true
		state = State.DONE
		events.append({"type": "opened"})
		return true

	# 3. Tide.
	if open_all and tide_damage > 0:
		var lost: int = mini(tide_damage, hp)
		hp -= lost
		events.append({"type": "damage", "target": "player", "amount": lost, "blocked": 0, "source": "tide"})
		if hp <= 0:
			state = State.LOST
			events.append({"type": "lost"})
			return true

	# 4. Out of turns, or the next one.
	if turn >= turns:
		state = State.DONE
		events.append({"type": "done"})
		return true
	if not _is_preview:
		_start_turn()
	return true


## Replays a move log. Returns false at the first move the room refuses.
func apply_moves(log_moves: Array[Dictionary]) -> bool:
	for entry: Dictionary in log_moves:
		var ok: bool = false
		match str(entry.get("move", "")):
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


## A copy to plan on: no RNG, so it can't reroll or peek at a roll.
## end_turn() on it resolves the turn and stops before the next roll.
func planning_copy() -> DiceRoom:
	var copy: DiceRoom = DiceRoom.new()
	copy._is_preview = true
	copy.room_id = room_id
	copy.state = state
	copy.turn = turn
	copy.turns = turns
	copy.open_all = open_all
	copy.tide_damage = tide_damage
	copy.succeeded = succeeded
	copy.hp = hp
	copy.max_hp = max_hp
	copy.payout = payout.duplicate()
	copy.table = table.copy(copy.events, copy.moves)
	copy.start_rng = start_rng.duplicate(true)
	copy.start_hp = start_hp
	return copy


func _start_turn() -> void:
	turn += 1
	table.reset_turn()
	var values: Array[int] = table.roll_hand()
	events.append({"type": "turn_start", "turn": turn, "values": values})
