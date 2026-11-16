class_name SequenceSteps
extends RefCounted
## The pieces a MoveSequence phase plays, collected for CobblemonMoveFX.
## Each piece is a particle effect by id ("cobblemon:" is implied) at a locator on the user or
## the foe, with options:
## - aim: Cobblemon's target variables point at `aim_at` (a locator) on the other fighter;
## - delay: seconds after the phase starts; max: seconds before the piece stops emitting;
## - keep: a windup piece that runs on past the windup (and past a feint);
## - face_camera: the piece's front turns to the camera instead of the other fighter, for
##   pieces placed metres in front of their fighter, which our closer melee spacing would bury
##   inside the attacker;
## - tint: recolour the piece to the move's type colour (a palette swap), for borrowed pieces;
## - speed: multiplies the sequence's speed for this piece; scale: multiplies its size.

const LOCATORS: Array[String] = ["root", "middle", "target", "top", "special", "special_attack", "mouth",
	"physical", "hand", "hand_primary", "hand_secondary", "eye", "face", "jaw_lower"]

var pieces: Array[Dictionary] = []


## A piece on the user.
func on_user(effect: String, at := "middle", options := {}) -> SequenceSteps:
	return _add(effect, "user", at, options)


## A piece on the foe.
func on_foe(effect: String, at := "target", options := {}) -> SequenceSteps:
	return _add(effect, "foe", at, options)


func _add(effect: String, on: String, at: String, options: Dictionary) -> SequenceSteps:
	var piece := {"effect": effect, "on": on, "at": at}
	piece.merge(options, true)
	pieces.append(piece)
	return self
