class_name Haul
extends RefCounted
## What a delve is carrying back up (DM-8): resources, rescued villagers
## and a won landmark. Every amount is a whole number above zero; a
## resource that reaches 0 is dropped.

var resources: Dictionary[String, int] = {}
var villagers: Array[String] = []
var landmark: String = ""


func resource(id: String) -> int:
	return resources.get(id, 0)


## Adds a positive amount. Returns false for zero or negative amounts.
func add_resource(id: String, amount: int) -> bool:
	if amount <= 0 or id.is_empty():
		return false
	resources[id] = resource(id) + amount
	return true


## Takes `amount` out if the haul has it all (a vault stake). Never below 0.
func take_resource(id: String, amount: int) -> bool:
	if amount <= 0 or resource(id) < amount:
		return false
	resources[id] = resource(id) - amount
	if resources[id] == 0:
		resources.erase(id)
	return true


func is_empty() -> bool:
	return resources.is_empty() and villagers.is_empty() and landmark.is_empty()


## How a delve can end, as GameState.finish_delve() takes it.
const SURFACED: String = "surfaced"
const CLEARED: String = "cleared"
const WASHED_UP: String = "washed_up"
## The game closed mid-delve (Imogen's #6 audit): a wash-up with nothing kept.
const ABANDONED: String = "abandoned"
const OUTCOMES: Array[String] = [SURFACED, CLEARED, WASHED_UP, ABANDONED]


## What the town keeps of this haul after `outcome`: all of it after
## surfacing or clearing the vault, half the resources after washing up,
## nothing after an abandoned delve (or an unknown outcome).
func kept(outcome: String) -> Haul:
	match outcome:
		SURFACED, CLEARED:
			return copy()
		WASHED_UP:
			return halved()
	return Haul.new()


## What washing up keeps (DM-7): half of each resource, rounded down, and
## no villagers or landmark. Those go back below the tide.
func halved() -> Haul:
	var out: Haul = Haul.new()
	for id: String in resources:
		out.add_resource(id, resources[id] / 2)
	return out


func copy() -> Haul:
	var out: Haul = Haul.new()
	out.resources = resources.duplicate()
	out.villagers = villagers.duplicate()
	out.landmark = landmark
	return out


func to_dict() -> Dictionary:
	var resource_data: Dictionary = {}
	for id: String in resources:
		resource_data[id] = resources[id]
	return {"resources": resource_data, "villagers": villagers.duplicate(), "landmark": landmark}
