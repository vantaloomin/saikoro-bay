extends GutTest
## Koban's vault: Beat the House (specs/delve-map.md section 6, 8a rule 3).

const NUDGE: Array[Dictionary] = [{"perk": "nudge", "source": "pearl_diver"}]

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()
	assert_eq(data.errors, PackedStringArray())


func _haul() -> Haul:
	var haul: Haul = Haul.new()
	haul.add_resource("driftwood", 20)
	haul.add_resource("pearls", 3)
	return haul


func _vault(haul: Haul = _haul(), seed_value: int = 5, perks: Array[Dictionary] = []) -> Vault:
	var vault: Vault = Vault.create(data, "fresh", "koban", RngStreams.new(seed_value), perks, haul)
	assert_not_null(vault)
	return vault


## Rolls, sets your dice and Koban's, and plays `hand` (die ids).
func _play_round(vault: Vault, yours: Array[int], house: Array[int], hand: Array[int] = [0, 1, 2]) -> void:
	if vault.state == Vault.State.WAGER:
		vault.roll()
	vault.house_hand.assign(house)
	for i: int in yours.size():
		vault.table.hand[i].value = yours[i]
	for die_id: int in hand:
		assert_true(vault.place(die_id, vault.hand().id))
	assert_true(vault.end_turn())


func _round_events(vault: Vault) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in vault.events:
		if event["type"] == "round":
			found.append(event)
	return found


# --- Hands -------------------------------------------------------------------------

func test_hands_rank_like_poker_dice() -> void:
	assert_eq(Vault.hand_rank([2, 2, 2] as Array[int]), Vault.THREE_KIND)
	assert_eq(Vault.hand_rank([5, 3, 4] as Array[int]), Vault.RUN)
	assert_eq(Vault.hand_rank([6, 1, 6] as Array[int]), Vault.PAIR)
	assert_eq(Vault.hand_rank([1, 3, 6] as Array[int]), Vault.HIGH_DIE)
	assert_gt(Vault.hand_score([1, 1, 1] as Array[int]), Vault.hand_score([4, 5, 6] as Array[int]), "three of a kind beats a run")
	assert_gt(Vault.hand_score([1, 2, 3] as Array[int]), Vault.hand_score([6, 6, 5] as Array[int]), "a run beats a pair")
	assert_gt(Vault.hand_score([2, 2, 1] as Array[int]), Vault.hand_score([6, 5, 3] as Array[int]), "a pair beats a high die")
	assert_gt(Vault.hand_score([4, 4, 6] as Array[int]), Vault.hand_score([5, 5, 2] as Array[int]), "ties break on the sum")
	assert_eq(Vault.hand_score([6, 6] as Array[int]), -1, "a hand needs 3 dice")


func test_the_house_wins_a_full_tie_and_an_empty_hand_loses() -> void:
	var vault: Vault = _vault()
	_play_round(vault, [4, 4, 6, 1], [6, 4, 4])
	assert_false(_round_events(vault)[0]["won"], "4-4-6 against 6-4-4: the house wins ties")
	_play_round(vault, [6, 6, 6, 6], [1, 2, 4], [0, 1])
	assert_false(_round_events(vault)[1]["won"], "two dice in the hand lose")
	assert_eq(vault.state, Vault.State.LOST)


func test_best_of_three() -> void:
	var vault: Vault = _vault()
	assert_eq(vault.round_number, 1)
	assert_eq(vault.house_hand.size(), 3, "Koban rolls openly before you wager")
	_play_round(vault, [5, 5, 5, 1], [1, 2, 4])
	_play_round(vault, [1, 2, 4, 1], [6, 6, 6])
	assert_eq(vault.state, Vault.State.WAGER, "one each: round 3")
	assert_eq(vault.round_number, 3)
	_play_round(vault, [2, 3, 4, 1], [6, 6, 1])
	assert_eq(vault.state, Vault.State.WON)
	assert_false(vault.roll())
	assert_false(vault.end_turn())


func test_you_play_only_after_the_wager() -> void:
	var vault: Vault = _vault()
	assert_false(vault.place(0, vault.hand().id), "roll first")
	assert_false(vault.end_turn())
	assert_true(vault.roll())
	assert_false(vault.roll())
	assert_eq(vault.raise_amount("driftwood"), 0, "too late to raise")


# --- The wager ------------------------------------------------------------------------

func test_a_raise_stakes_a_quarter_once_a_round() -> void:
	var haul: Haul = _haul()
	var vault: Vault = _vault(haul)
	assert_eq(vault.raise_amount("pearls"), 1, "a quarter of 3 rounds down, but at least 1")
	assert_eq(vault.raise_amount("koban_coins"), 0, "you need some to stake")
	assert_true(vault.raise("driftwood"))
	assert_eq(haul.resource("driftwood"), 15, "the stake leaves the haul")
	assert_eq(vault.stake, {"driftwood": 5} as Dictionary[String, int])
	assert_false(vault.raise("pearls"), "one raise a round")


func test_a_won_round_pays_twice_the_stake_and_a_lost_one_keeps_it() -> void:
	var haul: Haul = _haul()
	var vault: Vault = _vault(haul)
	vault.raise("driftwood")
	_play_round(vault, [6, 6, 6, 1], [1, 2, 4])
	assert_eq(haul.resource("driftwood"), 25, "20 - 5 + 10")
	assert_true(vault.stake.is_empty())
	vault.raise("driftwood")
	assert_eq(haul.resource("driftwood"), 19, "a quarter of 25 is 6")
	_play_round(vault, [1, 2, 4, 1], [3, 3, 3])
	assert_eq(haul.resource("driftwood"), 19, "the stake is gone")


func test_stakes_always_add_up() -> void:
	# Conservation (8a rule 3): what's left = what came in - every stake +
	# twice each won stake, whatever the bot does.
	for s: int in range(1, 121):
		var haul: Haul = _haul()
		var start: Dictionary = haul.resources.duplicate()
		var perks: Array[Dictionary] = []
		if s % 2 == 0:
			perks = NUDGE
		var vault: Vault = _vault(haul, s, perks)
		VaultBot.new().play_vault(vault)
		var expected: Dictionary = start.duplicate()
		for event: Dictionary in vault.events:
			if event["type"] == "raise":
				expected[event["resource"]] -= event["amount"]
			elif event["type"] == "stake" and event["won"]:
				expected[event["resource"]] += event["amount"]
		for id: String in expected:
			assert_eq(haul.resource(id), expected[id], "seed %d, %s" % [s, id])
			assert_gte(haul.resource(id), 0)


# --- Randomness and replay ----------------------------------------------------------

func test_koban_rolls_on_her_own_stream() -> void:
	var calm: Vault = _vault(_haul(), 9)
	var busy: Vault = _vault(_haul(), 9)
	calm.roll()
	busy.roll()
	busy.reroll(0)
	for v: Vault in [calm, busy]:
		for die_id: int in [1, 2, 3]:
			v.place(die_id, v.hand().id)
		v.end_turn()
	assert_eq(busy.house_hand, calm.house_hand, "your reroll doesn't change her next hand")


func test_a_vault_replays_from_its_seed_and_moves() -> void:
	var vault: Vault = _vault(_haul(), 31, NUDGE)
	VaultBot.new().play_vault(vault)
	var haul: Haul = _haul()
	var again: Vault = Vault.create(data, "fresh", "koban", RngStreams.new(31), NUDGE, haul)
	assert_true(again.apply_moves(vault.moves))
	assert_eq(again.state, vault.state)
	assert_eq(again.events, vault.events)
	assert_eq(haul.to_dict(), vault.haul.to_dict())


func test_a_vault_allows_one_nudge_in_all() -> void:
	var vault: Vault = _vault(_haul(), 5, NUDGE)
	vault.roll()
	for i: int in 4:
		vault.table.hand[i].value = 2
	assert_true(vault.nudge(0))
	assert_false(vault.nudge(1), "one nudge, not one a round")
	var copy: Vault = vault.planning_copy()
	assert_eq(copy.nudges_used, 1, "the copy knows it's spent")
	for die_id: int in [0, 1, 2]:
		vault.place(die_id, vault.hand().id)
	vault.end_turn()
	if vault.is_over():
		return
	vault.roll()
	assert_eq(vault.table.nudges_left, 0, "the next round has none")
	vault.table.hand[0].value = 2
	assert_false(vault.nudge(0))


func test_the_vault_reads_its_nudge_allowance_from_data() -> void:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	var vaults: Dictionary = JSON.parse_string(texts["vaults"])
	(vaults["items"] as Array)[0]["nudges_per_vault"] = 0
	texts["vaults"] = JSON.stringify(vaults)
	var no_nudges: GameData = GameData.new()
	no_nudges.load_texts(texts)
	assert_eq(no_nudges.errors, PackedStringArray())
	var vault: Vault = Vault.create(no_nudges, "fresh", "koban", RngStreams.new(5), NUDGE, _haul())
	vault.roll()
	vault.table.hand[0].value = 2
	assert_eq(vault.nudges_per_vault, 0)
	assert_false(vault.nudge(0), "a vault set to 0 nudges allows none")


# --- Planning copies (Imogen, #27) ------------------------------------------------------

func test_a_planning_copy_previews_a_round_on_its_own_haul() -> void:
	var haul: Haul = _haul()
	var rng: RngStreams = RngStreams.new(11)
	var vault: Vault = Vault.create(data, "fresh", "koban", rng, [], haul)
	vault.raise("driftwood")
	vault.roll()
	vault.house_hand.assign([1, 2, 4] as Array[int])
	for i: int in 3:
		vault.table.hand[i].value = 6
		vault.place(i, vault.hand().id)
	var rng_before: Dictionary = rng.to_dict()
	var moves_before: int = vault.moves.size()
	var copy: Vault = vault.planning_copy()
	assert_true(copy.end_turn())
	assert_eq(copy.rounds_won, 1)
	assert_eq(copy.haul.resource("driftwood"), 25, "the copy's haul gets the stake back twice")
	assert_eq(haul.resource("driftwood"), 15, "the run's haul still has the stake out")
	assert_eq(copy.state, Vault.State.WAGER, "the round is scored")
	assert_eq(copy.round_number, vault.round_number, "but the copy never starts the next one")
	assert_false(copy.end_turn(), "a copy scores once")
	assert_eq(rng.to_dict(), rng_before, "the preview draws nothing")
	assert_eq(vault.moves.size(), moves_before)
	assert_eq(vault.state, Vault.State.PLAYER_TURN)


func test_a_planning_copy_cant_roll_or_reroll() -> void:
	var haul: Haul = _haul()
	var vault: Vault = _vault(haul)
	var copy: Vault = vault.planning_copy()
	assert_true(copy.raise("driftwood"), "a preview raise works on the copy")
	assert_eq(haul.resource("driftwood"), 20, "and leaves the run's haul alone")
	assert_false(copy.roll())
	vault.roll()
	assert_ne(vault.planning_copy().reroll_refusal(0), "")
	assert_false(vault.planning_copy().reroll(0))


func test_moves_before_the_roll_say_why() -> void:
	var vault: Vault = _vault()
	assert_eq(vault.place_refusal(0, vault.hand().id), "Roll first.")
	assert_eq(vault.reroll_refusal(0), "Roll first.")
	vault.roll()
	assert_eq(vault.place_refusal(0, vault.hand().id), "")


# --- The bot ---------------------------------------------------------------------------

func test_the_bot_plays_its_best_three_dice() -> void:
	var vault: Vault = _vault()
	vault.roll()
	vault.house_hand.assign([1, 1, 2] as Array[int])
	for i: int in 4:
		vault.table.hand[i].value = [3, 6, 5, 4][i]
	var best: Dictionary = VaultBot.new().best_hand(vault)
	assert_eq(best["dice"], [1, 2, 3], "4-5-6, the top run")


func test_the_bot_raises_only_against_a_weak_hand() -> void:
	var weak: Vault = _vault()
	weak.house_hand.assign([1, 3, 5] as Array[int])
	VaultBot.new().play_round(weak)
	assert_eq(weak.events.filter(func(e: Dictionary) -> bool: return e["type"] == "raise").size(), 1)
	var strong: Vault = _vault()
	strong.house_hand.assign([4, 4, 2] as Array[int])
	VaultBot.new().play_round(strong)
	assert_eq(strong.events.filter(func(e: Dictionary) -> bool: return e["type"] == "raise").size(), 0)


func test_rank_always_beats_the_sum_even_with_big_faces() -> void:
	assert_gt(Vault.hand_score([1, 1, 2] as Array[int]), Vault.hand_score([40, 41, 50] as Array[int]),
		"a pair of 1s beats any high die, whatever the faces")


# --- Failing closed (Imogen's #27 audit) ----------------------------------------------

func _without_vaults() -> GameData:
	var texts: Dictionary[String, String] = {}
	for table_name: String in GameData.TABLES:
		texts[table_name] = FileAccess.get_file_as_string("res://data/%s.json" % table_name)
	texts["vaults"] = JSON.stringify({"schema": 1, "items": []})
	var broken: GameData = GameData.new()
	broken.load_texts(texts)
	return broken


func test_the_data_needs_kobans_vault() -> void:
	assert_has(_without_vaults().errors, "vaults: needs the \"koban\" vault (the delve ends there)")


func test_no_delve_starts_without_a_vault_to_end_at() -> void:
	var broken: GameData = _without_vaults()
	assert_false(Vault.can_open(broken, "fresh", "koban"))
	assert_null(Vault.create(broken, "fresh", "koban", RngStreams.new(1), [], Haul.new()))
	assert_null(DelveRun.create(broken, 1, [], ["pearl_diver"], ["cafe"], 0))


func test_the_last_room_wont_strand_you_at_a_vault_that_cant_open() -> void:
	var run: DelveRun = DelveRun.create(data, 4, [], ["pearl_diver"], ["cafe"], 0)
	for guard: int in 200:
		if run.step == DelveRun.Step.CHOOSE_ROOM:
			run.choose(run.reachable()[0])
		elif run.step == DelveRun.Step.LANDING:
			run.go_deeper()
		elif run.step == DelveRun.Step.IN_ROOM:
			var last: bool = run.floor_index == run.map.floors.size() - 1 and run.row == run.map.rows_in_floor(run.floor_index) - 1
			if run.fight != null:
				GreedyBot.new().play_fight(run.fight)
			if run.room != null:
				RoomBot.new().play_room(run.room)
			if last and not run.is_over():
				run._data = _without_vaults()
				assert_false(run.finish_room(), "refused, not stranded")
				assert_push_error("can't open the vault")
				assert_eq(run.step, DelveRun.Step.IN_ROOM)
				return
			run.finish_room()
		if run.is_over():
			run = DelveRun.create(data, 4 + guard, [], ["pearl_diver"], ["cafe"], 0)
	fail_test("never reached the last room")
