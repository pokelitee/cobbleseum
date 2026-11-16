class_name StyleSequence
extends MoveSequence
## The sequence for one of our visual styles (MoveStyle), played by every move of that style
## that has no sequence of its own (concepts_brief.md §12.5): Cobblemon's pieces borrowed from
## moves that look the part, palette-swapped to the move's type colour (TINT). By default a hit
## shows Cobblemon's impact in the type's own colours, and an area move a quake ring sweeping
## out from the user, so every style covers every phase; style scripts in
## move_sequences/styles/ add their own pieces on top.

const TINT := {"tint": true}
## Tinted melee accents on the foe: larger than Cobblemon draws them and nudged toward the
## camera, since our close melee spacing and the foe's own body otherwise hide them.
const ACCENT := {"tint": true, "scale": 1.6, "nudge": 0.35}


func hit(steps: SequenceSteps) -> void:
	steps.impact()


func blast(steps: SequenceSteps) -> void:
	steps.on_user("bulldoze_actorquake", "root", TINT)
	steps.on_user("bulldoze_actorspark", "root", TINT)


## TINT with extra options.
static func tinted(options: Dictionary) -> Dictionary:
	var merged := TINT.duplicate()
	merged.merge(options, true)
	return merged


## ACCENT with extra options.
static func accent(options: Dictionary) -> Dictionary:
	var merged := ACCENT.duplicate()
	merged.merge(options, true)
	return merged
