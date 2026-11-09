class_name SimpleAI
extends RefCounted
## Milestone 1 controller: walks into range of its ready moves and uses the strongest one.
## The utility AI (concepts_brief.md §11) replaces it in milestone 3.

var random: SimRandom


func _init(stream: SimRandom) -> void:
	random = stream


func decide(battle: Battle, side: int) -> Dictionary:
	var me := battle.fighters[side]
	var foe := battle.fighters[1 - side]
	var gap := me.position.distance_to(foe.position) - me.radius - foe.radius
	var best := -1
	var best_power := -1
	var desired_gap := INF
	for i in me.moves.size():
		if not me.move_ready(i):
			continue
		var move := me.moves[i]
		desired_gap = minf(desired_gap, move.reach() * 0.8)
		# Ties go to a random pick so the order of the moveset never decides.
		if gap <= move.reach() and (move.power > best_power or (move.power == best_power and random.chance(0.5))):
			best = i
			best_power = move.power
	if best >= 0:
		return {"use": best, "move": Vector2.ZERO}
	if desired_gap == INF:
		desired_gap = Rules.MELEE_REACH  # everything on cooldown: stay close
	var toward := (foe.position - me.position).normalized()
	return {"use": -1, "move": toward if gap > desired_gap else Vector2.ZERO}
