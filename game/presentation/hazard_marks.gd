class_name HazardMarks
extends Node3D
## How entry hazards (concepts_brief.md §9.11) look on the field: low-poly pieces scattered around
## the start spot of the side they lie on, more for each layer. Pointed stones hover and turn
## (Stealth Rock), grey spikes and purple poison spikes stand in the ground, and a pale web lies
## flat. Pieces rise or sink in over a few frames as hazards are laid and cleared. Places come
## from the battle's seed, so every render matches.

const FADE_FRAMES := 10
## Pieces are scattered this far from the side's start spot, PIECES_PER_LAYER a layer.
const SCATTER := Vector2(1.2, 3.2)
const PIECES_PER_LAYER := 5
const ROCKS := 6
const ROCK_COLOUR := Color("8f7a5a")
const SPIKE_COLOUR := Color("8c8a86")
const TOXIC_COLOUR := Color("9b4fc4")
const WEB_COLOUR := Color(0.92, 0.92, 0.85, 0.85)
const ROCK_HEIGHT := 1.3

## Per side and hazard, the pieces shown ({"node", "layer"}) and how far in they are (0-1).
var _pieces := [{}, {}]
var _shown := [{}, {}]
var _seed := 0
var _frame := 0
var _material: StandardMaterial3D


## `seed` places the pieces.
func setup(seed: int) -> void:
	_seed = seed
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Shows the hazards up (`hazards`, ArenaConditions.hazards) on `battle`'s ground, one video
## frame on.
func sync(hazards: Array[Dictionary], battle: Battle) -> void:
	_frame += 1
	for side in 2:
		for name: String in ArenaConditions.HAZARDS:
			var layers := int(hazards[side].get(name, 0))
			var target := 1.0 if layers > 0 else 0.0
			var shown: float = move_toward(float(_shown[side].get(name, 0.0)), target, 1.0 / FADE_FRAMES)
			_shown[side][name] = shown
			if shown <= 0.0 and not _pieces[side].has(name):
				continue
			if not _pieces[side].has(name):
				_pieces[side][name] = _build(side, name, battle)
			var pieces: Array = _pieces[side][name]
			for piece: Dictionary in pieces:
				var node: Node3D = piece.node
				node.visible = shown > 0.0 and int(piece.layer) < maxi(layers, 1)
				node.scale = Vector3.ONE * maxf(shown, 0.01)
				if name == "stealthrock":
					var bob := sin((_frame + float(piece.phase)) * 0.05) * 0.12
					node.position.y = float(piece.ground) + ROCK_HEIGHT * shown + bob
					node.rotation.y = (_frame + float(piece.phase)) * 0.02


## The pieces of hazard `name` on `side`, for every layer it can stack to, hidden.
func _build(side: int, name: String, battle: Battle) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = hash("%d|%d|%s" % [_seed, side, name])
	var centre := Vector2(0, (-0.5 if side == 0 else 0.5) * Rules.START_DISTANCE)
	var pieces: Array = []
	var count := ROCKS if name == "stealthrock" else PIECES_PER_LAYER * int(ArenaConditions.HAZARDS[name])
	if name == "stickyweb":
		count = 1
	for i in count:
		var angle := random.randf() * TAU
		var at := centre + Vector2(cos(angle), sin(angle)) * random.randf_range(SCATTER.x, SCATTER.y)
		if name == "stickyweb":
			at = centre
		var ground := battle.terrain.height_at(at)
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		match name:
			"stealthrock":
				LowPoly.frustum(tool, ROCK_COLOUR, Vector3(0, -0.18, 0), 0.08, 0.2, 0.18, 5, angle, 0.25, random)
				LowPoly.frustum(tool, ROCK_COLOUR.lightened(0.15), Vector3.ZERO, 0.2, 0.0, 0.3, 5, angle, 0.25, random)
			"spikes", "toxicspikes":
				var colour := SPIKE_COLOUR if name == "spikes" else TOXIC_COLOUR
				LowPoly.frustum(tool, colour, Vector3.ZERO, 0.11, 0.0, 0.32, 4, angle)
				LowPoly.frustum(tool, colour.darkened(0.15), Vector3(0.13, 0, 0.05), 0.07, 0.0, 0.2, 4, angle + 0.6)
			"stickyweb":
				_web(tool)
		var node := MeshInstance3D.new()
		node.mesh = tool.commit()
		node.material_override = _material
		node.position = Vector3(at.x, ground, at.y)
		node.visible = false
		add_child(node)
		var layer := 0 if name in ["stealthrock", "stickyweb"] else i / PIECES_PER_LAYER
		pieces.append({"node": node, "layer": layer, "ground": ground, "phase": random.randf() * 100.0})
	return pieces


## A web lying flat on the ground: spokes and three rings of thin strips.
func _web(tool: SurfaceTool) -> void:
	var spokes := 8
	var radius := 2.4
	var lift := Vector3.UP * 0.03
	for s in spokes:
		var angle := TAU * s / spokes
		var out := Vector3(cos(angle), 0, sin(angle))
		_strip(tool, lift, lift + out * radius)
		for ring: float in [0.35, 0.65, 0.95]:
			var next := Vector3(cos(angle + TAU / spokes), 0, sin(angle + TAU / spokes))
			_strip(tool, lift + out * radius * ring, lift + next * radius * ring)


func _strip(tool: SurfaceTool, from: Vector3, to: Vector3) -> void:
	var across := (to - from).cross(Vector3.UP).normalized() * 0.025
	LowPoly.face(tool, WEB_COLOUR, [from - across, to - across, to + across, from + across],
		[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector3.UP)
