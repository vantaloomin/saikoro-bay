class_name DialogueRunner
extends RefCounted
## Steps through one dialogue script for a screen: the current line, its
## responses, and the tags the screen reads ([#face=...], [#outfit=...]).
## The script talks only to `state` (for a date, the DateSession), never to
## the game, and the screen never reads the script's file itself.
##
## Calls are awaited. While one is in flight `busy` is true and further
## calls return the current line, so a double press can't skip a line or
## pick two responses.

var resource: DialogueResource
var state: Object
## The line on screen, or null once the script has ended.
var line: DialogueLine
var busy: bool = false
var _started: bool = false


func _init(script_resource: DialogueResource, script_state: Object) -> void:
	resource = script_resource
	state = script_state


## Starts at `cue`. Returns the first line, or null if there is none.
func start(cue: String) -> DialogueLine:
	if busy or resource == null:
		return line
	busy = true
	_started = true
	line = await resource.get_next_dialogue_line(cue, [state])
	busy = false
	return line


## Moves on: past a plain line, or down response `pick` (an index into
## line.responses, which must be allowed). Returns the new line, or null at
## the end. A pick that doesn't fit changes nothing.
func advance(pick: int = -1) -> DialogueLine:
	if busy or line == null or not _started:
		return line
	var next_id: String = line.next_id
	if not line.responses.is_empty():
		if pick < 0 or pick >= line.responses.size() or not (line.responses[pick] as DialogueResponse).is_allowed:
			return line
		next_id = (line.responses[pick] as DialogueResponse).next_id
	elif pick >= 0:
		return line
	busy = true
	line = await resource.get_next_dialogue_line(next_id, [state])
	busy = false
	return line


func is_over() -> bool:
	return _started and line == null and not busy


## The value of tag `key` ("face" for [#face=happy]) on `of`, or "".
static func tag(of: DialogueLine, key: String) -> String:
	if of == null:
		return ""
	for item: String in of.tags:
		if item.begins_with(key + "="):
			return item.substr(key.length() + 1)
	return ""
