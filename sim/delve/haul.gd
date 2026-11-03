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


## What washing up keeps (DM-7): half of each resource, rounded down, and
## no villagers or landmark. Those go back below the tide.
func halved() -> Haul:
	var kept: Haul = Haul.new()
	for id: String in resources:
		kept.add_resource(id, resources[id] / 2)
	return kept


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
