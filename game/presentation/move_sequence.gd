class_name MoveSequence
extends RefCounted
## How one move looks in Cobblemon's style (concepts_brief.md §12.5): a short sequence of
## pieces (Cobblemon's particle effects, or our own sprites in their style) for each phase of
## the real-time move. A move's sequence is the script in game/presentation/move_sequences/
## named after its id, or else its style's in move_sequences/styles/ (StyleSequence); each
## extends this class and overrides the phases it uses:
## - windup: on the user while it winds up (cut short by a feint, unless a piece keeps going);
## - fire: as the move is released, from the user;
## - flight: riding the projectile until it lands;
## - hit: when the move connects (melee moves included);
## - blast: an area move going off around the user.
## A phase adds pieces through SequenceSteps; Cobblemon's own action-effect scripts are only a
## reference for which pieces a move uses, since their 2–3 s turn-based timing doesn't fit.

const DIR := "res://game/presentation/move_sequences"
const STYLES_DIR := "res://game/presentation/move_sequences/styles"
const PHASES: Array[String] = ["windup", "fire", "flight", "hit", "blast"]


## Effect seconds per real second, to squeeze Cobblemon's slower pieces into our timings.
func speed() -> float:
	return 1.0


func windup(_steps: SequenceSteps) -> void:
	pass


func fire(_steps: SequenceSteps) -> void:
	pass


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(_steps: SequenceSteps) -> void:
	pass


func blast(_steps: SequenceSteps) -> void:
	pass


## The pieces a phase adds for a move of `type` (a Showdown type name).
func steps_for(phase: String, type := "") -> Array[Dictionary]:
	var steps := SequenceSteps.new()
	steps.type = type.to_lower()
	if PHASES.has(phase):
		call(phase, steps)
	return steps.pieces


## The move's own sequence, or null when it has none.
static func for_move(id: String) -> MoveSequence:
	return load_from(DIR, id)


## The sequence script `name` in `dir`, or null when there's none.
static func load_from(dir: String, name: String) -> MoveSequence:
	var path := dir.path_join(name + ".gd")
	if not ResourceLoader.exists(path):
		return null
	var script: Variant = load(path)
	if not script is GDScript:
		return null
	var sequence: Variant = (script as GDScript).new()
	return sequence if sequence is MoveSequence else null
