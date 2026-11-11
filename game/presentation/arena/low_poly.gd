class_name LowPoly
extends RefCounted
## Faceted shapes for the arena (concepts_brief.md §12.7): flat-shaded faces with UVs in
## metres, so the arena surface shader's pixel grid lies on each face, added to a SurfaceTool.
## The ground mesh and the features (rocks, columns, spikes, trees) are built from these, for
## a low-poly look with the same pixel textures as Cobblemon's models.

## A polygon fanned from its first corner, each triangle flat-shaded and wound to face
## `facing` (the side it's seen from). `uvs` are the corners' metres on the face.
static func face(tool: SurfaceTool, colour: Color, corners: Array, uvs: Array, facing: Vector3) -> void:
	for i in range(1, corners.size() - 1):
		_triangle(tool, colour, [corners[0], corners[i], corners[i + 1]], [uvs[0], uvs[i], uvs[i + 1]], facing)


static func _triangle(tool: SurfaceTool, colour: Color, corners: Array, uvs: Array, facing: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	var order := [0, 1, 2]
	# Godot's front faces wind clockwise as seen from the front: the cross product of the
	# corners as given points away from the viewer, so flip it toward `facing` and swap.
	if normal.dot(facing) > 0.0:
		order = [0, 2, 1]
	else:
		normal = -normal
	for i: int in order:
		tool.set_color(colour)
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(corners[i])


## A faceted frustum standing on `base` (x, height, z): `sides` sides, from `bottom_radius` to
## `top_radius` (0 for a point) over `height`, turned by `turn` radians. `wobble` scales each
## corner's radius by up to that share, from `random`, so rocks come out irregular. A flat cap
## closes the top unless it comes to a point; the underside is never seen and is left out.
static func frustum(tool: SurfaceTool, colour: Color, base: Vector3, bottom_radius: float, top_radius: float,
		height: float, sides: int, turn: float, wobble := 0.0, random: RandomNumberGenerator = null) -> void:
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for s in sides:
		var angle := turn + TAU * s / sides
		var direction := Vector3(cos(angle), 0, sin(angle))
		var shake := 1.0 + (random.randf_range(-wobble, wobble) if random != null and wobble > 0.0 else 0.0)
		bottom.append(base + direction * bottom_radius * shake)
		top.append(base + Vector3.UP * height + direction * top_radius * shake)
	var middle := base + Vector3.UP * height * 0.5
	for s in sides:
		var n := (s + 1) % sides
		var width := bottom[s].distance_to(bottom[n])
		var slant := bottom[s].distance_to(top[s])
		var outward := ((bottom[s] + bottom[n] + top[s] + top[n]) * 0.25 - middle) * Vector3(1, 0, 1)
		if top_radius <= 1e-4:
			face(tool, colour, [bottom[s], bottom[n], top[s]], [Vector2(0, 0), Vector2(width, 0), Vector2(width * 0.5, slant)], outward)
		else:
			face(tool, colour, [bottom[s], bottom[n], top[n], top[s]],
				[Vector2(0, 0), Vector2(width, 0), Vector2(width, slant), Vector2(0, slant)], outward)
	if top_radius > 1e-4:
		var uvs: Array = top.map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z))
		face(tool, colour, top, uvs, Vector3.UP)


## A faceted ball (a canopy, a boulder): a short widening frustum, a band, and a cap closing in.
static func ball(tool: SurfaceTool, colour: Color, centre: Vector3, radius: float, height: float, sides: int,
		turn: float, random: RandomNumberGenerator) -> void:
	var low := centre - Vector3.UP * height * 0.5
	frustum(tool, colour, low, radius * 0.55, radius, height * 0.3, sides, turn, 0.12, random)
	frustum(tool, colour, low + Vector3.UP * height * 0.3, radius, radius * 0.9, height * 0.35, sides, turn, 0.08, random)
	frustum(tool, colour.lightened(0.06), low + Vector3.UP * height * 0.65, radius * 0.9, radius * 0.35, height * 0.35, sides, turn, 0.1, random)


## A log lying along `along` (a unit vector on the floor): a faceted prism of `radius`.
static func log_(tool: SurfaceTool, colour: Color, centre: Vector3, along: Vector3, length: float, radius: float, sides: int) -> void:
	var up := Vector3.UP
	var across := along.cross(up).normalized()
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for s in sides:
		var angle := TAU * s / sides
		var offset := (up * sin(angle) + across * cos(angle)) * radius
		ring_a.append(centre - along * length * 0.5 + offset)
		ring_b.append(centre + along * length * 0.5 + offset)
	for s in sides:
		var n := (s + 1) % sides
		var outward := (ring_a[s] + ring_a[n]) * 0.5 - (centre - along * length * 0.5)
		var width := ring_a[s].distance_to(ring_a[n])
		face(tool, colour, [ring_a[s], ring_a[n], ring_b[n], ring_b[s]],
			[Vector2(0, 0), Vector2(width, 0), Vector2(width, length), Vector2(0, length)], outward)
	var end_uvs: Array = []
	for s in sides:
		end_uvs.append(Vector2(cos(TAU * s / sides), sin(TAU * s / sides)) * radius)
	face(tool, colour.lightened(0.25), ring_a, end_uvs, -along)
	face(tool, colour.lightened(0.25), ring_b, end_uvs, along)
