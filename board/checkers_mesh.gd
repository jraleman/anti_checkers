extends RefCounted

## Original turned checkers and inlaid table, batched into vertex-coloured meshes.

const SEGMENTS := 32
const PROFILE := [
	Vector2(0.0, 0.0), Vector2(0.31, 0.0), Vector2(0.37, 0.04),
	Vector2(0.37, 0.08), Vector2(0.34, 0.10), Vector2(0.36, 0.13),
	Vector2(0.36, 0.20), Vector2(0.32, 0.25), Vector2(0.27, 0.25),
	Vector2(0.26, 0.225), Vector2(0.21, 0.225), Vector2(0.20, 0.245),
	Vector2(0.0, 0.245),
]
const GOLD := Color("c89560")
var _surface := SurfaceTool.new()


## A king is physically two checkers plus a raised crown, not a colour change.
static func piece(king: bool, body: Color, player_ring: Color) -> ArrayMesh:
	var builder := new()
	builder._surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder._disc(0.0, body, player_ring)
	if king:
		builder._disc(0.23, body, GOLD)
		builder._box(Vector3(0.26, 0.025, 0.07), Vector3(0, 0.49, 0), GOLD)
		for x in [-0.10, 0.0, 0.10]:
			builder._box(Vector3(0.045, 0.025, 0.11),
				Vector3(x, 0.49, -0.06), GOLD)
	return builder._finish()


## Static rails, trays and brass trim share a single draw surface.
static func table() -> ArrayMesh:
	var builder := new()
	builder._surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder._box(Vector3(9.6, 0.50, 11.5), Vector3(0, -0.26, 0), Color("412c2b"))
	builder._box(Vector3(9.44, 0.08, 11.34), Vector3(0, 0.015, 0), Color("795043"))
	builder._box(Vector3(9.22, 0.06, 11.12), Vector3(0, 0.085, 0), Color("38272e"))
	for x in [-4.55, 4.55]:
		builder._box(Vector3(0.025, 0.015, 10.96), Vector3(x, 0.125, 0), GOLD)
	for z in [-5.46, 5.46]:
		builder._box(Vector3(9.10, 0.015, 0.025), Vector3(0, 0.125, z), GOLD)
	for x in [-4.05, 4.05]:
		builder._box(Vector3(0.045, 0.06, 8.14), Vector3(x, 0.145, 0), GOLD)
	for z in [-4.05, 4.05]:
		builder._box(Vector3(8.14, 0.06, 0.045), Vector3(0, 0.145, z), GOLD)
	for z in [-4.83, 4.83]:
		builder._box(Vector3(8.35, 0.02, 0.94), Vector3(0, 0.127, z), Color("181923"))
		for x in [-4.22, 4.22]:
			builder._box(Vector3(0.035, 0.02, 0.98), Vector3(x, 0.14, z), GOLD)
		for offset in [-0.49, 0.49]:
			builder._box(Vector3(8.47, 0.02, 0.025),
				Vector3(0, 0.14, z + offset), GOLD)
	for x in [-4.4, 4.4]:
		for z in [-5.32, 5.32]:
			builder._box(Vector3(0.08, 0.02, 0.08), Vector3(x, 0.14, z), GOLD)
	return builder._finish()


func _disc(height: float, body: Color, ring: Color) -> void:
	for band in range(PROFILE.size() - 1):
		var lower: Vector2 = PROFILE[band]
		var upper: Vector2 = PROFILE[band + 1]
		var slope := upper - lower
		var color := body
		if band == 2:
			color = ring
		elif band in [3, 8, 9]:
			color = body.darkened(0.28)
		elif band == 6:
			color = body.lightened(0.12)
		for segment in SEGMENTS:
			var first := TAU * float(segment) / SEGMENTS
			var next := TAU * float(segment + 1) / SEGMENTS
			var points: Array[Vector3] = [
				Vector3(cos(first) * lower.x, lower.y + height, sin(first) * lower.x),
				Vector3(cos(first) * upper.x, upper.y + height, sin(first) * upper.x),
				Vector3(cos(next) * upper.x, upper.y + height, sin(next) * upper.x),
				Vector3(cos(next) * lower.x, lower.y + height, sin(next) * lower.x),
			]
			var first_normal := Vector3(
				cos(first) * slope.y, -slope.x, sin(first) * slope.y
			).normalized()
			var next_normal := Vector3(
				cos(next) * slope.y, -slope.x, sin(next) * slope.y
			).normalized()
			for index in [0, 2, 1, 0, 3, 2]:
				_surface.set_color(color)
				_surface.set_normal(first_normal if index < 2 else next_normal)
				_surface.add_vertex(points[index])


func _box(dimensions: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		_surface.set_color(color)
		_surface.set_normal(normals[index])
		_surface.add_vertex(at + vertices[index])


func _finish() -> ArrayMesh:
	_surface.index()
	return _surface.commit()
