class_name KitSheet
extends RefCounted
## The words and marks for the kit (specs/bridge.md section 5): what the
## Kit tab, the kit strip above Go down, a shop's Build card and the stamp
## show. Everything comes from Kit.build, the same kit Go down takes, so
## the screen never re-derives a rule.
##
## Every perk line shows its gain and, for a shop, its cost (Mara: a hidden
## downside reads as cheating). A happy villager's bonus is its own small
## line; an unhappy one's missing bonus is a ghost line, so the player sees
## what fixing their home would give.


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
		})
	return rows


## True if any die differs from the loadout's: changed or added.
static func is_changed(row: Dictionary) -> bool:
	return row["added"] or (row["changed"] as Array).has(true)


## The perk lines, in kit order (villagers, then shops): for each perk
## {"kind": "perk", "source", "source_id", "perk", "gain", "cost"}, then
## {"kind": "happy", "text"} when its villager is happy, or {"kind":
## "ghost", "text"} when their home doesn't suit them yet.
static func perk_lines(data: GameData, state: GameState, kit: Kit) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for entry: Dictionary in kit.perks:
		var row: Dictionary = data.row("perks", str(entry["perk"]))
		var source: String = str(entry["source"])
		lines.append({"kind": "perk", "source": source_name(data, source), "source_id": source,
			"perk": str(row["name"]), "gain": str(row["gain"]), "cost": str(row["cost"])})
		var bonus: String = str(row["happy_gain"])
		if bonus.is_empty() or not data.has_row("villagers", source):
			continue
		if entry["happy"]:
			lines.append({"kind": "happy", "text": "Happy · " + bonus})
		else:
			var why: String = "a home" if state.mood(data, source) == Town.Mood.HOMELESS else "their home suited them"
			lines.append({"kind": "ghost", "text": "If %s: %s" % [why, bonus.left(1).to_lower() + bonus.substr(1)]})
	return lines


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


## A villager's role or a building's name, for a source chip.
static func source_name(data: GameData, source: String) -> String:
	if data.has_row("villagers", source):
		return str(data.row("villagers", source)["role"])
	if data.has_row("buildings", source):
		return str(data.row("buildings", source)["name"])
	return source.capitalize()
