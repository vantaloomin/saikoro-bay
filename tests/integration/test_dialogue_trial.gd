extends GutTest
## Dialogue Manager trial (M0): branching, conditions on game state,
## mutations, and content-level gating all work headless, typed, on 4.6.

const TRIAL: DialogueResource = preload("res://dialogue/trial/onsen_keeper_trial.dialogue")


class TrialState:
	extends RefCounted
	var villager_happy: bool = true
	var affection: int = 0
	var content_level: int = 0


func test_condition_picks_the_happy_line() -> void:
	var state: TrialState = TrialState.new()
	var line: DialogueLine = await TRIAL.get_next_dialogue_line("move_in", [state])
	assert_eq(line.character, "Onsen keeper")
	line = await TRIAL.get_next_dialogue_line(line.next_id, [state])
	assert_string_contains(line.text, "Close enough to the spring")


func test_condition_picks_the_unhappy_line() -> void:
	var state: TrialState = TrialState.new()
	state.villager_happy = false
	var line: DialogueLine = await TRIAL.get_next_dialogue_line("move_in", [state])
	line = await TRIAL.get_next_dialogue_line(line.next_id, [state])
	assert_string_contains(line.text, "a little far from the water")


func test_response_runs_its_mutation() -> void:
	var state: TrialState = TrialState.new()
	var line: DialogueLine = await TRIAL.get_next_dialogue_line("move_in", [state])
	while line != null and line.responses.is_empty():
		line = await TRIAL.get_next_dialogue_line(line.next_id, [state])
	assert_not_null(line)
	assert_eq(line.responses.size(), 2)
	assert_eq(line.responses[0].text, "I'll be there.")
	line = await TRIAL.get_next_dialogue_line(line.responses[0].next_id, [state])
	assert_eq(state.affection, 1)
	assert_string_contains(line.text, "keep it warm")


func test_content_level_gates_lines() -> void:
	var state: TrialState = TrialState.new()
	var sfw: DialogueLine = await TRIAL.get_next_dialogue_line("date_teaser", [state])
	assert_string_contains(sfw.text, "SFW build")
	state.content_level = 1
	var suggestive: DialogueLine = await TRIAL.get_next_dialogue_line("date_teaser", [state])
	assert_string_contains(suggestive.text, "Suggestive or above")
