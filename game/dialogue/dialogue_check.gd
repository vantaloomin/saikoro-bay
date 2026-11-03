class_name DialogueCheck
extends RefCounted
## Holds dialogue scripts to the rules the game relies on, so a script that
## breaks one fails CI instead of a playtest.
##
## Static rules, on the compiled file:
##   - expressions use only `names` (for dates, DateSession.NAMES): no
##     autoloads, no "using", no function calls, so a script can't reach
##     the save or Game around the date session;
##   - the only write is "affection +=" (no other name, no "=" or "-=");
##   - no inline [set], [do] or [if] in text, which run unchecked;
##   - no content_level: these scripts ship in the SFW build;
##   - every speaker is a villager id or one of EXTRA_SPEAKERS, so names
##     can change in data without touching scripts;
##   - every [#face=...] tag names one of FACES, the expression ids the
##     whole cast shares (art-direction portrait pipeline, section 3).
## Walked rules, for a date, from its "date" cue: every combination of
## spot, happy or not, first date or repeat and content level, down every
## response, must reach the end, offer at least one choice, and never pick
## a random line (a date plays the same way twice).

## Speakers other than villagers.
const EXTRA_SPEAKERS: Array[String] = ["koban"]
## Portrait expressions, the same ids for everyone.
const FACES: Array[String] = ["neutral", "happy", "tease", "flustered", "sad", "surprised"]
## A path longer than this many lines is taken as a loop.
const MAX_STEPS: int = 400
## More paths than this is taken as a loop too (each loop back offers the
## way out again).
const MAX_WALKS: int = 2000

static var _INLINE: RegEx = RegEx.create_from_string("\\[\\s*/?\\s*(set|do!?|if|elif|else)\\b")

const _NAME_TOKENS: Array[String] = ["variable", "function", "dictionary_reference", "dictionary_nested_reference"]


## Problems with `resource`'s compiled lines, or [] if it follows the static
## rules. `speakers` are the allowed speaker ids.
##
## Every comparison here goes through str(), never a bare ==, so no token
## can raise a runtime error and turn the check into "no problems" (Imogen's
## PR 1 audit, finding 1). The test also fails on any engine error.
static func static_problems(resource: DialogueResource, names: Array[String], speakers: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	var where: String = resource.resource_path.get_file()
	if not resource.using_states.is_empty():
		out.append("%s: \"using %s\" reaches outside the date" % [where, ", ".join(resource.using_states)])
	for id: Variant in resource.lines:
		var line: Variant = resource.lines[id]
		if not line is Dictionary:
			out.append("%s line %s: not a compiled line" % [where, id])
			continue
		var line_dict: Dictionary = line
		var character: String = str(line_dict.get("character", ""))
		if not character.is_empty() and not speakers.has(character) and not EXTRA_SPEAKERS.has(character):
			out.append("%s line %s: unknown speaker \"%s\" (use a villager id)" % [where, id, character])
		# Dialogue Manager reads [set], [do] and [if] inside text only when
		# the line plays, so this check can't see their names: none at all.
		if _INLINE.search(str(line_dict.get("text", ""))) != null:
			out.append("%s line %s: inline [set], [do] and [if] run unchecked; use a set line or an if block" % [where, id])
		for tag: Variant in line_dict.get("tags", []) as Array:
			var face: String = str(tag).trim_prefix("face=")
			if str(tag).begins_with("face=") and not FACES.has(face):
				out.append("%s line %s: face \"%s\" isn't one of %s" % [where, id, face, ", ".join(FACES)])
		for token: Dictionary in _tokens(line_dict):
			var kind: String = str(token.get("type", ""))
			var value: String = str(token.get("function", token.get("variable", token.get("value", ""))))
			if kind == "function":
				out.append("%s line %s: calls %s(), and scripts can't call functions" % [where, id, value])
			elif _NAME_TOKENS.has(kind) and value == "content_level":
				out.append("%s line %s: content_level isn't for res://dialogue scripts, which ship in the SFW build" % [where, id])
			elif _NAME_TOKENS.has(kind) and not names.has(value):
				out.append("%s line %s: uses \"%s\", which isn't one of %s" % [where, id, value, ", ".join(names)])
		# The only write a script may make is "affection +=", in a line's
		# mutation, an inline [set ...] or a multi-assignment alike.
		for expression: Array in _expressions(line_dict):
			for index: int in expression.size():
				var token: Variant = expression[index]
				if not (token is Dictionary and str((token as Dictionary).get("type", "")) == "assignment"):
					continue
				var target: Variant = expression[index - 1] if index > 0 else null
				var ok: bool = str((token as Dictionary).get("value", "")) == "+=" and target is Dictionary \
					and str((target as Dictionary).get("type", "")) == "variable" and str((target as Dictionary).get("value", "")) == "affection"
				if not ok:
					out.append("%s line %s: the only write a script may make is \"affection += n\"" % [where, id])
	return out


## Every expression (a list of tokens) inside a compiled line.
static func _expressions(value: Variant) -> Array[Array]:
	var out: Array[Array] = []
	if value is Array:
		var list: Array = value
		if list.any(func(item: Variant) -> bool: return item is Dictionary and (item as Dictionary).has("type") and (item as Dictionary).has("i")):
			out.append(list)
		for item: Variant in list:
			out.append_array(_expressions(item))
	elif value is Dictionary:
		for key: Variant in value as Dictionary:
			out.append_array(_expressions((value as Dictionary)[key]))
	return out


## Every expression token inside a compiled line, however deeply nested.
static func _tokens(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Dictionary:
		var dict: Dictionary = value
		if _NAME_TOKENS.has(str(dict.get("type", ""))):
			out.append(dict)
		for key: Variant in dict:
			out.append_array(_tokens(dict[key]))
	elif value is Array:
		for item: Variant in value as Array:
			out.append_array(_tokens(item))
	return out


## One walk result: the responses picked, how it ended, and what it earned.
class Walk:
	extends RefCounted
	var path: Array[int] = []
	var ended: bool = false
	var choices: int = 0
	var gained: int = 0
	var speakers: Array[String] = []
	var texts: Array[String] = []


## Plays `cue` down every response path, each time with a fresh session
## from `make_session` (a Callable returning the state object the script
## reads). Returns one Walk per path; a path that hasn't ended after
## `max_steps` lines is cut off with ended false. Awaits the dialogue manager.
static func walk_all(resource: DialogueResource, cue: String, make_session: Callable,
		max_steps: int = MAX_STEPS) -> Array[Walk]:
	var out: Array[Walk] = []
	var pending: Array[Array] = [[]]
	while not pending.is_empty() and out.size() < MAX_WALKS:
		var forced: Array = pending.pop_back()
		var walk: Walk = Walk.new()
		var session: Object = make_session.call()
		var line: DialogueLine = await resource.get_next_dialogue_line(cue, [session])
		var steps: int = 0
		while line != null and steps < max_steps:
			steps += 1
			walk.speakers.append(line.character)
			walk.texts.append(line.text)
			var next_id: String = line.next_id
			if not line.responses.is_empty():
				walk.choices += 1
				var allowed: Array[int] = []
				for index: int in line.responses.size():
					if (line.responses[index] as DialogueResponse).is_allowed:
						allowed.append(index)
				if allowed.is_empty():
					break
				var pick: int = allowed[0]
				var depth: int = walk.path.size()
				if depth < forced.size():
					pick = forced[depth]
				else:
					for other: int in allowed.slice(1):
						var branch: Array = walk.path.duplicate()
						branch.append(other)
						pending.append(branch)
				walk.path.append(pick)
				next_id = (line.responses[pick] as DialogueResponse).next_id
			line = await resource.get_next_dialogue_line(next_id, [session])
		walk.ended = line == null
		if session.get("affection") != null and session.has_method("gained"):
			walk.gained = session.call("gained")
		out.append(walk)
	return out


## Lines a date's raw graph can reach from its cue that pick at random
## ("%" lines). A date must play the same way twice, so this should be [].
static func random_lines(resource: DialogueResource, cue: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var start: String = str(resource.cues.get(cue, ""))
	var seen: Dictionary = {}
	var todo: Array[String] = [start]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		if id.is_empty() or seen.has(id) or not resource.lines.has(id):
			continue
		seen[id] = true
		var line: Dictionary = resource.lines[id]
		if line.has("siblings") or str(line.get("type", "")) == "random":
			out.append(id)
		for key: String in ["next_id", "next_sibling_id", "next_id_after"]:
			todo.append(str(line.get(key, "")))
		for response: Variant in line.get("responses", []) as Array:
			todo.append(str(response))
	return out
