class_name GreedyBot
extends FightBot
## The floor: plays the way a new player might. Pairs first if it has one,
## then each die from highest to lowest goes where it does the most right
## now. Guard only when the enemy's attack would get through. Nudges a 4 up
## to fit High Roller
## when nothing else fits it. Never rerolls.


func name() -> String:
	return "greedy"


func play_turn(fight: Fight) -> void:
	_nudge_into_high_roller(fight)
	_place_pair(fight)
	for d: Fight.Die in _by_value(fight):
		if not d.is_free() or d.locked:
			continue
		var best_slot: String = ""
		var best_value: int = 0
		for s: Fight.Slot in fight.slots:
			if s.max_dice() > 1:
				continue
			var preview: Dictionary = fight.preview(d.id, s.id)
			if not preview["ok"]:
				continue
			var value: int = _worth(fight, preview["effect"] as String, preview["amount"] as int)
			if value > best_value:
				best_value = value
				best_slot = s.id
		if not best_slot.is_empty():
			fight.place(d.id, best_slot)


func _worth(fight: Fight, effect: String, amount: int) -> int:
	match effect:
		"damage":
			return amount
		"block":
			var incoming: int = fight.current_intent().get("attack", 0) as int
			return mini(amount, maxi(0, incoming - fight.player_block))
		"heal":
			return mini(amount, fight.player_max_hp - fight.player_hp)
	return 0


func _nudge_into_high_roller(fight: Fight) -> void:
	if fight.nudges_left <= 0 or fight.slot("high_roller") == null:
		return
	for d: Fight.Die in fight.hand:
		if d.is_free() and not d.locked and d.value >= 5:
			return
	for d: Fight.Die in fight.hand:
		if d.is_free() and not d.locked and d.value == 4:
			fight.nudge(d.id)
			return


func _place_pair(fight: Fight) -> void:
	for s: Fight.Slot in fight.slots:
		if s.row["accepts"] != "pair" or not s.dice.is_empty():
			continue
		var dice: Array[Fight.Die] = _by_value(fight)
		for i: int in dice.size():
			for j: int in range(i + 1, dice.size()):
				var a: Fight.Die = dice[i]
				var b: Fight.Die = dice[j]
				if a.value == b.value and fight.place(a.id, s.id):
					if fight.place(b.id, s.id):
						return
					fight.take_back(a.id)


## Free dice, highest value first, lowest id first on ties.
static func _by_value(fight: Fight) -> Array[Fight.Die]:
	var dice: Array[Fight.Die] = fight.hand.duplicate()
	dice.sort_custom(func(a: Fight.Die, b: Fight.Die) -> bool:
		return a.value > b.value or (a.value == b.value and a.id < b.id))
	return dice
