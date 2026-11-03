class_name Fight
extends RefCounted
## One dice fight (DR-1 to DR-4, DR-6, DR-8), as plain rules with no nodes.
##
## The board scene and the bot both play through the same moves: place,
## take_back, reroll, nudge and end_turn. Each returns false and changes
## nothing when the move isn't allowed. Nothing takes effect when a die is
## placed; end_turn() commits every slot at once, so taking a die back is
## always safe and every preview is exact.
##
## end_turn() runs one fixed pipeline (spec: specs/dice-fight-rules.md):
##   1. complete slots resolve in card order (all of them, even past 0 HP);
##      a half-filled Pair Bet doesn't fire and its die counts as unused
##   2. each unused, unlocked die gives unused-die block
##   3. win check: enemy at 0 HP wins; the enemy doesn't act, Mend fires
##   4. twist damage (Snake eyes: each unused 1 bites for 1, ignoring block;
##      a bite to 0 HP loses on the spot)
##   5. the enemy attacks (through block)
##   6. lose check
##   7. next turn: block resets, Brace, intent advances (its guard applies
##      now, so it protects during the turn it's shown), roll in die-id
##      order, House lock on the highest die (lowest id on ties)
##
## The dice (hand, slots, per-turn counters and the moves on them) live in
## a DiceTable that the fight owns, shared with the other dice rooms. The
## fight owns HP, the enemy and what each slot does when the turn ends.
##
## Randomness: rolls use the ROLLS stream and nothing else draws during a
## fight. Previews and planning copies run the same pipeline on a copy with
## no dice streams, so they can't drift from what really happens, can't
## peek at a future roll, and never move the real streams.
##
## Everything that happens is appended to `events` as a Dictionary, so the
## board animates only from events and flashes perk source badges (KP-2).
## `moves` records every accepted move, so start_rng + start_hp + moves
## replays any fight, including later fights of a delve.

enum State { PLAYER_TURN, WON, LOST }

const NUDGE_PERK: String = "nudge"
const BRACE_PERK: String = "brace"
const MEND_PERK: String = "mend"


## The table's dice and slots, under their old names.
const Die = DiceTable.Die
const Slot = DiceTable.Slot


class Perk:
	extends RefCounted
	var id: String = ""
	## Who granted it (villager or building id), for source badges.
	var source: String = ""
	var amount: int = 0
	var uses_per_turn: int = 0


var state: State = State.PLAYER_TURN
var turn: int = 0

var player_hp: int = 0
var player_max_hp: int = 0
var player_block: int = 0

var enemy_id: String = ""
var enemy_name: String = ""
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var enemy_block: int = 0
var twist: String = "none"
var intent_index: int = 0

## The dice. Its event and move logs are this fight's, so table moves and
## fight moves form one sequence.
var table: DiceTable

var hand: Array[Die]:
	get:
		return table.hand
var slots: Array[Slot]:
	get:
		return table.slots
var rerolls_left: int:
	get:
		return table.rerolls_left
	set(value):
		table.rerolls_left = value
var nudges_left: int:
	get:
		return table.nudges_left
	set(value):
		table.nudges_left = value

## The RNG state and HP the fight started with, before the first roll.
## With the move log, this replays any fight of a delve, not just the first.
var start_rng: Dictionary = {}
var start_hp: int = 0

## The table logs into these same arrays, so assigning a new one rebinds
## the table too and the room keeps a single log.
var events: Array[Dictionary] = []:
	set(value):
		events = value
		if table != null:
			table.events = value
## Every accepted move, in order: {"move": "place", "die": 0, "slot": "strike"}...
var moves: Array[Dictionary] = []:
	set(value):
		moves = value
		if table != null:
			table.moves = value

var _unused_die_block: int = 0
## True on preview copies: end_turn stops before the next turn starts.
var _is_preview: bool = false
var _intents: Array[Dictionary] = []
var _perks: Dictionary[String, Perk] = {}


## Builds a fight, or returns null if an id doesn't exist in `data` or the
## player comes in at 0 HP. `perks` is a list of
## {"perk": id, "source": villager_or_building_id}.
## `hp` carries the player's HP in from earlier fights (-1 = full).
static func create(data: GameData, loadout_id: String, enemy_ref: String, rng: RngStreams,
		perks: Array[Dictionary] = [], hp: int = -1) -> Fight:
	if not data.has_row("loadouts", loadout_id) or not data.has_row("enemies", enemy_ref):
		return null
	if hp == 0:
		return null
	var fight: Fight = Fight.new()
	var loadout: Dictionary = data.row("loadouts", loadout_id)
	fight.table = DiceTable.create(data, loadout["dice"] as Array, loadout["slots"] as Array, rng)
	if fight.table == null:
		return null
	fight.table.events = fight.events
	fight.table.moves = fight.moves
	fight.table.rerolls_per_turn = loadout["rerolls_per_turn"] as int
	fight.player_max_hp = loadout["hp"] as int
	fight.player_hp = fight.player_max_hp if hp < 0 else mini(hp, fight.player_max_hp)
	fight._unused_die_block = loadout["unused_die_block"] as int

	var enemy: Dictionary = data.row("enemies", enemy_ref)
	fight.enemy_id = enemy_ref
	fight.enemy_name = enemy["name"]
	fight.enemy_max_hp = enemy["hp"] as int
	fight.enemy_hp = fight.enemy_max_hp
	fight.twist = enemy["twist"]
	if fight.twist == "house_lock":
		fight.table.lock_policy = DiceTable.LockPolicy.LOCK_HIGHEST_FREE
		fight.table.lock_source = fight.twist
	for text: Variant in enemy["intents"] as Array:
		var intent: Dictionary = parse_intent(text as String)
		intent.make_read_only()
		fight._intents.append(intent)
	fight._intents.make_read_only()

	for entry: Dictionary in perks:
		var perk_id: String = str(entry.get("perk", ""))
		if not data.has_row("perks", perk_id):
			push_error("Fight.create: unknown perk \"%s\" from \"%s\"" % [perk_id, entry.get("source", "")])
			continue
		var perk_row: Dictionary = data.row("perks", perk_id)
		var perk: Perk = Perk.new()
		perk.id = perk_id
		perk.source = str(entry.get("source", ""))
		perk.amount = perk_row["amount"] as int
		perk.uses_per_turn = perk_row["uses_per_turn"] as int
		fight._perks[perk_id] = perk
	if fight.has_perk(NUDGE_PERK):
		var nudge_perk: Perk = fight._perks[NUDGE_PERK]
		fight.table.nudge_perk = NUDGE_PERK
		fight.table.nudge_source = nudge_perk.source
		fight.table.nudge_amount = nudge_perk.amount
		fight.table.nudge_uses_per_turn = nudge_perk.uses_per_turn

	fight.start_hp = fight.player_hp
	fight.start_rng = rng.to_dict()
	fight._start_turn()
	return fight


## "attack:4+guard:4" -> {"attack": 4, "guard": 4}. Returns {} if any part
## isn't attack:N or guard:N with N >= 0, so bad data never half-loads.
static func parse_intent(text: String) -> Dictionary:
	var intent: Dictionary = {}
	for part: String in text.split("+", false):
		var bits: PackedStringArray = part.strip_edges().split(":")
		if bits.size() != 2 or not bits[0] in ["attack", "guard"] or intent.has(bits[0]):
			return {}
		if not bits[1].is_valid_int() or bits[1].to_int() < 0:
			return {}
		intent[bits[0]] = bits[1].to_int()
	return intent


## Problems with an enemy row's intents, for the data check. Empty if fine.
static func intent_errors(enemy: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	var intents: Array = enemy.get("intents", []) as Array
	if intents.is_empty():
		problems.append("%s: needs at least one intent" % enemy.get("id", "?"))
	for text: Variant in intents:
		if parse_intent(str(text)).is_empty():
			problems.append("%s: can't read intent \"%s\"" % [enemy.get("id", "?"), text])
	return problems


## What the enemy does this turn (DR-6): its guard is already up, and its
## attack lands after your slots.
func current_intent() -> Dictionary:
	if _intents.is_empty():
		return {}
	return _intents[intent_index % _intents.size()]


## The intent after this one, for the small dimmed "next" display.
func next_intent() -> Dictionary:
	if _intents.is_empty():
		return {}
	return _intents[(intent_index + 1) % _intents.size()]


func has_perk(perk_id: String) -> bool:
	return _perks.has(perk_id)


## Who granted `perk_id` (villager or building id), or "".
func perk_source(perk_id: String) -> String:
	return _perks[perk_id].source if _perks.has(perk_id) else ""


func die(die_id: int) -> Die:
	return table.die(die_id)


func slot(slot_id: String) -> Slot:
	return table.slot(slot_id)


# --- Moves --------------------------------------------------------------------

## Why `die_id` can't go in `slot_id` right now, or "" if it can.
func place_refusal(die_id: int, slot_id: String) -> String:
	if state != State.PLAYER_TURN:
		return "The fight is over."
	return table.place_refusal(die_id, slot_id)


func place(die_id: int, slot_id: String) -> bool:
	return state == State.PLAYER_TURN and table.place(die_id, slot_id)


## Returns a placed die to the hand. Free, any number of times (DR-4).
func take_back(die_id: int) -> bool:
	return state == State.PLAYER_TURN and table.take_back(die_id)


## Why rerolling by discarding `discard_id` isn't allowed, or "" if it is.
func reroll_refusal(discard_id: int) -> String:
	if state != State.PLAYER_TURN:
		return "The fight is over."
	return table.reroll_refusal(discard_id)


## Spends `discard_id` to reroll every other free, unlocked die, in die-id
## order (DR-2). The House lock is then recomputed.
func reroll(discard_id: int) -> bool:
	return state == State.PLAYER_TURN and table.reroll(discard_id)


## Pearl diver's perk: +amount to a free die, up to its highest face.
func nudge(die_id: int) -> bool:
	return state == State.PLAYER_TURN and has_perk(NUDGE_PERK) and table.nudge(die_id)


## What a slot would do with `die_id` added (DR-3), as it would really land
## at end of turn: the real pipeline runs on a planning copy, so enemy guard
## used up by earlier slots is counted. Keys:
##   ok, reason   whether it can go there, and why not
##   effect       damage, block or heal
##   amount       what the slot produces
##   landed       what reaches its target (damage after guard, healing after
##                the HP cap, block as is)
##   blocked      damage the enemy's guard soaks
##   complete     false while a multi-die slot waits for more dice; amount
##                then assumes matching dice arrive
##   can_complete false when the hand has no free dice left to fill it, so
##                the board says "Needs another 6" instead of promising
func preview(die_id: int, slot_id: String) -> Dictionary:
	var reason: String = place_refusal(die_id, slot_id)
	var result: Dictionary = {"ok": reason.is_empty(), "reason": reason, "effect": "", "amount": 0,
		"landed": 0, "blocked": 0, "complete": false, "can_complete": false}
	if not reason.is_empty():
		return result
	var s: Slot = slot(slot_id)
	var values: Array[int] = table.values_in(s)
	values.append(hand[die_id].value)
	var missing: int = maxi(0, s.min_dice() - values.size())
	result["complete"] = missing == 0
	result["can_complete"] = missing <= table.matching_free_dice(die_id, hand[die_id].value)
	while values.size() < s.min_dice():
		values.append(hand[die_id].value)
	result["effect"] = s.row["effect"]
	result["amount"] = DiceTable.amount(s, values)

	var copy: Fight = planning_copy()
	copy.place(die_id, slot_id)
	if missing > 0:
		# Pretend the rest arrived: the slot fires now with the full amount.
		var copy_slot: Slot = copy.slot(slot_id)
		var row: Dictionary = copy_slot.row.duplicate()
		row["min_dice"] = copy_slot.dice.size()
		row["max_dice"] = copy_slot.dice.size()
		row["mult"] = 0
		row["add"] = result["amount"]
		copy_slot.row = row
	copy.events.clear()
	copy.end_turn()
	for event: Dictionary in copy.events:
		if event.get("source", "") == "slot:" + slot_id:
			result["landed"] = event["amount"]
			result["blocked"] = event.get("blocked", 0)
	return result


## What ending the turn now would do, without doing it (Mara's End turn
## preview). Runs the real pipeline on a copy. Keys: events (the turn's
## events), enemy_hp, player_hp, player_block, state.
func preview_end_turn() -> Dictionary:
	var copy: Fight = _copy()
	copy._is_preview = true
	copy.events.clear()
	copy.end_turn()
	return {
		"events": copy.events,
		"enemy_hp": copy.enemy_hp,
		"player_hp": copy.player_hp,
		"player_block": copy.player_block,
		"state": copy.state,
	}


## What a complete slot does at end of turn with the dice in it now, or 0.
func slot_amount(s: Slot) -> int:
	if not s.is_complete():
		return 0
	return DiceTable.amount(s, table.values_in(s))


## Commits the turn through the pipeline in the header. Starts the next
## turn unless the fight ended.
func end_turn() -> bool:
	if state != State.PLAYER_TURN:
		return false
	if not _is_preview:
		moves.append({"move": "end_turn"})

	# 1. Slots, in card order. All complete slots fire, even past 0 HP.
	for s: Slot in slots:
		if not s.is_complete():
			continue
		var amount: int = slot_amount(s)
		match s.row["effect"] as String:
			"damage":
				_hit_enemy(amount, "slot:" + s.id)
			"block":
				player_block += amount
				events.append({"type": "block", "target": "player", "amount": amount, "source": "slot:" + s.id})
			"heal":
				_heal(amount, "slot:" + s.id)

	# 2. Unused dice (including a half-filled pair) give block.
	var unused: Array[Die] = table.unused_dice()
	var unused_block: int = 0
	for d: Die in unused:
		if not d.locked:
			unused_block += _unused_die_block
	if unused_block > 0:
		player_block += unused_block
		events.append({"type": "block", "target": "player", "amount": unused_block, "source": "unused_dice"})

	# 3. Win check.
	if enemy_hp <= 0:
		_win()
		return true

	# 4. Twist damage. Snake eyes ignores block.
	if twist == "snake_eyes":
		for d: Die in unused:
			if d.value == 1:
				var bite: int = mini(1, player_hp)
				player_hp -= bite
				events.append({"type": "damage", "target": "player", "amount": bite, "blocked": 0,
					"source": "twist:snake_eyes", "die": d.id})
		if player_hp <= 0:
			state = State.LOST
			events.append({"type": "lost"})
			return true

	# 5. The enemy attacks.
	var intent: Dictionary = current_intent()
	if intent.has("attack"):
		_hit_player(intent["attack"] as int, "enemy")

	# 6. Lose check.
	if player_hp <= 0:
		state = State.LOST
		events.append({"type": "lost"})
		return true

	# 7. Next turn.
	if not _is_preview:
		intent_index += 1
		_start_turn()
	return true


## Replays a move log on a fresh fight. Returns false at the first move the
## fight refuses (a log that doesn't match the seed or the data).
func apply_moves(log: Array[Dictionary]) -> bool:
	for entry: Dictionary in log:
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


# --- Internals ----------------------------------------------------------------

func _start_turn() -> void:
	turn += 1
	player_block = 0
	table.reset_turn()

	if has_perk(BRACE_PERK):
		var brace: Perk = _perks[BRACE_PERK]
		player_block += brace.amount
		events.append({"type": "perk", "perk": BRACE_PERK, "source": brace.source, "amount": brace.amount})

	var intent: Dictionary = current_intent()
	enemy_block = intent.get("guard", 0) as int
	if enemy_block > 0:
		events.append({"type": "block", "target": "enemy", "amount": enemy_block, "source": "enemy"})

	var values: Array[int] = table.roll_hand()
	events.append({"type": "turn_start", "turn": turn, "values": values, "intent": intent})
	table.apply_lock()


## A copy to plan on: place, take back, nudge and preview freely. It has no
## dice streams, so it can't reroll, and a planner (or the bot) can never
## peek at a roll before it happens or move the real streams. end_turn() on
## it resolves the turn and stops there, like preview_end_turn().
func planning_copy() -> Fight:
	var copy: Fight = _copy()
	copy._is_preview = true
	return copy


## A deep copy for previews, without the RNG (previews never roll).
func _copy() -> Fight:
	var copy: Fight = Fight.new()
	copy.state = state
	copy.turn = turn
	copy.player_hp = player_hp
	copy.player_max_hp = player_max_hp
	copy.player_block = player_block
	copy.enemy_id = enemy_id
	copy.enemy_name = enemy_name
	copy.enemy_hp = enemy_hp
	copy.enemy_max_hp = enemy_max_hp
	copy.enemy_block = enemy_block
	copy.twist = twist
	copy.intent_index = intent_index
	copy.table = table.copy(copy.events, copy.moves)
	copy._unused_die_block = _unused_die_block
	copy._intents = _intents
	copy.start_rng = start_rng
	copy.start_hp = start_hp
	for perk_id: String in _perks:
		var perk: Perk = Perk.new()
		perk.id = _perks[perk_id].id
		perk.source = _perks[perk_id].source
		perk.amount = _perks[perk_id].amount
		perk.uses_per_turn = _perks[perk_id].uses_per_turn
		copy._perks[perk_id] = perk
	return copy


func _hit_enemy(amount: int, source: String) -> void:
	var blocked: int = mini(enemy_block, amount)
	enemy_block -= blocked
	enemy_hp = maxi(0, enemy_hp - (amount - blocked))
	events.append({"type": "damage", "target": "enemy", "amount": amount - blocked, "blocked": blocked, "source": source})


func _hit_player(amount: int, source: String) -> void:
	var blocked: int = mini(player_block, amount)
	player_block -= blocked
	player_hp = maxi(0, player_hp - (amount - blocked))
	events.append({"type": "damage", "target": "player", "amount": amount - blocked, "blocked": blocked, "source": source})


func _heal(amount: int, source: String) -> void:
	var healed: int = mini(amount, player_max_hp - player_hp)
	player_hp += healed
	events.append({"type": "heal", "target": "player", "amount": healed, "source": source})


func _win() -> void:
	state = State.WON
	events.append({"type": "won"})
	if has_perk(MEND_PERK):
		var mend: Perk = _perks[MEND_PERK]
		var before: int = player_hp
		_heal(mend.amount, "perk:" + MEND_PERK)
		events.append({"type": "perk", "perk": MEND_PERK, "source": mend.source, "amount": player_hp - before})
