class_name MoveFX
extends Node3D
## Type-themed move effects (concepts_brief.md §12.5), built from simple meshes and animated
## by video frame so renders are identical:
## - wind-up: a glowing ring at the attacker's feet
## - melee: a swipe crescent in front of the attacker
## - projectiles: a glowing core with a halo and a fading trail
## - hits: a flash, an expanding ring and shards flying out
## - misses: a small puff

const SWIPE_SHADER := preload("res://game/presentation/shaders/swipe.gdshader")
const WINDUP_FRAMES := 14
const SWIPE_FRAMES := 9
const BURST_FRAMES := 14
const PUFF_FRAMES := 10
const TRAIL_LENGTH := 7
const SHARDS := 8
const PROJECTILE_HEIGHT := 1.0

## Running effects: {"node": Node3D, "age": int, "frames": int, "kind": String, ...}.
var _effects: Array[Dictionary] = []
## Projectile visuals, matched to the simulation's projectile dictionaries by identity.
var _projectiles: Array[Dictionary] = []


func windup(attacker: FighterView, move: BattleMove) -> void:
	var ring := _mesh(_torus(0.6, 0.75), TypeColors.of(move.type), 0.8)
	ring.position = attacker.position + Vector3.UP * 0.05
	ring.scale = Vector3.ONE * attacker.height * 0.5
	add_child(ring)
	_effects.append({"node": ring, "age": 0, "frames": WINDUP_FRAMES, "kind": "windup", "base": ring.scale})


func swipe(attacker: FighterView, target: FighterView, move: BattleMove) -> void:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2.ONE * attacker.height * 1.4
	var material := ShaderMaterial.new()
	material.shader = SWIPE_SHADER
	material.set_shader_parameter("tint", TypeColors.of(move.type))
	quad.material_override = material
	add_child(quad)
	var toward := (target.position - attacker.position) * Vector3(1, 0, 1)
	var centre := attacker.position + toward.normalized() * attacker.height * 0.45 + Vector3.UP * attacker.height * 0.55
	quad.look_at_from_position(centre, centre + toward, Vector3.UP)
	quad.rotate_object_local(Vector3.FORWARD, deg_to_rad(-30))
	_effects.append({"node": quad, "age": 0, "frames": SWIPE_FRAMES, "kind": "swipe"})


func hit(defender: FighterView, move: BattleMove, big: bool) -> void:
	var colour := TypeColors.of(move.type)
	var centre := defender.position + Vector3.UP * defender.height * 0.5
	var size := defender.height * (0.6 if big else 0.4)
	var burst := Node3D.new()
	burst.position = centre
	add_child(burst)
	var flash := _mesh(_sphere(1.0), Color(1, 1, 1).lerp(colour, 0.4), 0.6)
	flash.scale = Vector3.ONE * size * 0.25
	burst.add_child(flash)
	var ring := _mesh(_torus(0.85, 1.0), colour, 0.9)
	ring.rotation_degrees.x = 90
	ring.scale = Vector3.ONE * size * 0.3
	burst.add_child(ring)
	# Shards in fixed directions so every render matches.
	var shards: Array[Dictionary] = []
	for i in SHARDS:
		var angle := TAU * i / SHARDS
		var direction := Vector3(cos(angle), 0.4 + 0.5 * float(i % 3) / 2.0, sin(angle)).normalized()
		var shard := _mesh(BoxMesh.new(), colour, 1.0)
		shard.scale = Vector3.ONE * size * 0.12
		burst.add_child(shard)
		shards.append({"node": shard, "direction": direction})
	_effects.append({"node": burst, "age": 0, "frames": BURST_FRAMES, "kind": "burst", "flash": flash,
		"ring": ring, "shards": shards, "size": size})


func miss(position: Vector3) -> void:
	var puff := _mesh(_sphere(1.0), Color(0.9, 0.9, 0.9), 0.5)
	puff.position = position + Vector3.UP * PROJECTILE_HEIGHT
	puff.scale = Vector3.ONE * 0.2
	add_child(puff)
	_effects.append({"node": puff, "age": 0, "frames": PUFF_FRAMES, "kind": "puff"})


## Matches projectile visuals to the simulation's projectiles and moves them.
func sync_projectiles(battle: Battle) -> void:
	var alive: Array[Dictionary] = []
	for projectile in battle.projectiles:
		var visual := _visual_for(projectile)
		if visual.is_empty():
			var move := battle.fighters[projectile.owner].moves[projectile.move]
			visual = _new_projectile(projectile, TypeColors.of(move.type))
		var position := Vector3(projectile.position.x, PROJECTILE_HEIGHT, projectile.position.y)
		visual.node.position = position
		visual.history.push_front(position)
		visual.history.resize(mini(visual.history.size(), TRAIL_LENGTH))
		for i in TRAIL_LENGTH:
			var ghost: MeshInstance3D = visual.trail[i]
			ghost.visible = i + 1 < visual.history.size()
			if ghost.visible:
				ghost.global_position = visual.history[i + 1]
		alive.append(visual)
	for visual in _projectiles:
		if not alive.has(visual):
			visual.node.queue_free()
	_projectiles = alive


## Advances every running effect by one video frame.
func next_frame() -> void:
	for effect in _effects.duplicate():
		effect.age += 1
		var t: float = float(effect.age) / effect.frames
		var node: Node3D = effect.node
		match effect.kind:
			"windup":
				node.scale = effect.base * (1.0 + 0.6 * t)
				_fade(node, 1.0 - t)
			"swipe":
				(node as MeshInstance3D).material_override.set_shader_parameter("progress", t)
			"burst":
				var flash: MeshInstance3D = effect.flash
				flash.scale = Vector3.ONE * effect.size * (0.25 + 0.35 * t)
				_fade(flash, 1.0 - t * 2.5)
				var ring: MeshInstance3D = effect.ring
				ring.scale = Vector3.ONE * effect.size * (0.3 + 1.4 * t)
				_fade(ring, 1.0 - t)
				for shard: Dictionary in effect.shards:
					shard.node.position = shard.direction * effect.size * 1.6 * t
					shard.node.rotation = Vector3(t * 6.0, t * 4.0, 0)
					_fade(shard.node, 1.0 - t)
			"puff":
				node.scale = Vector3.ONE * (0.2 + 0.5 * t)
				_fade(node, 0.5 * (1.0 - t))
		if effect.age >= effect.frames:
			node.queue_free()
			_effects.erase(effect)


func _visual_for(projectile: Dictionary) -> Dictionary:
	for visual in _projectiles:
		if is_same(visual.source, projectile):
			return visual
	return {}


func _new_projectile(projectile: Dictionary, colour: Color) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var core := _mesh(_sphere(Rules.PROJECTILE_RADIUS * 0.7), Color(1, 1, 1).lerp(colour, 0.3), 1.0)
	root.add_child(core)
	var halo := _mesh(_sphere(Rules.PROJECTILE_RADIUS * 1.4), colour, 0.35)
	root.add_child(halo)
	var trail: Array[MeshInstance3D] = []
	for i in TRAIL_LENGTH:
		var ghost := _mesh(_sphere(Rules.PROJECTILE_RADIUS * (1.0 - 0.12 * i)), colour, 0.5 * (1.0 - float(i) / TRAIL_LENGTH))
		ghost.top_level = true
		ghost.visible = false
		root.add_child(ghost)
		trail.append(ghost)
	return {"source": projectile, "node": root, "trail": trail, "history": []}


static func _mesh(mesh: Mesh, colour: Color, alpha: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(colour, alpha)
	material.set_meta("peak", alpha)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _fade(node: MeshInstance3D, alpha: float) -> void:
	var material: StandardMaterial3D = node.material_override
	material.albedo_color.a = clampf(alpha, 0.0, 1.0) * float(material.get_meta("peak", 1.0))


static func _sphere(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 16
	sphere.rings = 8
	return sphere


static func _torus(inner: float, outer: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 8
	return torus
