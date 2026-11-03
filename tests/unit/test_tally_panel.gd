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


func test_a_cleared_vault_lists_people_then_places_then_resources() -> void:
	assert_eq(_texts(_settle(Haul.CLEARED, _haul())), [
		["headline", "Cleared the vault"],
		["join", "Pearl diver joins · Nudge"],
		["landmark", "Café · yours to place"],
		["resource", "+7 driftwood"],
		["resource", "+2 pearls"],
	])


func test_a_wash_up_hatches_the_barrel_s_share_beside_what_was_kept() -> void:
	var settled: Dictionary = _settle(Haul.WASHED_UP, _haul())
	assert_eq(_texts(settled), [
		["headline", "Washed up"],
		["note", TallyPanel.BARREL],
		["below", "Pearl diver is still below · you can bring them up next delve"],
		["below", "Café is still below · you can win it next delve"],
		["resource", "+3 driftwood"],
		["resource", "+1 pearl"],
	])
	var resources: Array = TallyPanel.lines(data, settled).filter(
		func(line: Dictionary) -> bool: return line["kind"] == "resource").map(
		func(line: Dictionary) -> Array: return [line["amount"], line["name"], line["barrel"]])
	assert_eq(resources, [["+3", "driftwood", "−4 to the barrel"], ["+1", "pearl", "−1 to the barrel"]])


func test_an_empty_haul_still_says_so() -> void:
	assert_eq(_texts(_settle(Haul.SURFACED, Haul.new())), [["headline", "Surfaced"], ["note", TallyPanel.NOTHING]])
	assert_eq(_texts(_settle(Haul.WASHED_UP, Haul.new())), [["headline", "Washed up"], ["note", TallyPanel.NOTHING]],
		"no barrel note when it took nothing")


## Mara's #58 review: the barrel sounds on the tally, as the loss shows,
## so the town's uncovering stays a relief.
func test_the_barrel_sounds_on_a_wash_up_s_tally_only() -> void:
	Settings.reduce_motion = true
	var settled: Dictionary = _settle(Haul.WASHED_UP, _haul())
	var before: int = Soundscape.played.size()
	var panel: TallyPanel = TallyPanel.new()
	panel.setup(data, settled)
	add_child_autofree(panel)
	assert_eq(Soundscape.played.slice(-1), [Soundscape.barrel_for(int(settled["delve"]))] as Array[String])
	var surfaced: TallyPanel = TallyPanel.new()
	surfaced.setup(data, _settle(Haul.SURFACED, _haul()))
	add_child_autofree(surfaced)
	assert_eq(Soundscape.played.size(), mini(before + 1, 32), "no barrel after surfacing")
	Settings.reduce_motion = false


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
