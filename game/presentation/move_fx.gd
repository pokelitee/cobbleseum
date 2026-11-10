class_name MoveFX
extends Node3D
## Move effects (concepts_brief.md §12.5), drawn per MoveStyle in the move's type colour and
## built from simple meshes animated by video frame, so renders are identical.
## - wind-up: a ring at the attacker's feet, plus a charging glow for ranged styles
## - melee: strike (crescent), slash (claw marks), punch (shockwave star), kick (low arc),
##   bite (closing fangs), rush (speed lines and dust)
## - ranged: orb, bullet, beam, bolt (lightning), stream (breath and spray), pulse, sound,
##   wind, powder, skyfall (drops onto the target), erupt (spikes from the ground),
##   quake (ground wave), mind (glow on the target), explosion
## - hits: a flash, a ring and shards, plus an accent for some styles
## Flat effects (crescents, claw marks, rings) face the camera when they spawn, so no shot
## sees them edge-on. A ranged move that hits on the tick it fires never shows a
## projectile, so point_blank() draws a short version of its style instead.

const SWIPE_SHADER := preload("res://game/presentation/shaders/swipe.gdshader")
const WINDUP_FRAMES := 14
const SWIPE_FRAMES := 9
const BURST_FRAMES := 14
const PUFF_FRAMES := 10
const STRIKE_FRAMES := 12
const FADE_FRAMES := 8
const TRAIL_LENGTH := 7
const SHARDS := 8
const PROJECTILE_HEIGHT := 1.0
## Skyfall moves drop from this height; erupt and quake emit something every N frames.
const SKY_HEIGHT := 7.0
const EMIT_EVERY := 2
const BOLT_SEGMENTS := 9
const POWDER_MOTES := 12
const AURA_FRAMES := 20
## Melee effects are at least this big, so small targets still show them.
const MIN_MELEE_SIZE := 1.4
## How far flat effects sit in front of the target, toward the camera, as a share of their size.
const CAMERA_NUDGE := 0.35
const CHARGING: Array[String] = ["beam", "bolt", "stream", "pulse", "sound", "mind", "explosion", "orb", "bullet"]

## Move id -> style, from MoveStyle; moves not listed use their kind's default.
var styles: Dictionary = {}
## Running effects: {"node": Node3D, "age": int, "frames": int, "kind": String, ...}.
var _effects: Array[Dictionary] = []
## Projectile visuals, matched to the simulation's projectile dictionaries by identity.
var _projectiles: Array[Dictionary] = []
var _frame := 0


func style_of(move: BattleMove) -> String:
	return styles.get(move.id, "strike" if move.kind == BattleMove.Kind.MELEE else "orb")


func windup(attacker: FighterView, move: BattleMove) -> void:
	var colour := TypeColors.of(move.type)
	var ring := _mesh(_torus(0.6, 0.75), colour, 0.8)
	ring.position = attacker.position + Vector3.UP * 0.05
	ring.scale = Vector3.ONE * attacker.height * 0.5
	add_child(ring)
	_effects.append({"node": ring, "age": 0, "frames": WINDUP_FRAMES, "kind": "grow", "base": ring.scale, "growth": 0.6})
	var style := style_of(move)
	if style in CHARGING:
		var glow := _mesh(_sphere(1.0), Color.WHITE.lerp(colour, 0.5), 0.7)
		glow.position = _front(attacker, 0.6)
		add_child(glow)
		_effects.append({"node": glow, "age": 0, "frames": WINDUP_FRAMES, "kind": "charge",
			"size": 0.18 + 0.12 * attacker.height})
	elif style == "rush":
		_dust(attacker.position, colour, attacker.height * 0.6)


## A melee move landing (or whiffing) on `target`, drawn in the move's style.
func melee(attacker: FighterView, target: FighterView, move: BattleMove) -> void:
	var colour := TypeColors.of(move.type)
	var toward := ((target.position - attacker.position) * Vector3(1, 0, 1)).normalized()
	var chest := target.position + Vector3.UP * target.height * 0.55
	var size := maxf(target.height, MIN_MELEE_SIZE)
	match style_of(move):
		"slash":
			_slash(chest, size, colour)
		"punch":
			_punch(chest, size, colour)
		"kick":
			_swipe(chest - Vector3.UP * target.height * 0.2, size * 1.5, colour, 200.0)
		"bite":
			_bite(chest, size, colour)
		"rush":
			_rush(attacker, toward, colour)
			_punch(chest, size * 0.8, colour)
		_:
			_swipe(chest, size * 1.3, colour, 30.0)


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
	_face_camera(burst)
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
	match style_of(move):
		"mind":
			for i in 3:
				var halo := _mesh(_torus(0.9, 1.0), colour, 0.7)
				halo.position = centre
				halo.rotation = Vector3(deg_to_rad(60 * i), deg_to_rad(40 * i), 0)
				halo.scale = Vector3.ONE * defender.height * 0.5
				add_child(halo)
				_effects.append({"node": halo, "age": 0, "frames": BURST_FRAMES, "kind": "grow", "base": halo.scale, "growth": 0.8})
		"quake", "erupt":
			_dust(defender.position, colour, defender.height)


func miss(position: Vector3) -> void:
	var puff := _mesh(_sphere(1.0), Color(0.9, 0.9, 0.9), 0.5)
	puff.position = position + Vector3.UP * PROJECTILE_HEIGHT
	puff.scale = Vector3.ONE * 0.2
	add_child(puff)
	_effects.append({"node": puff, "age": 0, "frames": PUFF_FRAMES, "kind": "puff"})


## A ranged move that hit on the tick it fired, so no projectile was ever shown: draws a
## short version of its style between the fighters.
func point_blank(attacker: FighterView, target: FighterView, move: BattleMove) -> void:
	var colour := TypeColors.of(move.type)
	var from := _front(attacker, 0.6)
	var to := target.position + Vector3.UP * target.height * 0.55
	var ground := Vector3(target.position.x, 0, target.position.z)
	match style_of(move):
		"beam":
			_line(from, to, colour, false)
		"bolt":
			_line(from, to, colour, true)
		"stream":
			for i in 4:
				_cloud(from.lerp(to, (i + 1) / 5.0), colour, 0.35 + 0.12 * i)
		"skyfall":
			var rock := _mesh(_sphere(Rules.PROJECTILE_RADIUS * 2.0), Color.WHITE.lerp(colour, 0.6), 1.0)
			add_child(rock)
			_effects.append({"node": rock, "age": 0, "frames": FADE_FRAMES, "kind": "drop", "origin": ground + Vector3.UP * 0.4})
		"erupt":
			_spike(ground, colour)
		"quake":
			_dust(ground, colour, target.height)
		"explosion":
			_cloud(from, colour, 2.5)
		"mind":
			pass  # the hit accent already rings the target
		_:
			_cloud(from.lerp(to, 0.5), colour, 0.45)


## Rings drifting up a fighter (stat rise, heal) or down it (stat drop).
func aura(view: FighterView, colour: Color, rising: bool) -> void:
	for i in 3:
		var ring := _mesh(_torus(0.85, 1.0), Color.WHITE.lerp(colour, 0.6), 0.8)
		ring.scale = Vector3.ONE * maxf(view.height, 1.0) * 0.45
		add_child(ring)
		var low := view.position + Vector3.UP * view.height * 0.1
		var high := view.position + Vector3.UP * view.height * 1.0
		_effects.append({"node": ring, "age": -i * 4, "frames": AURA_FRAMES, "kind": "drift",
			"from": low if rising else high, "to": high if rising else low})


## A dodge: speed lines streaming behind the fighter and a puff of dust.
func dodge(view: FighterView, direction: Vector2) -> void:
	_rush(view, Vector3(direction.x, 0, direction.y), Color(0.85, 0.95, 1.0))


## Matches projectile visuals to the simulation's projectiles and moves them.
func sync_projectiles(battle: Battle) -> void:
	var alive: Array[Dictionary] = []
	for projectile in battle.projectiles:
		var visual := _visual_for(projectile)
		if visual.is_empty():
			var move := battle.fighters[projectile.owner].moves[projectile.move]
			var target: Vector2 = battle.fighters[1 - int(projectile.owner)].position
			visual = _new_projectile(projectile, move, target)
		_update_projectile(visual, Vector3(projectile.position.x, PROJECTILE_HEIGHT, projectile.position.y))
		alive.append(visual)
	for visual in _projectiles:
		if not alive.has(visual):
			_end_projectile(visual)
	_projectiles = alive


## Advances every running effect by one video frame.
func next_frame() -> void:
	_frame += 1
	for effect in _effects.duplicate():
		effect.age += 1
		var t: float = float(effect.age) / effect.frames
		var node: Node3D = effect.node
		match effect.kind:
			"grow":
				node.scale = effect.base * (1.0 + effect.growth * t)
				_fade_all(node, 1.0 - t)
			"charge":
				node.scale = Vector3.ONE * effect.size * (0.3 + 0.7 * t)
				_fade_all(node, 1.0 if t < 0.8 else (1.0 - t) * 5.0)
			"swipe":
				(node as MeshInstance3D).material_override.set_shader_parameter("progress", t)
			"burst":
				var flash: MeshInstance3D = effect.flash
				flash.scale = Vector3.ONE * effect.size * (0.25 + 0.35 * t)
				_fade(flash, 1.0 - t * 2.5)
				var ring: MeshInstance3D = effect.ring
				ring.scale = Vector3.ONE * effect.size * (0.3 + 0.8 * t)
				_fade(ring, 1.0 - t * 1.4)
				for shard: Dictionary in effect.shards:
					shard.node.position = shard.direction * effect.size * 1.6 * t
					shard.node.rotation = Vector3(t * 6.0, t * 4.0, 0)
					_fade(shard.node, 1.0 - t)
			"puff":
				node.scale = Vector3.ONE * (0.2 + 0.5 * t)
				_fade(node, 0.5 * (1.0 - t))
			"cloud":
				node.scale = Vector3.ONE * effect.size * (0.4 + 1.2 * t)
				node.position = effect.origin + Vector3.UP * 0.6 * t
				_fade(node, 1.0 - t)
			"spike":
				node.scale = Vector3(1, minf(1.0, t * 4.0), 1) * effect.size
				_fade_all(node, 1.0 - maxf(0.0, t - 0.4) / 0.6)
			"claws":
				node.scale = Vector3(1, minf(1.0, 0.2 + t * 3.0), 1)
				_fade_all(node, 1.0 - maxf(0.0, t - 0.3) / 0.7)
			"star":
				node.scale = Vector3.ONE * effect.size * (0.4 + 1.2 * t)
				_fade_all(node, 1.0 - t)
			"fangs":
				var close := minf(1.0, t * 2.5)
				effect.upper.position.y = effect.gap * (1.0 - close)
				effect.lower.position.y = -effect.gap * (1.0 - close)
				_fade_all(node, 1.0 - maxf(0.0, t - 0.5) * 2.0)
			"fade":
				_fade_all(node, 1.0 - t)
			"drop":
				node.position = effect.origin + Vector3.UP * SKY_HEIGHT * (1.0 - t)
			"drift":
				var d := clampf(t, 0.0, 1.0)
				node.position = (effect.from as Vector3).lerp(effect.to, d)
				_fade(node, 0.0 if t < 0.0 else 1.0 - d)
		if effect.age >= effect.frames:
			node.queue_free()
			_effects.erase(effect)


# --- Melee ---------------------------------------------------------------------------

## A crescent swept across the target, rolled by `tilt` degrees.
func _swipe(centre: Vector3, size: float, colour: Color, tilt: float) -> void:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2.ONE * size
	var material := ShaderMaterial.new()
	material.shader = SWIPE_SHADER
	material.set_shader_parameter("tint", colour)
	quad.material_override = material
	add_child(quad)
	quad.position = centre
	_face_camera(quad, size * CAMERA_NUDGE)
	quad.rotate_object_local(Vector3.FORWARD, deg_to_rad(tilt))
	_effects.append({"node": quad, "age": 0, "frames": SWIPE_FRAMES, "kind": "swipe"})


## Three claw marks raked diagonally across the target.
func _slash(centre: Vector3, height: float, colour: Color) -> void:
	var root := _camera_root(centre, height * CAMERA_NUDGE)
	for i in 3:
		var mark := _mesh(BoxMesh.new(), Color.WHITE.lerp(colour, 0.3), 0.95)
		mark.scale = Vector3(0.06, height * 0.9, 0.03)
		mark.position = Vector3((i - 1) * height * 0.2, 0, 0)
		mark.rotation.z = deg_to_rad(35)
		root.add_child(mark)
	_effects.append({"node": root, "age": 0, "frames": STRIKE_FRAMES, "kind": "claws"})


## A shockwave ring facing the attacker, with rays bursting out like a comic-book impact.
func _punch(centre: Vector3, height: float, colour: Color) -> void:
	var root := _camera_root(centre, height * CAMERA_NUDGE)
	var ring := _mesh(_torus(0.8, 1.0), Color.WHITE.lerp(colour, 0.3), 0.9)
	ring.rotation_degrees.x = 90
	root.add_child(ring)
	for i in 8:
		var ray := _mesh(BoxMesh.new(), colour, 0.9)
		ray.scale = Vector3(0.08, 0.6, 0.02)
		var holder := Node3D.new()
		holder.rotation.z = TAU * i / 8
		holder.add_child(ray)
		ray.position = Vector3(0, 1.1, 0)
		root.add_child(holder)
	_effects.append({"node": root, "age": 0, "frames": STRIKE_FRAMES, "kind": "star", "size": height * 0.35})


## Upper and lower rows of fangs snapping shut on the target.
func _bite(centre: Vector3, height: float, colour: Color) -> void:
	var root := _camera_root(centre, height * CAMERA_NUDGE)
	var rows: Array[Node3D] = []
	for side in [1, -1]:
		var row := Node3D.new()
		for i in 4:
			var fang := _mesh(_cone(0.07 * height, 0.3 * height), Color.WHITE.lerp(colour, 0.2), 0.95)
			fang.position = Vector3((i - 1.5) * height * 0.14, side * height * 0.15, 0)
			fang.rotation.z = PI if side == 1 else 0.0
			row.add_child(fang)
		root.add_child(row)
		rows.append(row)
	_effects.append({"node": root, "age": 0, "frames": STRIKE_FRAMES, "kind": "fangs",
		"upper": rows[0], "lower": rows[1], "gap": height * 0.35})


## Speed lines streaming behind a charging attacker.
func _rush(attacker: FighterView, toward: Vector3, colour: Color) -> void:
	var root := _facing_root(attacker.position + Vector3.UP * attacker.height * 0.5, toward)
	for i in 6:
		var line := _mesh(BoxMesh.new(), Color.WHITE.lerp(colour, 0.5), 0.6)
		var angle := TAU * i / 6
		line.position = Vector3(cos(angle), sin(angle), 0) * attacker.height * 0.45 + Vector3(0, 0, attacker.height * 0.8)
		line.scale = Vector3(0.04, 0.04, attacker.height * 1.2)
		root.add_child(line)
	_effects.append({"node": root, "age": 0, "frames": STRIKE_FRAMES, "kind": "fade"})
	_dust(attacker.position, colour, attacker.height * 0.5)


func _dust(ground: Vector3, colour: Color, size: float) -> void:
	var ring := _mesh(_torus(0.7, 1.0), Color(0.85, 0.8, 0.7).lerp(colour, 0.25), 0.6)
	ring.position = ground + Vector3.UP * 0.05
	ring.scale = Vector3.ONE * size * 0.6
	add_child(ring)
	_effects.append({"node": ring, "age": 0, "frames": STRIKE_FRAMES, "kind": "grow", "base": ring.scale, "growth": 1.2})


# --- Projectiles ---------------------------------------------------------------------

func _new_projectile(projectile: Dictionary, move: BattleMove, target: Vector2) -> Dictionary:
	var style := style_of(move)
	var colour := TypeColors.of(move.type)
	var origin := Vector3(projectile.position.x, PROJECTILE_HEIGHT, projectile.position.y)
	var direction := Vector3(projectile.velocity.x, 0, projectile.velocity.y).normalized()
	var reach := maxf(1.0, (target - (projectile.position as Vector2)).length())
	var root := Node3D.new()
	add_child(root)
	var visual := {"source": projectile, "node": root, "style": style, "colour": colour, "origin": origin,
		"direction": direction, "reach": reach, "history": [], "parts": [], "power": move.power, "spawned": _frame}
	var size := clampf(0.8 + move.power / 120.0, 0.8, 1.8)
	var r := Rules.PROJECTILE_RADIUS
	match style:
		"orb":
			visual.parts = [_attach(root, _sphere(r * 0.7 * size), Color.WHITE.lerp(colour, 0.3), 1.0),
				_attach(root, _sphere(r * 1.5 * size), colour, 0.35)]
			visual.trail = _trail(root, r * size, colour, TRAIL_LENGTH)
		"bullet":
			var core := _attach(root, _sphere(r * 0.8), Color.WHITE.lerp(colour, 0.4), 1.0)
			core.scale = Vector3(1, 1, 2.2)
			visual.parts = [core]
			visual.trail = _trail(root, r * 0.7, colour, 4)
		"beam":
			var beam := _mesh(_cylinder(r * 0.3 * size), Color.WHITE.lerp(colour, 0.5), 0.9)
			var glow := _mesh(_cylinder(r * 0.9 * size), colour, 0.4)
			for part in [beam, glow]:
				part.top_level = true
				root.add_child(part)
			visual.parts = [beam, glow, _attach(root, _sphere(r * 1.1 * size), Color.WHITE.lerp(colour, 0.4), 0.8)]
		"bolt":
			var segments: Array = []
			for i in BOLT_SEGMENTS:
				var segment := _mesh(BoxMesh.new(), Color.WHITE.lerp(colour, 0.3), 1.0)
				segment.top_level = true
				root.add_child(segment)
				segments.append(segment)
			visual.parts = segments
		"stream", "erupt", "quake":
			visual.parts = [_attach(root, _sphere(r * 0.6), Color.WHITE.lerp(colour, 0.5), 0.8 if style == "stream" else 0.0)]
		"pulse", "sound":
			var rings: Array = []
			for i in (2 if style == "pulse" else 3):
				var ring := _mesh(_torus(0.75 if style == "pulse" else 0.88, 1.0), colour, 0.85 - 0.2 * i)
				ring.rotation_degrees.x = 90
				root.add_child(ring)
				rings.append(ring)
			if style == "pulse":
				rings.append(_attach(root, _sphere(r * 1.2), Color.WHITE.lerp(colour, 0.5), 0.6))
			visual.parts = rings
		"wind":
			var swirl := _mesh(_torus(0.7, 0.9), Color.WHITE.lerp(colour, 0.5), 0.7)
			root.add_child(swirl)
			var leaves: Array = [swirl]
			for i in 6:
				leaves.append(_attach(root, BoxMesh.new(), Color.WHITE.lerp(colour, 0.6), 0.95))
				leaves[-1].scale = Vector3(0.25, 0.05, 0.4)
			visual.parts = leaves
		"powder":
			var motes: Array = []
			for i in POWDER_MOTES:
				motes.append(_attach(root, _sphere(0.09 + 0.04 * (i % 3)), Color.WHITE.lerp(colour, 0.7), 0.85))
			visual.parts = motes
		"skyfall":
			var rock := _mesh(_sphere(r * 1.6 * size), Color.WHITE.lerp(colour, 0.6), 1.0)
			rock.top_level = true
			root.add_child(rock)
			var marker := _mesh(_torus(0.8, 1.0), colour, 0.6)
			marker.top_level = true
			root.add_child(marker)
			visual.parts = [rock, marker]
			visual.trail = _trail(rock, r * 1.2 * size, colour, TRAIL_LENGTH)
		"mind":
			var aura := _mesh(_sphere(1.0), colour, 0.5)
			aura.top_level = true
			root.add_child(aura)
			visual.parts = [aura]
		"explosion":
			_cloud(origin, colour, 2.5)
			visual.parts = [_attach(root, _sphere(r), colour, 0.0)]
	return visual


func _update_projectile(visual: Dictionary, position: Vector3) -> void:
	var root: Node3D = visual.node
	var style: String = visual.style
	var origin: Vector3 = visual.origin
	var direction: Vector3 = visual.direction
	var travelled := (position - origin).length()
	var progress := clampf(travelled / float(visual.reach), 0.0, 1.0)
	root.position = position
	if direction.length_squared() > 0.0:
		root.look_at(position + direction, Vector3.UP)
	visual.history.push_front(position)
	visual.history.resize(mini(visual.history.size(), TRAIL_LENGTH + 1))
	match style:
		"orb", "bullet":
			_update_trail(visual, visual.history)
		"beam":
			var middle := (origin + position) * 0.5
			for i in 2:
				var part: MeshInstance3D = visual.parts[i]
				part.global_position = middle
				if travelled > 0.01:
					part.look_at(position, Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT)
					part.rotate_object_local(Vector3.RIGHT, PI / 2)
				part.scale = Vector3(1, maxf(0.01, travelled), 1)
		"bolt":
			var count: int = visual.parts.size()
			var previous := origin
			var side := direction.cross(Vector3.UP).normalized()
			for i in count:
				var along := origin + (position - origin) * float(i + 1) / count
				# Jitter changes every other frame, from fixed sines, so renders match.
				var phase := floorf(_frame * 0.5) * 1.7 + i * 2.3
				var jitter := (side * sin(phase) + Vector3.UP * sin(phase * 1.3)) * 0.25
				var point := along + (jitter if i + 1 < count else Vector3.ZERO)
				var segment: MeshInstance3D = visual.parts[i]
				segment.global_position = (previous + point) * 0.5
				if previous.distance_to(point) > 0.001:
					segment.look_at(point, Vector3.UP)
				segment.scale = Vector3(0.06, 0.06, previous.distance_to(point))
				previous = point
		"stream":
			if (_frame - int(visual.spawned)) % EMIT_EVERY == 0:
				_cloud(position, visual.colour, 0.35 + 0.45 * progress)
		"erupt":
			if (_frame - int(visual.spawned)) % EMIT_EVERY == 0:
				_spike(Vector3(position.x, 0, position.z), visual.colour)
		"quake":
			if (_frame - int(visual.spawned)) % (EMIT_EVERY * 2) == 0:
				_dust(Vector3(position.x, 0, position.z), visual.colour, 1.2)
		"pulse", "sound":
			for i in visual.parts.size():
				var ring: MeshInstance3D = visual.parts[i]
				ring.position = Vector3(0, 0, i * 0.45)
				ring.scale = Vector3.ONE * (0.45 + 0.75 * progress) * (1.0 - 0.15 * i)
		"wind":
			var spin := _frame * 0.6
			visual.parts[0].rotation = Vector3(PI / 2 + 0.4 * sin(spin), 0, spin)
			visual.parts[0].scale = Vector3.ONE * 0.7
			for i in range(1, visual.parts.size()):
				var angle: float = spin + TAU * i / 6.0
				visual.parts[i].position = Vector3(cos(angle), sin(angle), 0) * 0.65
				visual.parts[i].rotation = Vector3(spin, angle, 0)
		"powder":
			for i in visual.parts.size():
				var a: float = i * 1.7 + _frame * 0.25
				visual.parts[i].position = Vector3(sin(a), cos(a * 1.3) * 0.6, sin(i * 3.1 + _frame * 0.15)) * 0.6
		"skyfall":
			var landing: Vector3 = origin + direction * float(visual.reach)
			landing.y = 0.0
			var rock: MeshInstance3D = visual.parts[0]
			rock.global_position = landing + Vector3.UP * (0.4 + SKY_HEIGHT * (1.0 - progress))
			var marker: MeshInstance3D = visual.parts[1]
			marker.global_position = landing + Vector3.UP * 0.05
			marker.global_rotation = Vector3.ZERO
			marker.scale = Vector3.ONE * (0.3 + 0.7 * progress)
			var falling: Array = []
			for i in TRAIL_LENGTH + 1:
				falling.append(rock.global_position + Vector3.UP * 0.35 * i)
			_update_trail(visual, falling)
		"mind":
			var landing: Vector3 = origin + direction * float(visual.reach)
			var aura: MeshInstance3D = visual.parts[0]
			aura.global_position = Vector3(landing.x, PROJECTILE_HEIGHT, landing.z)
			aura.scale = Vector3.ONE * (0.5 + 0.6 * progress)
			_fade_pulse(aura, (0.4 + 0.3 * sin(_frame * 0.8)) * progress)


## A finished projectile: beams and bolts fade where they are, the rest vanish.
func _end_projectile(visual: Dictionary) -> void:
	var node: Node3D = visual.node
	if visual.style in ["beam", "bolt"]:
		_effects.append({"node": node, "age": 0, "frames": FADE_FRAMES, "kind": "fade"})
	else:
		node.queue_free()


func _visual_for(projectile: Dictionary) -> Dictionary:
	for visual in _projectiles:
		if is_same(visual.source, projectile):
			return visual
	return {}


func _trail(parent: Node3D, radius: float, colour: Color, length: int) -> Array:
	var trail: Array = []
	for i in length:
		var ghost := _mesh(_sphere(radius * (1.0 - 0.12 * i)), colour, 0.5 * (1.0 - float(i) / length))
		ghost.top_level = true
		ghost.visible = false
		parent.add_child(ghost)
		trail.append(ghost)
	return trail


func _update_trail(visual: Dictionary, points: Array) -> void:
	var trail: Array = visual.get("trail", [])
	for i in trail.size():
		var ghost: MeshInstance3D = trail[i]
		ghost.visible = i + 1 < points.size()
		if ghost.visible:
			ghost.global_position = points[i + 1]


## A beam (or, with `zigzag`, a lightning bolt) from `from` to `to` that fades out.
func _line(from: Vector3, to: Vector3, colour: Color, zigzag: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	var length := from.distance_to(to)
	if length < 0.01:
		return
	if zigzag:
		var side := (to - from).cross(Vector3.UP).normalized()
		var previous := from
		for i in BOLT_SEGMENTS:
			var along := from.lerp(to, float(i + 1) / BOLT_SEGMENTS)
			var point := along + ((side * sin(i * 2.3) + Vector3.UP * sin(i * 3.1)) * 0.2 if i + 1 < BOLT_SEGMENTS else Vector3.ZERO)
			var segment := _attach(root, BoxMesh.new(), Color.WHITE.lerp(colour, 0.3), 1.0)
			segment.look_at_from_position((previous + point) * 0.5, point, Vector3.UP)
			segment.scale = Vector3(0.06, 0.06, previous.distance_to(point))
			previous = point
	else:
		for width in [0.3, 0.9]:
			var part := _attach(root, _cylinder(Rules.PROJECTILE_RADIUS * width), Color.WHITE.lerp(colour, 0.5 if width < 0.5 else 1.0), 0.9 if width < 0.5 else 0.4)
			part.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
			part.rotate_object_local(Vector3.RIGHT, PI / 2)
			part.scale = Vector3(1, length, 1)
	_effects.append({"node": root, "age": 0, "frames": FADE_FRAMES * 2, "kind": "fade"})


func _cloud(position: Vector3, colour: Color, size: float) -> void:
	var puff := _mesh(_sphere(1.0), Color.WHITE.lerp(colour, 0.85), 0.45)
	puff.position = position
	add_child(puff)
	_effects.append({"node": puff, "age": 0, "frames": STRIKE_FRAMES, "kind": "cloud", "size": size, "origin": position})


func _spike(ground: Vector3, colour: Color) -> void:
	var spike := _mesh(_cone(0.18, 1.0), Color.WHITE.lerp(colour, 0.2), 0.95)
	var holder := Node3D.new()
	holder.position = ground
	holder.add_child(spike)
	spike.position = Vector3.UP * 0.5
	add_child(holder)
	_effects.append({"node": holder, "age": 0, "frames": STRIKE_FRAMES, "kind": "spike", "size": 0.9})


# --- Helpers -------------------------------------------------------------------------

## A point in front of a fighter, at `height_share` of its height.
static func _front(view: FighterView, height_share: float) -> Vector3:
	var forward := -view.global_transform.basis.z if view.is_inside_tree() else Vector3.FORWARD
	return view.position + forward * view.height * 0.6 + Vector3.UP * view.height * height_share


## A node at `centre` whose -Z points back along `toward`.
func _facing_root(centre: Vector3, toward: Vector3) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.look_at_from_position(centre, centre + toward, Vector3.UP)
	return root


## A node at `centre` whose XY plane faces the camera.
func _camera_root(centre: Vector3, nudge: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = centre
	_face_camera(root, nudge)
	return root


## Turns a node so its XY plane faces the current camera, and moves it `nudge` metres
## toward the camera so the fighter it's drawn on doesn't hide it.
func _face_camera(node: Node3D, nudge := 0.0) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var eye := camera.global_position
	if eye.distance_to(node.global_position) > 0.01:
		node.global_position += (eye - node.global_position).normalized() * nudge
		node.look_at(node.global_position + (node.global_position - eye), Vector3.UP)


static func _attach(parent: Node3D, mesh: Mesh, colour: Color, alpha: float) -> MeshInstance3D:
	var instance := _mesh(mesh, colour, alpha)
	parent.add_child(instance)
	return instance


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


## Sets an alpha directly, ignoring the material's peak, for effects that pulse.
static func _fade_pulse(node: MeshInstance3D, alpha: float) -> void:
	(node.material_override as StandardMaterial3D).albedo_color.a = clampf(alpha, 0.0, 1.0)


static func _fade(node: MeshInstance3D, alpha: float) -> void:
	var material: StandardMaterial3D = node.material_override
	material.albedo_color.a = clampf(alpha, 0.0, 1.0) * float(material.get_meta("peak", 1.0))


## Fades a node and every mesh under it.
static func _fade_all(node: Node, alpha: float) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).material_override is StandardMaterial3D:
		_fade(node, alpha)
	for child in node.get_children():
		_fade_all(child, alpha)


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


## A unit-length cylinder along Y.
static func _cylinder(radius: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 12
	return cylinder


## A cone pointing up +Y, `length` tall.
static func _cone(radius: float, length: float) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = length
	cone.radial_segments = 8
	return cone
