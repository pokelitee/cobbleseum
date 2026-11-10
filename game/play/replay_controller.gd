class_name ReplayController
extends RefCounted
## Plays back one side's recorded intents (concepts_brief.md §10), one per tick, so a battle
## with a player replays exactly from its spec.

var intents: Array


func _init(recorded: Array) -> void:
	intents = recorded


func decide(battle: Battle, _side: int) -> Dictionary:
	return Battle.intent_from_log(intents[battle.tick]) if battle.tick < intents.size() else {}
