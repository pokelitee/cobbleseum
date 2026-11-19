class_name SubstituteDolls
extends Node3D
## How a Substitute (concepts_brief.md §9.5, rules version 39) looks: a small low-poly plush doll,
## in the fighter's likeness only by colour, standing just in front of it toward the foe while the
## decoy holds, fading in and out with the battle's state and wobbling when it takes a hit.

const FADE_FRAMES := 8
## The doll's size against the fighter's height (within limits), and how far in front it stands.
const HEIGHT_SHARE := 0.45
const HEIGHT_LIMITS := Vector2(0.45, 1.1)
const GAP := 0.25
const BODY := Color(0.93, 0.86, 0.66)
const PATCH := Color(0.78, 0.66, 0.45)
const WOBBLE_FRAMES := 12

var _dolls := {}
var _alphas := {}
var _hp_seen := {}
var _wobble := {}


## Shows a doll for each fighter out with a Substitute up, by one video frame. `fighters` and
## `views` line up (Battle.fighters and the views by index).
func sync(fighters: Array[Fighter], views: Array[FighterView], foes: Array[FighterView]) -> void:
	for index in fighters.size():
		var fighter := fighters[index]
		var up := fighter.substitute_ticks > 0 and not fighter.is_knocked_out()
		var alpha: float = move_toward(float(_alphas.get(index, 0.0)), 1.0 if up else 0.0, 1.0 / FADE_FRAMES)
		_alphas[index] = alpha
		if alpha <= 0.0 and not _dolls.has(index):
			continue
		var doll: Node3D = _dolls.get(index, null)
		if doll == null:
			doll = _doll()
			_dolls[index] = doll
		doll.visible = alpha > 0.0
		if not doll.visible:
			_hp_seen.erase(index)
			continue
		if fighter.substitute_hp < int(_hp_seen.get(index, fighter.substitute_hp)):
			_wobble[index] = WOBBLE_FRAMES
		_hp_seen[index] = fighter.substitute_hp
		var me := views[index]
		var toward := foes[index].global_position - me.global_position
		toward.y = 0.0
		toward = toward.normalized() if toward.length_squared() > 1e-6 else Vector3.FORWARD
		var size := clampf(me.height * HEIGHT_SHARE, HEIGHT_LIMITS.x, HEIGHT_LIMITS.y)
		doll.scale = Vector3.ONE * size * alpha
		doll.global_position = me.global_position + toward * (fighter.radius + GAP + size * 0.3)
		doll.look_at(doll.global_position - toward, Vector3.UP)
		var shake := int(_wobble.get(index, 0))
		if shake > 0:
			_wobble[index] = shake - 1
			doll.rotate_object_local(Vector3.FORWARD, sin(shake * 1.3) * 0.25 * shake / WOBBLE_FRAMES)


## A unit-high doll: a squat body, a round-cornered head with two ear tufts, two dot eyes and a
## stitched patch, all low-poly boxes.
func _doll() -> Node3D:
	var doll := Node3D.new()
	_box(doll, Vector3(0.62, 0.5, 0.5), Vector3(0, 0.25, 0), BODY)
	_box(doll, Vector3(0.56, 0.42, 0.46), Vector3(0, 0.71, 0), BODY)
	for x: float in [-0.19, 0.19]:
		_box(doll, Vector3(0.12, 0.2, 0.12), Vector3(x, 0.98, 0), PATCH)
		_box(doll, Vector3(0.07, 0.07, 0.02), Vector3(x * 0.6, 0.75, 0.24), Color(0.12, 0.1, 0.1))
	_box(doll, Vector3(0.2, 0.16, 0.02), Vector3(0.12, 0.27, 0.26), PATCH)
	add_child(doll)
	return doll


static func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	box.material_override = material
	parent.add_child(box)
