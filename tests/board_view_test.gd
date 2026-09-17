extends SceneTree

## Real Compatibility rendering, portrait/wide framing, picking and full match surfaces.

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const Options = preload("res://games/anti_checkers/anti_checkers_options.gd")
const GAME := "res://games/anti_checkers/gameplay.tscn"
const FIXTURE := "res://games/anti_checkers/tests/match_fixture.gd"
var _failures := PackedStringArray()
var _capture_dir := ""
var _game: Node
var _peak_draw_calls := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("board_view_test requires a graphics window, not --headless.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--anti-checkers-capture-dir="):
			_capture_dir = argument.trim_prefix("--anti-checkers-capture-dir=")
	if not _capture_dir.is_empty():
		if DirAccess.make_dir_recursive_absolute(_capture_dir) != OK:
			printerr("Could not create the requested Anti Checkers capture directory.")
			quit(1)
			return
	var settings := get_root().get_node("Settings")
	var session := get_root().get_node("GameSession")
	var original_values := (settings.get("_values") as Dictionary).duplicate(true)
	var original_session := {
		"game_mode": session.get("game_mode"),
		"player_two_controller": session.get("player_two_controller"),
		"cpu_difficulty": session.get("cpu_difficulty"),
	}
	var save_timer := settings.get("_save_timer") as Timer
	var timer_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	var original_game := GameCatalog.current_id()
	var original_size := get_root().size
	var original_theme := get_root().theme
	settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	settings.call("set_value", "ui/scale", 1.0)
	settings.call("set_value", Options.SHOW_HINTS_KEY, true)
	settings.call("set_value", Options.PIECE_LABELS_KEY, true)
	session.call("configure_multiplayer", 0)
	GameCatalog.select(Options.GAME_ID)
	_game = (load(GAME) as PackedScene).instantiate()
	_game.set_script(load(FIXTURE) as Script)
	get_root().add_child(_game)
	_game.set_process(false)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(1920, 800)]:
		(_game.get_node("%PauseButton") as Control).visible = dimensions.y > dimensions.x
		get_root().size = dimensions
		await _render_frames()
		_test_geometry()
		_test_panel_bounds()
		await _capture("local-%dx%d" % [dimensions.x, dimensions.y])
	var view: Node = _game.get("_view")
	_game.call("_flip_board")
	await _render_frames()
	_test_geometry()
	_game.call("_reset_camera")
	get_root().size = Vector2i(1280, 720)
	for side in [State.RED, State.IVORY]:
		settings.call("set_value", Options.PLAYER_SIDE_KEY, side)
		session.call("configure_single_player")
		_game.call("_on_play_again_pressed")
		await _render_frames()
		_test_geometry()
		_test_panel_bounds()
		await _capture("solo-red" if side == State.RED else "solo-ivory")
		view.call("drag_camera", Vector2(105, 18))
		await _render_frames()
		_test_geometry()
		await _capture("solo-orbit-red" if side == State.RED else "solo-orbit-ivory")
	session.call("configure_multiplayer", 0)
	_game.call("_on_play_again_pressed")
	_position({
		16: State.MAN, 18: State.MAN, 27: -State.MAN, 45: -State.MAN, 63: -State.MAN,
	})
	_game.call("_on_square_pressed", 18)
	_game.call("_on_square_pressed", 36)
	await _render_frames()
	await _capture("compulsory-continuation")
	_game.call("_on_square_pressed", 54)
	await _render_frames()
	var given: Array = view.get("_given")
	_expect(given == [0, 2], "Both jumped Ivory checkers must reach their visible giveaway tray.")
	_position({41: State.MAN, 50: -State.MAN, 52: -State.MAN, 63: -State.MAN})
	_game.call("_on_square_pressed", 41)
	_game.call("_on_square_pressed", 59)
	await _render_frames()
	await _capture("crowned-king")
	_game.call("_request_resignation")
	(_game.get_node("%PauseButton") as Control).visible = true
	get_root().size = Vector2i(390, 844)
	await _render_frames()
	_test_dialog_bounds()
	_test_panel_bounds()
	await _capture("resignation-portrait")
	settings.call("set_value", "ui/scale", 1.5)
	await _render_frames()
	_test_dialog_bounds()
	_test_panel_bounds()
	await _capture("resignation-large-ui")
	settings.call("set_value", "ui/scale", 1.0)
	_game.call("_cancel_selection")
	get_root().size = Vector2i(1280, 720)
	_position({18: State.MAN, 27: -State.MAN})
	_game.call("_on_square_pressed", 18)
	_game.call("_on_square_pressed", 36)
	_game.call("_complete_match")
	await _render_frames()
	await _capture("results")
	_game.call("_on_see_score_pressed")
	for frame in 20:
		await process_frame
	_expect((_game.get_node("%ShareCardPreview") as TextureRect).texture != null,
		"The shared stats screen must render Anti Checkers' two-sided scorecard.")
	await _capture("scorecard")
	_expect(_peak_draw_calls > 0 and _peak_draw_calls <= 40,
		"The batched world must render in 1-40 draw calls including shadows; got %d."
		% _peak_draw_calls)
	print("Anti Checkers peak 3D draw calls including shadows: %d." % _peak_draw_calls)
	_game.queue_free()
	await process_frame
	GameCatalog.restrict_to(Options.GAME_ID)
	get_root().theme = GameCatalog.theme().restyle(ThemeDB.get_project_theme())
	var menu := (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	await _render_frames()
	_expect((menu.get_node("%Title") as Label).text == "Anti Checkers",
		"The standalone title screen must carry this game's identity.")
	await _capture("standalone-title")
	menu.queue_free()
	await process_frame
	var setup := (load("res://scenes/menus/mode_select.tscn") as PackedScene).instantiate()
	get_root().add_child(setup)
	setup.call("_on_single_player_pressed")
	get_root().size = Vector2i(390, 844)
	await _render_frames()
	var choices := setup.get_node("%SoloSetupChoices") as Control
	_expect(choices.is_visible_in_tree()
		and get_root().get_visible_rect().encloses(choices.get_global_rect()),
		"Red/Ivory solo choices must fit the portrait setup screen.")
	await _capture("solo-setup-portrait")
	setup.queue_free()
	await process_frame
	get_root().theme = original_theme
	get_root().size = original_size
	var values := settings.get("_values") as Dictionary
	values.clear()
	values.merge(original_values, true)
	for key: String in original_session:
		session.set(key, original_session[key])
	save_timer.stop()
	save_timer.process_mode = timer_mode
	GameCatalog.clear_restriction()
	GameCatalog.select(original_game)
	await create_timer(0.7).timeout
	if _failures.is_empty():
		print("Anti Checkers rendered view tests passed.")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _render_frames() -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw


func _test_geometry() -> void:
	var view: Node = _game.get("_view")
	var input := _game.get("_board_input") as Control
	var frame := Rect2(Vector2.ZERO, input.size)
	var state: State = _game.get("_state")
	var pixel_scale := float(get_root().size.x) / get_root().get_visible_rect().size.x
	_expect(int(input.get("_label_font_size")) * pixel_scale >= 10.5,
		"Board coordinates and side badges must remain readable in physical pixels.")
	for square in 64:
		var point: Vector3 = view.call("square_position", square)
		var projected: Vector2 = input.call("_project", point)
		_expect(frame.has_point(projected),
			"Square %s must fit the board at %s." % [State.square_name(square), input.size])
		var in_view: Vector2 = view.call("project", point)
		_expect(int(view.call("square_at", in_view)) == square,
			"Every square must pick itself after resizing, orbiting or flipping.")
		if state.board[square] != State.EMPTY:
			var top: Vector2 = view.call("project", point + Vector3.UP * 0.24)
			_expect(int(view.call("piece_at", top)) == square,
				"The actual checker top must select its owner, not a square behind it.")
	var count := 0
	for batch: MultiMesh in view.get("_batches"):
		count += batch.visible_instance_count
	_expect(count == 24, "The opening must render all twenty-four original 3D checkers.")
	var viewport := _game.get("_board_viewport") as SubViewport
	var calls := viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
	) + viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
	)
	_peak_draw_calls = maxi(_peak_draw_calls, calls)
	var image := viewport.get_texture().get_image()
	_expect(not image.is_empty(), "A real rendered 3D viewport must produce an image.")
	var colors := {}
	for x in range(0, image.get_width(), maxi(image.get_width() / 20, 1)):
		for y in range(0, image.get_height(), maxi(image.get_height() / 20, 1)):
			colors[image.get_pixel(x, y).to_html()] = true
	_expect(colors.size() > 20, "The rendered board must contain geometry, not a blank texture.")


func _test_panel_bounds() -> void:
	var panel := _game.get("_match_panel") as Control
	var input := _game.get("_board_input") as Control
	var screen := get_root().get_visible_rect()
	var bounds: Rect2 = _game.call("_playfield_bounds")
	var top_bar := (_game.get_node("%PlayerOneCard") as Control).get_parent() as Control
	_expect(screen.grow(1.0).encloses(top_bar.get_global_rect()),
		"The turn header and both player cards must fit at %s (canvas %s)."
		% [get_root().size, screen.size])
	_expect((_game.get_node("%ModeTitle") as Label).get_line_count() <= 2,
		"The game title must fit without breaking Checkers across multiple lines.")
	_expect(bounds.grow(1.0).encloses(input.get_rect())
		and bounds.grow(1.0).encloses(panel.get_rect()),
		"Board and scrollable briefing must stay between the HUD and footer.")
	_expect(not panel.get_rect().intersects(input.get_rect()),
		"The briefing must not cover playable squares.")
	var pixel_scale := float(get_root().size.x) / screen.size.x
	_expect(input.size.y * pixel_scale >= 180.0,
		"The board must retain useful physical height in portrait.")
	if get_root().size.y > get_root().size.x:
		_expect(panel.position.y >= input.get_rect().end.y,
			"Portrait keeps the board above, not behind, the ledger.")
	for button: Button in panel.get("_buttons"):
		_expect(panel.get_global_rect().grow(1.0).encloses(button.get_global_rect()),
			"Flip, reset, zoom and resignation must remain reachable.")
		_expect(button.size.y * pixel_scale >= 31.0,
			"Board actions must remain physically usable rather than merely in bounds.")


func _test_dialog_bounds() -> void:
	var dialog := _game.get("_dialog") as Control
	var panel := dialog.get("_panel") as Control
	_expect(dialog.visible and Rect2(Vector2.ZERO, dialog.size).encloses(panel.get_rect()),
		"Resignation confirmation must remain entirely on-screen.")


func _position(pieces: Dictionary) -> void:
	_game.call("_on_play_again_pressed")
	var board := PackedInt32Array()
	board.resize(64)
	for square: int in pieces:
		board[square] = pieces[square]
	var state: State = _game.get("_state")
	_expect(state.set_position(board, State.RED), "The visual teaching position must be valid.")
	_game.set("_legal", state.legal_moves())
	_game.set("_selected", -1)
	var colors: Array[Color] = _game.call("_side_colors")
	(_game.get("_view") as Node).call("reset", state, colors)
	_game.call("_sync_match_scores")
	_game.call("_update_scores")
	_game.call("_present_position")


func _capture(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	_expect(image.save_png(_capture_dir.path_join(name + ".png")) == OK,
		"Could not save the requested capture: " + name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
