class_name VaultBot
extends RefCounted
## Plays Koban's vault the way a careful new player might.
##
## Wager: raises only against a weak house hand (high die, total 12 or
## less), on the haul resource worth the most to stake. Turn: if the best 3
## dice (with a nudge if that helps) beat her, it plays them. Otherwise it
## keeps its core (its biggest set of matching dice, or else its highest
## die), spends the lowest other die to reroll the rest, then plays the
## best 3 it has.
##
## It reads only what the player sees: her open hand and your dice. It
## never draws randomness itself.

const WEAK_HOUSE: int = 12
## Placeholder worths, as RoomBot uses.
const RESOURCE_WORTH: Dictionary[String, int] = RoomBot.RESOURCE_WORTH


func play_vault(vault: Vault) -> int:
	while not vault.is_over():
		play_round(vault)
	return vault.round_number


func play_round(vault: Vault) -> void:
	if vault.state == Vault.State.WAGER:
		_wager(vault)
		vault.roll()
	var target: int = Vault.hand_score(vault.house_hand)
	var best: Dictionary = best_hand(vault)
	if best["score"] <= target and vault.table.rerolls_left > 0:
		var keep: Array[int] = _core(vault)
		var discard: int = -1
		for d: Vault.Die in vault.table.hand:
			if d.is_free() and not d.locked and not keep.has(d.id) \
					and (discard < 0 or d.value < vault.die(discard).value):
				discard = d.id
		if discard >= 0:
			for die_id: int in keep:
				vault.place(die_id, vault.hand().id)
			vault.reroll(discard)
			for die_id: int in keep:
				vault.take_back(die_id)
			best = best_hand(vault)
	if best["nudge"] >= 0:
		vault.nudge(best["nudge"] as int)
	for die_id: int in best["dice"] as Array:
		vault.place(die_id, vault.hand().id)
	vault.end_turn()


## The best 3 free dice: {"score", "dice" (ids), "nudge" (die id or -1)}.
func best_hand(vault: Vault) -> Dictionary:
	var free: Array[Vault.Die] = []
	for d: Vault.Die in vault.table.hand:
		if d.is_free() and not d.locked:
			free.append(d)
	var best: Dictionary = {"score": -1, "dice": [], "nudge": -1}
	var nudges: Array[int] = [-1]
	if vault.table.nudges_left > 0:
		for d: Vault.Die in free:
			if d.value < d.max_face():
				nudges.append(d.id)
	for nudged: int in nudges:
		for a: int in free.size():
			for b: int in range(a + 1, free.size()):
				for c: int in range(b + 1, free.size()):
					var trio: Array[Vault.Die] = [free[a], free[b], free[c]]
					var values: Array[int] = []
					for d: Vault.Die in trio:
						values.append(mini(d.value + vault.table.nudge_amount, d.max_face()) if d.id == nudged else d.value)
					var value: int = Vault.hand_score(values)
					if value > best["score"]:
						best = {"score": value, "dice": [trio[0].id, trio[1].id, trio[2].id], "nudge": nudged}
	return best


## The dice worth keeping through a reroll: the biggest group of matching
## free dice (highest value on ties), or the single highest die.
func _core(vault: Vault) -> Array[int]:
	var groups: Dictionary[int, Array] = {}
	for d: Vault.Die in vault.table.hand:
		if d.is_free() and not d.locked:
			if not groups.has(d.value):
				groups[d.value] = []
			groups[d.value].append(d.id)
	var best_value: int = -1
	for value: int in groups:
		if best_value < 0 or groups[value].size() > groups[best_value].size() \
				or (groups[value].size() == groups[best_value].size() and value > best_value):
			best_value = value
	var out: Array[int] = []
	if best_value >= 0:
		out.assign(groups[best_value].slice(0, 3))
	return out


func _wager(vault: Vault) -> void:
	if Vault.hand_rank(vault.house_hand) != Vault.HIGH_DIE:
		return
	var total: int = 0
	for v: int in vault.house_hand:
		total += v
	if total > WEAK_HOUSE:
		return
	var pick: String = ""
	var pick_worth: int = 0
	for id: String in vault.haul.resources:
		var worth: int = vault.raise_amount(id) * RESOURCE_WORTH.get(id, 1)
		if worth > pick_worth:
			pick = id
			pick_worth = worth
	if not pick.is_empty():
		vault.raise(pick)
