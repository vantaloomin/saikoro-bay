class_name Kit
extends RefCounted
## What a delve takes down (specs/bridge.md section 2): the dice, with their
## faces, and the perks, each with where it came from. The town is the
## loadout: the kit is built from what stands in town and who lives there,
## never bought or equipped by hand.
##
## Imogen's rules (reviews/bridge-spec-review.md):
## - The kit is derived and never saved. Game builds it once, at Go down.
## - It's a replay input: the playtest log records to_dict() at delve_start,
##   and a replay rebuilds it with the strict from_dict(), never build().
## - Perks change amounts after the draws, never how many draws happen.

const LOADOUT: String = "fresh"
## Highest face a kit die may have, for from_dict's checks.
const MAX_FACE: int = 20

## One entry per die, in die-id order:
## {"type": dice row id, "faces": Array[int], "source": "" or who changed it}.
var dice: Array[Dictionary] = []
## One entry per perk, resolved: {"perk", "source", "amount",
## "uses_per_turn", "happy"}. Fight, DiceRoom and Vault read amount and
## uses_per_turn from here, not from the perks table.
var perks: Array[Dictionary] = []


## The starting loadout's dice with `with_perks` ({"perk", "source"},
## optionally "happy"). Returns null if the data lacks the loadout, a die
## or a perk.
static func fresh(data: GameData, with_perks: Array[Dictionary] = []) -> Kit:
	if not data.has_row("loadouts", LOADOUT):
		return null
	var kit: Kit = Kit.new()
	for type_id: Variant in data.row("loadouts", LOADOUT)["dice"] as Array:
		if not data.has_row("dice", str(type_id)):
			return null
		var faces: Array[int] = []
		faces.assign(data.row("dice", str(type_id))["faces"] as Array)
		kit.dice.append({"type": str(type_id), "faces": faces, "source": ""})
	for entry: Dictionary in with_perks:
		if not kit.add_perk(data, str(entry.get("perk", "")), str(entry.get("source", "")), bool(entry.get("happy", false))):
			return null
	return kit


## The kit the town gives: the loadout's dice, and each villager's perk,
## with the happy bonus when their home suits them (specs/bridge.md
## section 4).
static func build(data: GameData, state: GameState) -> Kit:
	var kit: Kit = fresh(data)
	if kit == null:
		return null
	for villager: String in state.villagers():
		if not data.has_row("villagers", villager):
			continue
		var happy: bool = state.mood(data, villager) == Town.Mood.HAPPY
		kit.add_perk(data, str(data.row("villagers", villager)["perk"]), villager, happy)
	return kit


## Adds a perk, with its happy bonus if `happy`. Returns false for an
## unknown perk.
func add_perk(data: GameData, perk_id: String, source: String, happy: bool = false) -> bool:
	if not data.has_row("perks", perk_id):
		push_error("Kit: unknown perk \"%s\" from \"%s\"" % [perk_id, source])
		return false
	var row: Dictionary = data.row("perks", perk_id)
	perks.append({
		"perk": perk_id,
		"source": source,
		"amount": int(row["amount"]) + (int(row["happy_amount"]) if happy else 0),
		"uses_per_turn": int(row["uses_per_turn"]) + (int(row["happy_uses_per_turn"]) if happy else 0),
		"happy": happy,
	})
	return true


func has_perk(perk_id: String) -> bool:
	return perks.any(func(entry: Dictionary) -> bool: return entry["perk"] == perk_id)


## The perk entry for `perk_id`, or {}.
func perk(perk_id: String) -> Dictionary:
	for entry: Dictionary in perks:
		if entry["perk"] == perk_id:
			return entry
	return {}


## What DiceTable.create takes: one {"type", "faces"} per die.
func die_specs() -> Array:
	var out: Array = []
	for entry: Dictionary in dice:
		out.append({"type": entry["type"], "faces": entry["faces"]})
	return out


## JSON-friendly, for the playtest log and replays.
func to_dict() -> Dictionary:
	return {"dice": dice.duplicate(true), "perks": perks.duplicate(true)}


## Rebuilds a logged kit exactly, or returns null if anything in it is
## malformed or names a die type or perk this data doesn't have. Never
## re-derives from the town: a replay plays the kit that was taken down.
static func from_dict(data: GameData, d: Dictionary) -> Kit:
	var dice_in: Variant = d.get("dice")
	var perks_in: Variant = d.get("perks")
	if not (dice_in is Array and perks_in is Array) or (dice_in as Array).is_empty():
		return null
	var kit: Kit = Kit.new()
	for raw: Variant in dice_in as Array:
		if not raw is Dictionary:
			return null
		var entry: Dictionary = raw
		var faces_in: Variant = entry.get("faces")
		if not (data.has_row("dice", str(entry.get("type", ""))) and entry.get("source") is String
				and faces_in is Array and not (faces_in as Array).is_empty()):
			return null
		var faces: Array[int] = []
		for face: Variant in faces_in as Array:
			if not (face is int or face is float) or float(face) != floorf(float(face)):
				return null
			if int(face) < 1 or int(face) > MAX_FACE:
				return null
			faces.append(int(face))
		kit.dice.append({"type": str(entry["type"]), "faces": faces, "source": str(entry["source"])})
	for raw: Variant in perks_in as Array:
		if not raw is Dictionary:
			return null
		var entry: Dictionary = raw
		if not data.has_row("perks", str(entry.get("perk", ""))) or not entry.get("source") is String \
				or not entry.get("happy") is bool:
			return null
		var numbers: Array[int] = []
		for key: String in ["amount", "uses_per_turn"]:
			var value: Variant = entry.get(key)
			if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0:
				return null
			numbers.append(int(value))
		kit.perks.append({"perk": str(entry["perk"]), "source": str(entry["source"]), "amount": numbers[0],
			"uses_per_turn": numbers[1], "happy": bool(entry["happy"])})
	return kit
