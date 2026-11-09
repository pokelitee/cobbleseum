class_name BedrockGeometry
extends RefCounted
## Converts Bedrock geometry (.geo.json, format 1.12.0) into a Godot scene:
## a root Node3D holding a Skeleton3D with one rigidly skinned mesh (concepts_brief.md §7.2).
##
## Coordinates: 16 model pixels = 1 metre. Bedrock files store X mirrored relative to Godot,
## so positions and pivots negate X, rotations negate their X and Y angles, and a rotation
## is applied Z, then Y, then X about its pivot. Godot's -Z is the model's front (north).

const PIXEL := 1.0 / 16.0
const FACES: Array[String] = ["north", "east", "south", "west", "up", "down"]


## Builds the model. Returns {"scene": Node3D} or {"error": String}.
## `texture` may be null (tests); `name` becomes the root node's name.
static func build(geo_json: Dictionary, texture: Texture2D, name: String) -> Dictionary:
	var geometries: Variant = geo_json.get("minecraft:geometry")
	if not geometries is Array or geometries.is_empty():
		return {"error": "no minecraft:geometry entry"}
	var geometry: Dictionary = geometries[0]
	var description: Dictionary = geometry.get("description", {})
	var texture_size := Vector2(description.get("texture_width", 64), description.get("texture_height", 64))
	var bones := _ordered_bones(geometry.get("bones", []))
	if bones.has("error"):
		return bones

	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	var global_rest := {}
	var rest_rotations := {}
	var locators := {}
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_count := 0
	for bone: Dictionary in bones.list:
		var bone_name: String = bone.name
		var index := skeleton.add_bone(bone_name)
		var pivot := to_godot(bone.get("pivot", [0, 0, 0]))
		var parent_pivot := Vector3.ZERO
		if bone.has("parent"):
			var parent_index := skeleton.find_bone(bone.parent)
			skeleton.set_bone_parent(index, parent_index)
			parent_pivot = to_godot(bones.by_name[bone.parent].get("pivot", [0, 0, 0]))
		rest_rotations[bone_name] = bone.get("rotation", [0, 0, 0])
		var rest := Transform3D(rotation_basis(rest_rotations[bone_name]), pivot - parent_pivot)
		skeleton.set_bone_rest(index, rest)
		skeleton.set_bone_pose(index, rest)
		global_rest[bone_name] = (global_rest[bone.parent] * rest) if bone.has("parent") else rest
		for locator: String in bone.get("locators", {}):
			locators[locator] = {"bone": bone_name, "position": _locator_position(bone.locators[locator]) - pivot}
		for cube: Dictionary in bone.get("cubes", []):
			vertex_count += _add_cube(surface, cube, bone, index, pivot, global_rest[bone_name], texture_size)

	var root := Node3D.new()
	root.name = name
	root.add_child(skeleton)
	skeleton.owner = root
	root.set_meta("locators", locators)
	# Bedrock animations add their angles to these before building a bone's basis.
	root.set_meta("rest_rotations", rest_rotations)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	if vertex_count > 0:
		var mesh := surface.commit()
		mesh.surface_set_material(0, material(texture))
		mesh_instance.mesh = mesh
	var skin := Skin.new()
	for bone_name: String in global_rest:
		skin.add_named_bind(bone_name, (global_rest[bone_name] as Transform3D).affine_inverse())
	mesh_instance.skin = skin
	skeleton.add_child(mesh_instance)
	mesh_instance.owner = root
	mesh_instance.skeleton = NodePath("..")
	return {"scene": root}


## Pixel-art material: nearest filtering, no mipmaps, alpha-tested cut-outs. Both sides render
## because many models use zero-thickness planes for eyes, fins and wings.
static func material(texture: Texture2D) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_texture = texture
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	result.alpha_scissor_threshold = 0.5
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.roughness = 1.0
	return result


## Bedrock position (pixels, X mirrored) to Godot position (metres).
static func to_godot(position: Array) -> Vector3:
	return Vector3(-float(position[0]), float(position[1]), float(position[2])) * PIXEL


## Bedrock Euler angles in degrees to a Godot basis: X and Y negated, applied Z·Y·X.
static func rotation_basis(degrees: Array) -> Basis:
	var x := deg_to_rad(-float(degrees[0]))
	var y := deg_to_rad(-float(degrees[1]))
	var z := deg_to_rad(float(degrees[2]))
	return Basis(Vector3(0, 0, 1), z) * Basis(Vector3(0, 1, 0), y) * Basis(Vector3(1, 0, 0), x)


## Box-UV rectangles in texture pixels for each face, as [from, size]; a negative size flips.
## Rows: the top strip holds up and down; the strip below holds east, north, west and south.
static func box_uv(uv: Vector2, size: Vector3, mirror: bool) -> Dictionary:
	var faces := {
		"east": [Vector2(0, size.z), Vector2(size.z, size.y)],
		"north": [Vector2(size.z, size.z), Vector2(size.x, size.y)],
		"west": [Vector2(size.z + size.x, size.z), Vector2(size.z, size.y)],
		"south": [Vector2(2 * size.z + size.x, size.z), Vector2(size.x, size.y)],
		"up": [Vector2(size.z + size.x, size.z), Vector2(-size.x, -size.z)],
		"down": [Vector2(size.z + 2 * size.x, 0), Vector2(-size.x, size.z)],
	}
	if mirror:
		var east: Vector2 = faces.east[0]
		faces.east[0] = faces.west[0]
		faces.west[0] = east
		for face: String in faces:
			faces[face] = [faces[face][0] + Vector2(faces[face][1].x, 0), Vector2(-faces[face][1].x, faces[face][1].y)]
	for face: String in faces:
		faces[face][0] += uv
	return faces


## Corners of each face as seen from outside: top-left, top-right, bottom-right, bottom-left.
static func face_corners(low: Vector3, high: Vector3) -> Dictionary:
	var a := low
	var b := high
	return {
		"north": [Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z)],
		"south": [Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)],
		"east": [Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z)],
		"west": [Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z)],
		"up": [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)],
		"down": [Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z)],
	}


static func _add_cube(surface: SurfaceTool, cube: Dictionary, bone: Dictionary, bone_index: int,
		bone_pivot: Vector3, bone_global: Transform3D, texture_size: Vector2) -> int:
	var origin: Array = cube.get("origin", [0, 0, 0])
	var size := Vector3(absf(cube.get("size", [0, 0, 0])[0]), absf(cube.size[1]), absf(cube.size[2]))
	var inflate := float(cube.get("inflate", bone.get("inflate", 0.0)))
	# In Godot space the cube spans x from -(origin.x + size.x) to -origin.x.
	var low := Vector3(-(float(origin[0]) + size.x) - inflate, float(origin[1]) - inflate, float(origin[2]) - inflate) * PIXEL
	var high := Vector3(-float(origin[0]) + inflate, float(origin[1]) + size.y + inflate, float(origin[2]) + size.z + inflate) * PIXEL
	var cube_transform := Transform3D.IDENTITY
	if cube.has("rotation"):
		var pivot := to_godot(cube.get("pivot", [float(origin[0]) + size.x / 2, float(origin[1]) + size.y / 2, float(origin[2]) + size.z / 2]))
		cube_transform = Transform3D(Basis.IDENTITY, pivot) * Transform3D(rotation_basis(cube.rotation), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	# Vertices go into the bone's frame (relative to its pivot), then into rest-pose model space.
	var to_model := bone_global * Transform3D(Basis.IDENTITY, -bone_pivot) * cube_transform
	var uv_offset: Array = cube.get("uv", [0, 0])
	var uvs := box_uv(Vector2(uv_offset[0], uv_offset[1]), size, bool(cube.get("mirror", bone.get("mirror", false))))
	var corners := face_corners(low, high)
	var added := 0
	for face in FACES:
		var quad: Array = corners[face]
		var model: Array[Vector3] = []
		for corner: Vector3 in quad:
			model.append(to_model * corner)
		var normal := (model[1] - model[0]).cross(model[3] - model[0])
		if normal.length_squared() < 1e-12:
			continue  # zero-thickness cubes only keep their two large faces
		normal = normal.normalized()
		var from: Vector2 = uvs[face][0]
		var span: Vector2 = uvs[face][1]
		var quad_uv: Array[Vector2] = [from, from + Vector2(span.x, 0), from + span, from + Vector2(0, span.y)]
		for i in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(-normal)
			surface.set_uv(quad_uv[i] / texture_size)
			surface.set_bones(PackedInt32Array([bone_index, 0, 0, 0]))
			surface.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
			surface.add_vertex(model[i])
			added += 1
	return added


static func _locator_position(value: Variant) -> Vector3:
	var offset: Variant = value.get("offset", [0, 0, 0]) if value is Dictionary else value
	return to_godot(offset)


## Orders bones so every parent precedes its children.
static func _ordered_bones(raw: Array) -> Dictionary:
	var by_name := {}
	for bone: Dictionary in raw:
		if not bone.get("name") is String:
			return {"error": "bone without a name"}
		if by_name.has(bone.name):
			return {"error": "duplicate bone '%s'" % bone.name}
		by_name[bone.name] = bone
	var ordered: Array = []
	var placed := {}
	while ordered.size() < raw.size():
		var progressed := false
		for bone: Dictionary in raw:
			if placed.has(bone.name):
				continue
			if bone.has("parent") and not by_name.has(bone.parent):
				return {"error": "bone '%s' has unknown parent '%s'" % [bone.name, bone.parent]}
			if not bone.has("parent") or placed.has(bone.parent):
				ordered.append(bone)
				placed[bone.name] = true
				progressed = true
		if not progressed:
			return {"error": "bone hierarchy has a cycle"}
	return {"list": ordered, "by_name": by_name}
