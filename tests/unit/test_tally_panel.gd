extends GutTest
## The return-to-town tally (specs/bridge.md section 6): what came up, what
## the barrel took in the same layout, who joins with their perk, and the
## landmark to place. It reads the settlement only.

var data: GameData


func before_all() -> void:
	data = GameData.load_dir()


func _haul() -> Haul:
	var haul: Haul = Haul.new()
	haul.add_resource("driftwood", 7)
	haul.add_resource("pearls", 2)
	haul.villagers.append("pearl_diver")
	haul.landmark = "cafe"
	return haul


func _settle(outcome: String, haul: Haul) -> Dictionary:
	var state: GameState = GameState.new(5)
	state.start_delve(data)
	return state.settle_delve(data, outcome, haul)


func _texts(settled: Dictionary) -> Array:
	return TallyPanel.lines(data, settled).map(func(line: Dictionary) -> Array: return [line["kind"], line["text"]])


func test_a_cleared_vault_lists_every_gain_who_joins_and_the_landmark() -> void:
	assert_eq(_texts(_settle(Haul.CLEARED, _haul())), [
		["headline", "Cleared the vault"],
		["gain", "+7 driftwood"],
		["gain", "+2 pearls"],
		["join", "Pearl diver joins · Nudge"],
		["landmark", "Café · yours to place"],
	])


func test_a_wash_up_shows_what_the_barrel_took_beside_what_was_kept() -> void:
	assert_eq(_texts(_settle(Haul.WASHED_UP, _haul())), [
		["headline", "Washed up"],
		["note", TallyPanel.BARREL],
		["gain", "+3 driftwood"],
		["lost", "4 driftwood · the barrel"],
		["gain", "+1 pearl"],
		["lost", "1 pearl · the barrel"],
		["lost", "Pearl diver · still below"],
		["lost", "Café · still below"],
	])


func test_an_empty_haul_still_says_so() -> void:
	assert_eq(_texts(_settle(Haul.SURFACED, Haul.new())), [["headline", "Surfaced"], ["note", TallyPanel.NOTHING]])
	assert_eq(_texts(_settle(Haul.WASHED_UP, Haul.new())), [["headline", "Washed up"], ["note", TallyPanel.NOTHING]],
		"no barrel note when it took nothing")


func test_continue_ignores_a_press_meant_for_the_screen_before() -> void:
	var panel: TallyPanel = TallyPanel.new()
	panel.setup(data, _settle(Haul.SURFACED, _haul()))
	add_child_autofree(panel)
	watch_signals(panel)
	panel.continue_button.pressed.emit()
	assert_signal_not_emitted(panel, "continued", "inside the guard")
	panel._shown_at -= TallyPanel.GUARD_MS
	panel.continue_button.pressed.emit()
	assert_signal_emitted(panel, "continued")
