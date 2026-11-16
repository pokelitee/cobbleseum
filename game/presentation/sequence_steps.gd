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
## - speed: multiplies the sequence's speed for this piece; scale: multiplies its size;
## - nudge: moves the piece toward the camera by that share of its fighter's height, so the
##   fighter's own body doesn't hide it.

const LOCATORS: Array[String] = ["root", "middle", "target", "top", "special", "special_attack", "mouth",
	"physical", "hand", "hand_primary", "hand_secondary", "eye", "face", "jaw_lower"]

## Types Cobblemon has a hit impact piece for.
const IMPACT_TYPES: Array[String] = ["bug", "dark", "dragon", "electric", "fairy", "fighting", "fire", "flying",
	"ghost", "grass", "ground", "ice", "normal", "poison", "psychic", "rock", "steel", "water"]

var pieces: Array[Dictionary] = []
## The move's type in lower case ("fire"), for pieces named by type.
var type := ""


## A piece on the user.
func on_user(effect: String, at := "middle", options := {}) -> SequenceSteps:
	return _add(effect, "user", at, options)


## A piece on the foe.
func on_foe(effect: String, at := "target", options := {}) -> SequenceSteps:
	return _add(effect, "foe", at, options)


## Cobblemon's hit impact in the move's type colours (generic/impact_<type>), on the foe;
## Normal's for a type it has none for.
func impact(options := {}) -> SequenceSteps:
	return on_foe("impact_" + (type if IMPACT_TYPES.has(type) else "normal"), "target", options)


func _add(effect: String, on: String, at: String, options: Dictionary) -> SequenceSteps:
	var piece := {"effect": effect, "on": on, "at": at}
	piece.merge(options, true)
	pieces.append(piece)
	return self
