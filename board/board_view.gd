extends Node3D

## A read-only 3D table; input and animation never decide a move's legality.

signal presentation_changed

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const CheckersMesh = preload("res://games/anti_checkers/board/checkers_mesh.gd")
const BOARD_Y := 0.18
const MOVE_SECONDS := 0.24
const HOME_ELEVATION := PI * 0.27
const MIN_ELEVATION := PI * 0.24
const MAX_ELEVATION := PI * 0.45
const MIN_ZOOM := 0.70
const MAX_ZOOM := 1.85
const MAX_PAN := 3.0
const BODY_COLORS: Array[Color] = [Color("b54453"), Color("f1dfbf")]

var camera: Camera3D
var top_down := false
var azimuth := 0.0
var elevation := HOME_ELEVATION
var zoom_factor := 1.0
var pan_offset := Vector2.ZERO
var _home_side := State.RED
var _viewport_size := Vector2(1280, 720)
var _flip_tween: Tween
var _flip_target := 0.0
var _reduced_motion := false
var _built := false
var _pieces: Array[Dictionary] = []
var _batches: Array[MultiMesh] = []
var _faces: Array[PackedVector3Array] = []
var _player_colors: Array[Color] = []
var _given: Array[int] = [0, 0]
var _move_clock := MOVE_SECONDS
var _material: StandardMaterial3D


func _ready() -> void:
	_build_world()


func _process(delta: float) -> void:
	if _move_clock >= MOVE_SECONDS:
		return
	_move_clock = minf(_move_clock + delta, MOVE_SECONDS)
	var progress := _move_clock / MOVE_SECONDS
	var eased := smoothstep(0.0, 1.0, progress)
	for piece in _pieces:
		var start: Vector3 = piece["from"]
		var target: Vector3 = piece["to"]
		piece["position"] = start.lerp(target, eased)
		if not start.is_equal_approx(target):
			piece["position"] += Vector3.UP * sin(progress * PI) * 0.25
		piece["scale"] = lerpf(piece["from_scale"], piece["to_scale"], eased)
	_upload_pieces()
	presentation_changed.emit()


## Replay clears every old checker, tray and animation while retaining the meshes.
func reset(state: State, player_colors: Array[Color]) -> void:
	if player_colors.size() != 2:
		push_error("Anti Checkers needs one identity colour per side.")
		return
	_build_world()
	_rebuild_meshes(player_colors)
	_pieces.clear()
	_given = [0, 0]
	_move_clock = MOVE_SECONDS
	reset_camera()
	for square in 64:
		var value := state.board[square]
		if value == State.EMPTY:
			continue
		var at := square_position(square)
		_pieces.append({
			"square": square, "kind": absi(value), "side": State.side_of(value),
			"position": at, "from": at, "to": at,
			"scale": 1.0, "from_scale": 1.0, "to_scale": 1.0,
		})
	_upload_pieces()
	presentation_changed.emit()


## Local humans share an overhead camera; solo faces the chosen human side.
func configure_camera(overhead: bool, home_side: int) -> void:
	_build_world()
	top_down = overhead
	_home_side = home_side
	reset_camera()


## A committed jump visibly gives the captured checker to its owner's tray.
func present_move(move: Dictionary, state: State) -> void:
	_settle_pieces()
	for piece in _pieces:
		piece["from"] = piece["position"]
		piece["from_scale"] = piece["scale"]
		if int(move["capture"]) >= 0 and int(piece["square"]) == int(move["capture"]):
			var side := int(piece["side"])
			piece["square"] = -1
			piece["to"] = _tray_position(side, _given[side])
			piece["to_scale"] = 0.58
			_given[side] += 1
		elif int(piece["square"]) == int(move["from"]):
			piece["square"] = int(move["to"])
			piece["kind"] = absi(state.board[int(move["to"])])
			piece["to"] = square_position(int(move["to"]))
	_move_clock = 0.0
	if _reduced_motion:
		_settle_pieces()
	_upload_pieces()
	presentation_changed.emit()


## Reduced motion settles decorative movement without disabling direct camera input.
func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	if value:
		_settle_pieces()
		if _built:
			_upload_pieces()
		if camera_is_moving():
			_cancel_flip()
			_set_azimuth(_flip_target)
	presentation_changed.emit()


## The viewport's actual dimensions drive both framing and picking.
func resize_view(dimensions: Vector2) -> void:
	_viewport_size = dimensions.max(Vector2.ONE)
	_update_camera()


## Restores a safe full-table view after any zoom, orbit or pan.
func reset_camera() -> void:
	_cancel_flip()
	azimuth = PI if _home_side == State.IVORY else 0.0
	elevation = PI * 0.5 if top_down else HOME_ELEVATION
	zoom_factor = 1.0
	pan_offset = Vector2.ZERO
	_update_camera()


## Reorientation never changes players, squares, turn or zoom.
func flip_board() -> void:
	_cancel_flip()
	_flip_target = azimuth + PI
	if _reduced_motion:
		_set_azimuth(_flip_target)
	else:
		_flip_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_flip_tween.tween_method(_set_azimuth, azimuth, _flip_target, 0.35)


## Screen-relative camera keys orbit in solo and pan without tilting in local play.
func move_camera(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		return
	_cancel_flip()
	var step := direction.limit_length() * clampf(delta, 0.0, 0.1)
	if top_down:
		_pan((camera.basis.x * step.x - camera.basis.y * step.y) * 5.0 / zoom_factor)
	else:
		azimuth = wrapf(azimuth + step.x * 1.5, 0.0, TAU)
		elevation = clampf(elevation - step.y, MIN_ELEVATION, MAX_ELEVATION)
	_update_camera()


## Right dragging grabs the view, in viewport pixels rather than window pixels.
func drag_camera(relative: Vector2) -> void:
	_cancel_flip()
	if top_down:
		_pan((-camera.basis.x * relative.x + camera.basis.y * relative.y)
			* camera.size / _viewport_size.y)
	else:
		azimuth = wrapf(azimuth - relative.x / _viewport_size.x * TAU, 0.0, TAU)
		elevation = clampf(elevation + relative.y / _viewport_size.y * PI * 0.7,
			MIN_ELEVATION, MAX_ELEVATION)
	_update_camera()


## Bounded multiplicative zoom is shared by the wheel and touch-friendly buttons.
func zoom_camera(steps: float) -> void:
	zoom_factor = clampf(
		zoom_factor * pow(1.13, clampf(steps, -8.0, 8.0)), MIN_ZOOM, MAX_ZOOM
	)
	_update_camera()


## Browsing follows the nearest visible board axes after an orbit or flip.
func square_direction(direction: Vector2i) -> Vector2i:
	var angle := roundi(azimuth / (PI * 0.5)) * PI * 0.5
	return Vector2i(
		roundi(cos(angle) * direction.x - sin(angle) * direction.y),
		roundi(sin(angle) * direction.x + cos(angle) * direction.y)
	)


## Prevents a click during a deliberate view flip from choosing a moving target.
func camera_is_moving() -> bool:
	return _flip_tween != null and _flip_tween.is_running()


## The controller can hold the ending just long enough to show the final jump.
func pieces_are_moving() -> bool:
	return _move_clock < MOVE_SECONDS


## A ray onto the board plane works in solo, overhead, flipped and resized views.
func square_at(point: Vector2) -> int:
	if camera == null:
		return -1
	var hit: Variant = Plane(Vector3.UP, BOARD_Y).intersects_ray(
		camera.project_ray_origin(point), camera.project_ray_normal(point)
	)
	if hit == null:
		return -1
	var at: Vector3 = hit
	var file := floori(at.x + 4.0)
	var rank := floori(4.0 - at.z)
	return file + rank * 8 if file >= 0 and file < 8 and rank >= 0 and rank < 8 else -1


## The top disc of a king selects that piece, not the square projected behind it.
func piece_at(point: Vector2) -> int:
	if camera == null:
		return -1
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var nearest := INF
	var square := -1
	for piece in _pieces:
		if int(piece["square"]) < 0:
			continue
		var at: Vector3 = piece["position"]
		var height := 0.53 if int(piece["kind"]) == State.KING else 0.26
		var bounds := AABB(at + Vector3(-0.38, 0, -0.38), Vector3(0.76, height, 0.76))
		if bounds.intersects_ray(origin, direction) == null:
			continue
		var faces := _faces[int(piece["side"]) * 2 + int(piece["kind"]) - 1]
		for index in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(
				origin - at, direction, faces[index], faces[index + 1], faces[index + 2]
			)
			if hit == null:
				continue
			var local_hit: Vector3 = hit
			var distance := (origin - at).distance_squared_to(local_hit)
			if distance < nearest:
				nearest = distance
				square = int(piece["square"])
	return square


## The overlay uses the same camera as the world, including mid-animation.
func project(point: Vector3) -> Vector2:
	return camera.unproject_position(point) if camera != null else Vector2.ZERO


## A1 is the dark square at Red's left; ranks increase toward Ivory.
static func square_position(square: int) -> Vector3:
	return Vector3(float(square % 8) - 3.5, BOARD_Y, 3.5 - float(square / 8))


## Letter badges follow the moving checker, not its already-committed destination.
func piece_position(square: int) -> Vector3:
	for piece in _pieces:
		if int(piece["square"]) == square:
			return piece["position"]
	return square_position(square)


func _settle_pieces() -> void:
	_move_clock = MOVE_SECONDS
	for piece in _pieces:
		piece["position"] = piece["to"]
		piece["from"] = piece["to"]
		piece["scale"] = piece["to_scale"]
		piece["from_scale"] = piece["to_scale"]


func _tray_position(side: int, index: int) -> Vector3:
	var z := 4.61 + float(index / 6) * 0.45
	return Vector3((float(index % 6) - 2.5) * 1.27, 0.145,
		z if side == State.RED else -z)


func _cancel_flip() -> void:
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null


func _set_azimuth(value: float) -> void:
	azimuth = wrapf(value, 0.0, TAU)
	_update_camera()


func _pan(offset: Vector3) -> void:
	pan_offset = (pan_offset + Vector2(offset.x, offset.z)).clamp(
		Vector2.ONE * -MAX_PAN, Vector2.ONE * MAX_PAN
	)


func _update_camera() -> void:
	if camera == null:
		return
	var target := Vector3(pan_offset.x, BOARD_Y, pan_offset.y)
	var offset := Vector3.UP * 24.0 if top_down else Vector3(
		sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)
	) * 24.0
	camera.position = target + offset
	var up := Vector3.FORWARD.rotated(Vector3.UP, azimuth) if top_down else Vector3.UP
	camera.basis = Basis.looking_at(-offset, up)
	var inverse := camera.basis.inverse()
	var half_size := Vector2.ZERO
	for x in [-4.8, 4.8]:
		for z in [-5.75, 5.75]:
			for y in [-0.52, 0.72]:
				var point := inverse * Vector3(x, y - BOARD_Y, z)
				half_size.x = maxf(half_size.x, absf(point.x))
				half_size.y = maxf(half_size.y, absf(point.y))
	var aspect := _viewport_size.x / _viewport_size.y
	camera.size = (maxf(half_size.y, half_size.x / aspect) * 2.0 + 0.45) / zoom_factor
	presentation_changed.emit()


func _build_world() -> void:
	if _built:
		return
	_built = true
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.50
	var table := MeshInstance3D.new()
	table.name = "InlaidTable"
	table.mesh = CheckersMesh.table()
	table.material_override = _material
	add_child(table)
	var squares := MultiMeshInstance3D.new()
	squares.name = "BoardSquares"
	var tile := BoxMesh.new()
	tile.size = Vector3(0.992, 0.06, 0.992)
	tile.material = _material
	var tiles := MultiMesh.new()
	tiles.transform_format = MultiMesh.TRANSFORM_3D
	tiles.use_colors = true
	tiles.mesh = tile
	tiles.instance_count = 64
	for square in 64:
		tiles.set_instance_transform(square,
			Transform3D(Basis.IDENTITY, square_position(square) - Vector3.UP * 0.03))
		tiles.set_instance_color(square,
			Color("4b3844") if State.is_playable(square) else Color("e3ceb0"))
	squares.multimesh = tiles
	add_child(squares)
	for index in 4:
		var instance := MultiMeshInstance3D.new()
		instance.name = "Checkers%d" % index
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.instance_count = State.INITIAL_PIECES
		batch.visible_instance_count = 0
		instance.multimesh = batch
		instance.material_override = _material
		_batches.append(batch)
		_faces.append(PackedVector3Array())
		add_child(instance)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(120, 120)
	var velvet := StandardMaterial3D.new()
	velvet.albedo_color = Color("191823")
	velvet.roughness = 1.0
	floor_mesh.material = velvet
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Velvet"
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.55
	add_child(floor_node)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17131f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7d6e6")
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.name = "WarmKey"
	key.rotation_degrees = Vector3(-56, -30, 0)
	key.light_color = Color("ffdfba")
	key.light_energy = 0.72
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 35.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFill"
	fill.rotation_degrees = Vector3(-36, 135, 0)
	fill.light_color = Color("bfc9ed")
	fill.light_energy = 0.18
	add_child(fill)
	camera = Camera3D.new()
	camera.name = "BoardCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 80.0
	add_child(camera)
	camera.current = true
	_update_camera()


func _rebuild_meshes(colors: Array[Color]) -> void:
	for side in 2:
		for kind in range(State.MAN, State.KING + 1):
			var index := side * 2 + kind - 1
			if _batches[index].mesh == null or _player_colors != colors:
				_batches[index].mesh = CheckersMesh.piece(
					kind == State.KING, BODY_COLORS[side], colors[side]
				)
				_faces[index] = _batches[index].mesh.get_faces()
	_player_colors = colors.duplicate()


func _upload_pieces() -> void:
	var counts: Array[int] = [0, 0, 0, 0]
	for piece in _pieces:
		var index := int(piece["side"]) * 2 + int(piece["kind"]) - 1
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * float(piece["scale"]))
		_batches[index].set_instance_transform(counts[index],
			Transform3D(basis, piece["position"]))
		counts[index] += 1
	for index in 4:
		_batches[index].visible_instance_count = counts[index]
