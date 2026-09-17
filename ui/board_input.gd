extends Control

## A focusable, native-resolution input and hint layer over the isolated 3D view.

signal square_pressed(square: int)
signal square_hovered(square: int)
signal camera_dragged(relative: Vector2)
signal camera_zoomed(steps: float)
signal key_input(event: InputEvent)

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const BoardView = preload("res://games/anti_checkers/board/board_view.gd")
const GOLD := Color("ffcf8c")
const CREAM := Color("fff0dc")

var _view: BoardView
var _state: State
var _selected := -1
var _cursor := 20
var _hovered := -1
var _keyboard_cursor := false
var _hints := true
var _piece_labels := true
var _moves: Array[Dictionary] = []
var _dragging := false
var _badge_styles: Array[StyleBoxFlat] = []
var _label_font_size := 16


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = "Checkers board"
	mouse_exited.connect(_clear_hover)
	focus_exited.connect(_stop_dragging)
	get_window().focus_exited.connect(_stop_dragging)
	resized.connect(queue_redraw)
	for color in [Color("692236"), Color("fff0dc")]:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(4)
		_badge_styles.append(style)


## Camera changes invalidate both hover feedback and the projected markings.
func bind_view(view: BoardView) -> void:
	_view = view
	_view.presentation_changed.connect(_clear_hover)


## Only canonical moves from the model are advertised as legal destinations.
func present(
	state: State, selected: int, cursor: int, moves: Array[Dictionary],
	hints: bool, piece_labels: bool, keyboard_cursor: bool
) -> void:
	_state = state
	_selected = selected
	_cursor = cursor
	_moves = moves
	_hints = hints
	_piece_labels = piece_labels
	_keyboard_cursor = keyboard_cursor
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _view == null:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		if _dragging and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			camera_dragged.emit(event.relative * _viewport_scale())
			accept_event()
			return
		_stop_dragging()
		var square := _pick_square(event.position)
		if square != _hovered:
			_hovered = square
			square_hovered.emit(square)
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			grab_focus()
			_dragging = event.pressed
			mouse_default_cursor_shape = (
				Control.CURSOR_DRAG if _dragging else Control.CURSOR_POINTING_HAND
			)
			_clear_hover()
			accept_event()
		elif event.pressed and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
		]:
			camera_zoomed.emit(event.factor * (
				1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0:
				_stop_dragging()
				grab_focus()
				square_pressed.emit(_pick_square(event.position))
			accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		grab_focus()
		square_pressed.emit(_pick_square(event.position))
		accept_event()
	elif event is InputEventKey:
		key_input.emit(event)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			_stop_dragging()


func _pick_square(point: Vector2) -> int:
	var view_point := point * _viewport_scale()
	var piece := _view.piece_at(view_point)
	return piece if piece >= 0 else _view.square_at(view_point)


func _viewport_scale() -> Vector2:
	return Vector2(_view.get_viewport().size) / size.max(Vector2.ONE)


func _project(point: Vector3) -> Vector2:
	return _view.project(point) / _viewport_scale()


func _draw() -> void:
	if _view == null or _state == null:
		return
	var tile := _project(BoardView.square_position(0)).distance_to(
		_project(BoardView.square_position(1))
	)
	var pixel_scale := maxf(
		float(get_window().size.x) / maxf(get_viewport_rect().size.x, 1.0), 0.01
	)
	var font_size := roundi(clampf(tile * 0.25, 11.0 / pixel_scale, 17.0 / pixel_scale))
	_label_font_size = font_size
	var width := maxf(1.6 / pixel_scale, tile * 0.035)
	if not _state.last_move.is_empty():
		for key in ["from", "to"]:
			_outline(int(_state.last_move[key]), Color(GOLD, 0.42), width)
	if _hints:
		var marked := {}
		for move in _moves:
			var source := int(move["from"])
			var target := int(move["to"])
			var capture := int(move["capture"]) >= 0
			if _selected < 0 and capture and not marked.has(source):
				marked[source] = true
				_outline(source, Color("ffc5ad"), width)
			elif source == _selected and not marked.has(target):
				marked[target] = true
				var at := _project(BoardView.square_position(target))
				if capture:
					_outline(target, Color("ffc5ad"), width * 1.5)
					_center_text("x", at, font_size + 3, CREAM)
				else:
					draw_circle(at, tile * 0.12, Color("281d2a"))
					draw_circle(at, tile * 0.075, CREAM)
	if _selected >= 0:
		_outline(_selected, GOLD, width * 1.6)
	if _state.forced_from >= 0:
		_outline(_state.forced_from, GOLD, width, 0.12)
	if _keyboard_cursor:
		_outline(_cursor, CREAM, width, 0.17)
	elif _hovered >= 0:
		_outline(_hovered, Color(CREAM, 0.7), width, 0.09)
	for file in 8:
		_center_text(String.chr(97 + file),
			_project(Vector3(float(file) - 3.5, BoardView.BOARD_Y, 4.23)),
			font_size, GOLD)
	for rank in 8:
		_center_text(str(rank + 1),
			_project(Vector3(-4.23, BoardView.BOARD_Y, 3.5 - float(rank))),
			font_size, GOLD)
	for side in 2:
		var z := 5.37 if side == State.RED else -5.37
		var text := "RED - GIVEN AWAY" if side == State.RED else "IVORY - GIVEN AWAY"
		var at := _project(Vector3(0, BoardView.BOARD_Y, z))
		var label_width := get_theme_default_font().get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x + 8.0 / pixel_scale
		var label_size := Vector2(label_width, font_size * 1.25)
		draw_rect(Rect2(at - label_size * 0.5, label_size), Color("38272e"))
		_center_text(text, at, font_size, GOLD)
	if not _piece_labels:
		return
	for square in 64:
		var piece := _state.board[square]
		if piece == State.EMPTY:
			continue
		var king := absi(piece) == State.KING
		var at := _project(_view.piece_position(square)
			+ Vector3.UP * (0.56 if king else 0.29))
		var text := "R" if piece > 0 else "I"
		if king:
			text += "K"
		var badge_width := float(font_size) * (1.55 if king else 1.05)
		draw_style_box(_badge_styles[State.side_of(piece)],
			Rect2(at - Vector2(badge_width, font_size) * 0.5,
				Vector2(badge_width, font_size)))
		_center_text(text, at, font_size - 2,
			CREAM if piece > 0 else Color("271f28"))


func _outline(square: int, color: Color, width: float, inset := 0.025) -> void:
	var center := BoardView.square_position(square)
	var radius := 0.5 - inset
	var points := PackedVector2Array()
	for offset in [
		Vector3(-radius, 0.012, -radius), Vector3(radius, 0.012, -radius),
		Vector3(radius, 0.012, radius), Vector3(-radius, 0.012, radius),
		Vector3(-radius, 0.012, -radius),
	]:
		points.append(_project(center + offset))
	draw_polyline(points, color, width, true)


func _center_text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at + Vector2(-width * 0.5, font_size * 0.34),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _clear_hover() -> void:
	_hovered = -1
	square_hovered.emit(-1)
	queue_redraw()


func _stop_dragging() -> void:
	_dragging = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
