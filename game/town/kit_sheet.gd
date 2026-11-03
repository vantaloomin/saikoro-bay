class_name KitSheet
extends RefCounted
## The words and marks for the kit (specs/bridge.md section 5): what the
## Kit tab, the kit strip above Go down, a shop's Build card and the stamp
## show. Everything comes from Kit.build, the same kit Go down takes, so
## the screen never re-derives a rule.
##
## Every perk line shows its gain and, for a shop, its cost (Mara: a hidden
## downside reads as cheating). A villager's happy bonus folds into its gain
## line, as "happy: ..." when it applies or "if happy: ..." when it doesn't,
## so the player sees what fixing their home would give. Plain dice group
## into one "Standard" row (Mara's #51 review), so only what changed takes
## a row of its own.

## The row for the loadout's own dice, grouped.
const STANDARD: String = "Standard"


## One row per die, in die order: {"name", "faces", "changed" (one bool per
## face: differs from the loadout's die there), "source" (who changed or
## added it, as a name, or ""), "added"}.
static func dice_rows(data: GameData, kit: Kit) -> Array[Dictionary]:
	var loadout: Array = data.row("loadouts", Kit.LOADOUT)["dice"] as Array
	var rows: Array[Dictionary] = []
	for i: int in kit.dice.size():
		var entry: Dictionary = kit.dice[i]
		var faces: Array[int] = entry["faces"]
		var plain: Array = []
		if not entry["added"] and i < loadout.size():
			plain = data.row("dice", str(loadout[i]))["faces"] as Array
		var changed: Array[bool] = []
		for j: int in faces.size():
			changed.append(not entry["added"] and (j >= plain.size() or int(plain[j]) != faces[j]))
		rows.append({
			"name": str(data.row("dice", str(entry["type"])).get("name", entry["type"])),
			"faces": faces,
			"changed": changed,
			"source": source_name(data, str(entry["source"])),
			"added": entry["added"],
			"change": "added" if entry["added"] else change_text(plain, faces),
		})
	return rows


## What a die lost against the loadout's, in words: "no 1s or 6s". "" if
## nothing is gone; "changed" if the faces moved but every number stayed.
static func change_text(plain: Array, faces: Array[int]) -> String:
	var gone: PackedStringArray = []
	for face: Variant in plain:
		if not faces.has(int(face)) and not gone.has("%ds" % int(face)):
			gone.append("%ds" % int(face))
	if gone.is_empty():
		return "changed" if Array(faces) != plain.map(func(f: Variant) -> int: return int(f)) else ""
	if gone.size() == 1:
		return "no " + gone[0]
	return "no %s or %s" % [", ".join(gone.slice(0, gone.size() - 1)), gone[gone.size() - 1]]


## The Kit tab's dice rows: dice_rows with each run of plain dice folded
## into one, which gains "count" (every row has it) and the chip "Standard
## × 3". A changed or added die's chip says who and what: "Net shed · no 1s
## or 6s", "Boat shed · added".
static func dice_groups(data: GameData, kit: Kit) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for row: Dictionary in dice_rows(data, kit):
		var last: Dictionary = groups.back() if not groups.is_empty() else {}
		if not is_changed(row) and not last.is_empty() and not is_changed(last) and last["faces"] == row["faces"]:
			last["count"] = int(last["count"]) + 1
			last["chip"] = "%s × %d" % [STANDARD, last["count"]]
			continue
		row["count"] = 1
		if is_changed(row):
			var parts: PackedStringArray = []
			for part: String in [str(row["source"]), str(row["change"])]:
				if not part.is_empty():
					parts.append(part)
			row["chip"] = " · ".join(parts)
		else:
			row["chip"] = STANDARD
		groups.append(row)
	return groups


## True if any die differs from the loadout's: changed or added.
static func is_changed(row: Dictionary) -> bool:
	return row["added"] or (row["changed"] as Array).has(true)


## The perk lines, in kit order (villagers, then shops): {"source",
## "source_id", "perk", "gain", "cost", "bonus", "happy"}. "bonus" is a
## villager's happy bonus in words ("" for a shop), and "happy" whether it
## applies now; the tab folds it into the gain line.
static func perk_lines(data: GameData, kit: Kit) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for entry: Dictionary in kit.perks:
		var row: Dictionary = data.row("perks", str(entry["perk"]))
		var source: String = str(entry["source"])
		var bonus: String = str(row["happy_gain"]) if data.has_row("villagers", source) else ""
		lines.append({"source": source_name(data, source), "source_id": source, "perk": str(row["name"]),
			"gain": str(row["gain"]), "cost": str(row["cost"]), "bonus": bonus, "happy": bool(entry["happy"])})
	return lines


## A perk's gain line with its bonus folded in: "Raise one die by 1, once a
## turn · happy: twice a turn", or "· if happy: ..." while it waits.
static func gain_text(line: Dictionary) -> String:
	var bonus: String = str(line["bonus"])
	if bonus.is_empty():
		return str(line["gain"])
	return "%s · %s: %s" % [line["gain"], "happy" if line["happy"] else "if happy", bonus.left(1).to_lower() + bonus.substr(1)]


## What a villager's perk does when they turn happy (`happy`) or stop
## being happy: "Brace 2 → 3", "Nudge 1 → 2 a turn" (specs/bridge.md
## section 5: move and swap tags say when they change a perk). "" when
## they have no perk or it has no happy bonus.
static func happy_change(data: GameData, villager: String, happy: bool) -> String:
	if not data.has_row("villagers", villager):
		return ""
	var perk_id: String = str(data.row("villagers", villager).get("perk", ""))
	if not data.has_row("perks", perk_id):
		return ""
	var row: Dictionary = data.row("perks", perk_id)
	var field: String = "amount" if int(row["happy_amount"]) > 0 else "uses_per_turn"
	var bonus: int = int(row["happy_" + field])
	if bonus <= 0:
		return ""
	var plain: int = int(row[field])
	var before: int = plain if happy else plain + bonus
	var after: int = plain + bonus if happy else plain
	return "%s %d → %d%s" % [row["name"], before, after, " a turn" if field == "uses_per_turn" else ""]


## A shop's perk for its Build card and the stamp: {"perk", "kit", "gain",
## "cost"}, where "kit" reads "Kit: + Weighted die (2 3 3 4 4 5)". {} for a
## building with no perk.
static func shop_perk(data: GameData, building_id: String) -> Dictionary:
	var perk_id: String = str(data.row("buildings", building_id).get("perk", ""))
	if perk_id.is_empty() or not data.has_row("perks", perk_id):
		return {}
	var row: Dictionary = data.row("perks", perk_id)
	var kit_line: String = "Kit: + " + str(row["name"])
	if row["kind"] in ["die_faces", "add_die"] and data.has_row("dice", str(row["die"])):
		var faces: PackedStringArray = []
		for face: Variant in data.row("dice", str(row["die"]))["faces"] as Array:
			faces.append(str(face))
		kit_line += " (%s)" % " ".join(faces)
	return {"perk": str(row["name"]), "kit": kit_line, "gain": str(row["gain"]), "cost": str(row["cost"])}


## What the kit strip says to a screen reader and in its tooltip:
## "Your kit: 5 dice, 2 changed · 4 perks".
static func summary(data: GameData, kit: Kit) -> String:
	var changed: int = dice_rows(data, kit).filter(is_changed).size()
	var dice: String = "%d dice" % kit.dice.size()
	if changed > 0:
		dice += ", %d changed" % changed
	return "Your kit: %s · %d perk%s" % [dice, kit.perks.size(), "" if kit.perks.size() == 1 else "s"]


## A villager's name or a building's name, for a source chip.
static func source_name(data: GameData, source: String) -> String:
	if data.has_row("villagers", source):
		return data.villager_name(source)
	if data.has_row("buildings", source):
		return str(data.row("buildings", source)["name"])
	return source.capitalize()
