class_name GoldenFights
extends RefCounted
## Golden fight fixtures: bots play fixed seeds and every fight's move log,
## events, end state and board previews are recorded. A refactor of the
## fight rules must reproduce them exactly (test_golden_fights.gd).
##
## The fixtures are generated once from a known-good main with
## tools/make_golden_fights.gd and committed. Regenerate them only for a
## change that is meant to alter how fights play, and say so in the PR.

const PATH: String = "res://tests/golden/fights.json"
const LOADOUT: String = "fresh"
## "fiddler" is greedy plus scripted moves the bots rarely make: it rerolls
## on odd turns and places then takes back a die, so reroll, take back and
## the House lock recompute are covered too.
const BOTS: Array[String] = ["greedy", "planner", "fiddler"]
const PERK_SETS: Dictionary[String, Array] = {
	"none": [],
	"all": [
		{"perk": "nudge", "source": "pearl_diver"},
		{"perk": "brace", "source": "shipwright"},
		{"perk": "mend", "source": "onsen_keeper"},
	],
}
## The enemies the fixtures were recorded against. Fixed here, so a new
## enemy in the data doesn't change what the fixtures cover.
const ENEMIES: Array[String] = ["card_shark", "hermit_croupier", "snake_eyes_eel"]
## Seeds per bot, enemy and perk set.
const SEEDS: Dictionary[String, int] = {"none": 50, "all": 20}


## Every case to play, in a fixed order.
static func cases(_data: GameData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for perk_set: String in PERK_SETS:
		for bot: String in BOTS:
			for enemy: String in ENEMIES:
				for s: int in range(1, SEEDS[perk_set] + 1):
					out.append({"bot": bot, "enemy": enemy, "perks": perk_set, "seed": s})
	return out


## Plays one case and returns its record: the move log, a hash of every
## event, a hash of the end state, and a hash of the previews the board
## would show at the start of each turn.
static func play(data: GameData, case: Dictionary) -> Dictionary:
	var perks: Array[Dictionary] = []
	perks.assign(PERK_SETS[case["perks"]])
	var rng: RngStreams = RngStreams.new(case["seed"] as int)
	var fight: Fight = Fight.create(data, LOADOUT, case["enemy"], rng, perks)
	var fiddle: bool = case["bot"] == "fiddler"
	var bot: FightBot = FightBot.make("greedy" if fiddle else case["bot"])
	var previews: HashingContext = HashingContext.new()
	previews.start(HashingContext.HASH_SHA256)
	var turns: int = 0
	while fight.state == Fight.State.PLAYER_TURN and turns < 60:
		previews.update(JSON.stringify(board_previews(fight)).to_utf8_buffer())
		if fiddle:
			_fiddle(fight)
		bot.play_turn(fight)
		fight.end_turn()
		turns += 1
	var record: Dictionary = case.duplicate()
	record["moves"] = encode_moves(fight.moves)
	record["events"] = hash_of(fight.events)
	record["end"] = hash_of(end_state(fight, rng))
	record["previews"] = previews.finish().hex_encode().substr(0, 16)
	return record


static func _fiddle(fight: Fight) -> void:
	if fight.turn % 2 == 1:
		var lowest: Fight.Die = null
		for d: Fight.Die in fight.hand:
			if d.is_free() and not d.locked and (lowest == null or d.value < lowest.value):
				lowest = d
		if lowest != null:
			fight.reroll(lowest.id)
	for d: Fight.Die in fight.hand:
		for s: Fight.Slot in fight.slots:
			if fight.place(d.id, s.id):
				fight.take_back(d.id)
				return


## What the board asks the fight before the player moves: every die in
## every slot, and the End turn preview.
static func board_previews(fight: Fight) -> Array:
	var out: Array = []
	for d: Fight.Die in fight.hand:
		for s: Fight.Slot in fight.slots:
			out.append(fight.preview(d.id, s.id))
		out.append(fight.reroll_refusal(d.id))
	var end: Dictionary = fight.preview_end_turn()
	out.append([end["events"], end["enemy_hp"], end["player_hp"], end["player_block"], end["state"]])
	return out


static func end_state(fight: Fight, rng: RngStreams) -> Dictionary:
	var hand: Array = []
	for d: Fight.Die in fight.hand:
		hand.append([d.id, d.type_id, d.value, d.locked, d.discarded, d.slot_id])
	var slots: Array = []
	for s: Fight.Slot in fight.slots:
		slots.append([s.id, s.dice])
	return {
		"state": fight.state, "turn": fight.turn,
		"player": [fight.player_hp, fight.player_max_hp, fight.player_block],
		"enemy": [fight.enemy_id, fight.enemy_hp, fight.enemy_max_hp, fight.enemy_block, fight.intent_index],
		"left": [fight.rerolls_left, fight.nudges_left],
		"hand": hand, "slots": slots,
		"start": [fight.start_hp, fight.start_rng], "rng": rng.to_dict(),
	}


## Compact move log: "p0:strike", "t0", "r1", "n2", "e".
static func encode_moves(moves: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for m: Dictionary in moves:
		match str(m["move"]):
			"place":
				parts.append("p%d:%s" % [m["die"], m["slot"]])
			"take_back":
				parts.append("t%d" % m["die"])
			"reroll":
				parts.append("r%d" % m["die"])
			"nudge":
				parts.append("n%d" % m["die"])
			"end_turn":
				parts.append("e")
			_:
				parts.append("?" + JSON.stringify(m))
	return " ".join(parts)


static func hash_of(value: Variant) -> String:
	return JSON.stringify(value).sha256_text().substr(0, 16)
