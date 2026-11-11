class_name PlayerCamera
extends RefCounted
## The camera in play mode (concepts_brief.md §17, M4): behind and a little to the side of
## the player's fighter, looking past it towards the opponent, easing after them. Its
## forward direction makes movement input camera-relative.

const DISTANCE := 2.2
const HEIGHT := 0.9
const SHOULDER := 0.7
const FOV := 55.0
## How far along from the player to the opponent the camera looks.
const LOOK_SHARE := 0.5
## Share of the way to the new pose covered each frame.
const EASE := 0.15

var eye := Vector3.ZERO
## See CameraRig.limit.
var limit := INF
var target := Vector3.ZERO
var _placed := false


## The pose for a player and opponent standing at `player` and `foe` (floor positions).
static func pose(player: Vector3, foe: Vector3, player_height: float, foe_height: float) -> Dictionary:
	var toward := (foe - player) * Vector3(1, 0, 1)
	toward = toward.normalized() if toward.length_squared() > 1e-6 else Vector3.FORWARD
	var right := toward.cross(Vector3.UP).normalized()
	var back := DISTANCE + player_height * 0.9
	return {
		"eye": player - toward * back + right * SHOULDER + Vector3.UP * (HEIGHT + player_height * 0.6),
		"target": player.lerp(foe, LOOK_SHARE) + Vector3.UP * maxf(player_height, foe_height) * 0.45,
	}


func apply(camera: Camera3D, player: FighterView, foe: FighterView) -> void:
	var wanted := pose(player.position, foe.position, player.height, foe.height)
	if not _placed:
		eye = wanted.eye
		target = wanted.target
		_placed = true
	else:
		eye = eye.lerp(wanted.eye, EASE)
		target = target.lerp(wanted.target, EASE)
	camera.fov = FOV
	camera.look_at_from_position(CameraRig.keep_inside(eye, limit), target, Vector3.UP)


## The camera's forward direction on the floor, in simulation coordinates (x, z).
func forward() -> Vector2:
	var direction := target - eye
	return Vector2(direction.x, direction.z).normalized() if Vector2(direction.x, direction.z).length_squared() > 1e-6 else Vector2(0, 1)
