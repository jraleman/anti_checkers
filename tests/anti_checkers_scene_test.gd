extends SceneTree

## Game-specific integration: input, chained turns, CPU seats, lifecycle and setup.

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const Options = preload("res://games/anti_checkers/anti_checkers_options.gd")
const GAME := "res://games/anti_checkers/gameplay.tscn"
const FIXTURE := "res://games/anti_checkers/tests/match_fixture.gd"

var _failures := PackedStringArray()
var _checks := 0
var _settings: Node
var _session: Node
var _saved_values: Dictionary
var _saved_session: Dictionary
var _saved_game := ""
var _save_mode := Node.PROCESS_MODE_INHERIT


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = get_root().get_node("Settings")
	_session = get_root().get_node("GameSession")
	_saved_values = (_settings.get("_values") as Dictionary).duplicate(true)
	_saved_game = GameCatalog.current_id()
	for key in ["game_mode", "player_two_controller", "cpu_difficulty"]:
		_saved_session[key] = _session.get(key)
	var save_timer := _settings.get("_save_timer") as Timer
	_save_mode = save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	GameCatalog.select(Options.GAME_ID)
	for binding in Options.CONTROL_BINDINGS:
		_settings.call("set_value", binding["key"], binding["default"])
	_settings.call("set_value", Settings.ROUND_MODE_KEY, Settings.RoundMode.LIVES)
	_settings.call("set_value", Settings.REDUCED_MOTION_KEY, false)
	_settings.call("set_value", Options.CPU_DIFFICULTY_KEY, Options.CPU_CASUAL)
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.RED)
	_settings.call("set_value", Options.SHOW_HINTS_KEY, true)
	_settings.call("set_value", Options.PIECE_LABELS_KEY, true)
	_test_manifest()
	await _test_generated_setup()
	await _test_board_input()
	await _test_jump_chain()
	await _test_crowning()
	await _test_cpu_pause_and_replay()
	await _test_endings_and_seats()
	await _test_resignation_and_abandon()
	await _test_camera_and_live_options()
	for key: String in _saved_values:
		if (_settings.get("_values") as Dictionary).get(key) != _saved_values[key]:
			_settings.call("set_value", key, _saved_values[key])
	var values := _settings.get("_values") as Dictionary
	values.clear()
	values.merge(_saved_values, true)
	_settings.call("apply_controls")
	save_timer.stop()
	save_timer.process_mode = _save_mode
	for key: String in _saved_session:
		_session.set(key, _saved_session[key])
	GameCatalog.select(_saved_game)
	await create_timer(0.35).timeout
	if _failures.is_empty():
		print("Anti Checkers scene tests passed (%d checks)." % _checks)
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _test_manifest() -> void:
	var manifest := GameCatalog.get_manifest(Options.GAME_ID)
	_expect(manifest != null and manifest.title == "Anti Checkers",
		"The catalog must discover Anti Checkers without a host registration branch.")
	_expect(not manifest.uses_shell_round_rules and not manifest.default_lives_mode,
		"English giveaway rules, not the shared arcade limit, must end this match.")
	_expect(manifest.supports_single_player and manifest.supports_multiplayer
		and not manifest.supports_cpu_opponent,
		"Solo uses its own CPU; local play must be two humans.")
	_expect(manifest.control_style == GameManifest.CONTROL_STYLE_CUSTOM_KEYS
		and manifest.solo_setup_choices == [Options.PLAYER_SIDE_KEY],
		"Shared setup must discover the side choice and custom board controls from data.")
	_expect(manifest.gameplay_scene_exists() and ResourceLoader.exists(manifest.intro_scene_path)
		and ResourceLoader.exists(manifest.share_art_scene_path)
		and ResourceLoader.exists(manifest.tutorial_poster_path),
		"Every declared game-owned scene and piece of media must exist.")
	_expect(manifest.resolved_stats_url().to_utf8_buffer().size() <= 42,
		"The scorecard QR must stay within its scan-safe URL budget.")
	var rules := manifest.text("instructions_rules")
	_expect(rules.contains("same piece") and rules.contains("ENDS")
		and rules.contains("longest") and rules.contains("THEM"),
		"The instructions must explain jump chains, crowning and the reversed ending.")


func _test_generated_setup() -> void:
	var menu := (load("res://scenes/menus/mode_select.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	await process_frame
	menu.call("_on_single_player_pressed")
	var options: Array = menu.get("_solo_setup_options")
	_expect(options.size() == 1 and (menu.get_node("%SoloSetupChoices") as Control).visible,
		"Solo setup must offer the game-declared side choice.")
	if options.size() == 1:
		var buttons: Array = options[0]["buttons"]
		_expect(buttons.size() == 2, "Both Red and Ivory must be selectable.")
		if buttons.size() == 2:
			(buttons[1] as Button).pressed.emit()
			_expect(int(_settings.call("tunable_choice", Options.PLAYER_SIDE_KEY)) == State.IVORY,
				"The generated Ivory button must persist through Settings.")
			_expect((menu.get_node("%ConfirmDescription") as Label).text.contains("Ivory"),
				"Solo confirmation must describe the chosen human side.")
	menu.call("_on_multiplayer_pressed")
	_expect(not (menu.get_node("%SoloSetupChoices") as Control).visible
		and not (menu.get_node("%OpponentSelector") as Control).visible,
		"Local setup must not expose a solo side or a second CPU picker.")
	menu.queue_free()
	await process_frame
	var settings_menu := (
		load("res://scenes/menus/settings_menu.tscn") as PackedScene
	).instantiate()
	settings_menu.set("game_context_id", Options.GAME_ID)
	get_root().add_child(settings_menu)
	await process_frame
	var controls: Dictionary = settings_menu.get("_option_controls")
	for option in Options.TUNABLES:
		_expect(controls.has(option["key"]), "The generated Game tab must contain " + option["key"])
	var bindings: Dictionary = settings_menu.get("_binding_buttons")
	for binding in Options.CONTROL_BINDINGS:
		_expect(bindings.has(binding["key"]), "The generated Controls tab must contain " + binding["key"])
	settings_menu.queue_free()
	await process_frame
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.RED)


func _new_game(cpu := false) -> Node:
	if cpu:
		_session.call("configure_single_player")
	else:
		_session.call("configure_multiplayer", 0)
	var packed := load(GAME) as PackedScene
	var fixture := load(FIXTURE) as Script
	if packed == null or fixture == null or not fixture.can_instantiate():
		printerr("The Anti Checkers gameplay scene and fixture must compile.")
		quit(1)
		return null
	var game := packed.instantiate()
	game.set_script(fixture)
	get_root().add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	(game.get("_board_input") as Control).grab_focus()
	return game


func _free_game(game: Node) -> void:
	game.queue_free()
	await process_frame


func _test_board_input() -> void:
	var game := await _new_game()
	var state: State = game.get("_state")
	var viewport := game.get("_board_viewport") as SubViewport
	var container := game.get("_board_container") as SubViewportContainer
	_expect(viewport.own_world_3d and viewport.gui_disable_input and viewport.transparent_bg
		and container.stretch and container.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"The 3D board must be isolated beneath the 2D shell and native input overlay.")
	_expect((game.get_node("%RoundTimer") as Timer).is_stopped()
		and not bool(game.get("_lives_mode")), "Saved Lives must not eliminate checkers players.")
	game.call("_lose_life", 0, 99)
	_expect(bool(game.get("_round_active")), "Arcade mistakes cannot end a self-paced match.")
	_action(game, Options.SELECT_ACTION)
	_expect(int(game.get("_selected")) == _square("e3"), "Keyboard selection starts on e3.")
	_action(game, Options.CURSOR_UP_ACTION)
	_action(game, Options.CURSOR_LEFT_ACTION)
	_action(game, Options.SELECT_ACTION)
	_expect(state.board[_square("d4")] == State.MAN and state.turn == State.IVORY
		and state.ply_count == 1, "Keyboard input must commit e3-d4 exactly once.")
	game.call("_on_play_again_pressed")
	state = game.get("_state")
	_touch(game, "e3")
	_touch(game, "f4")
	_expect(state.board[_square("f4")] == State.MAN and state.ply_count == 1,
		"Tap selection and destination must use the same model path.")
	var emulated := InputEventMouseButton.new()
	emulated.pressed = true
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	(game.get("_board_input") as Control).call("_gui_input", emulated)
	_expect(state.ply_count == 1, "A synthesized mouse event must not replay a touch.")
	var sounds: Dictionary = game.get("_sounds")
	_expect(sounds.size() == 4, "The game must provide its own four semantic sound cues.")
	for cue: String in sounds:
		var sound: AudioStreamWAV = sounds[cue]
		_expect(sound.data.size() > 2048 and sound.mix_rate == 22050,
			"The original %s cue must contain playable PCM." % cue)
	await _free_game(game)


func _test_jump_chain() -> void:
	var game := await _new_game()
	var state := _position(game, {
		"a3": State.MAN, "c3": State.MAN, "d4": -State.MAN,
		"f6": -State.MAN, "h8": -State.MAN,
	})
	_settings.call("set_value", Options.SHOW_HINTS_KEY, false)
	game.call("_on_square_pressed", _square("a3"))
	_expect(int(game.get("_selected")) == -1, "A quiet piece cannot evade a capture elsewhere.")
	_play(game, "c3", "e5")
	_expect(state.forced_from == _square("e5") and state.turn == State.RED
		and state.ply_count == 0, "The first jump must retain the turn and lock its checker.")
	var rule: Label = game.get("_match_panel").get("_rule")
	_expect(rule.text.contains("KEEP JUMPING") and rule.text.contains("E5"),
		"Continuation must be named explicitly even with move hints off.")
	game.call("_cancel_selection")
	_expect(int(game.get("_selected")) == _square("e5"),
		"Cancel cannot undo or abandon an already started jump chain.")
	game.call("_on_square_pressed", _square("a3"))
	_expect(int(game.get("_selected")) == _square("e5"),
		"Selecting another checker cannot transfer a continuation.")
	game.call("_on_square_pressed", _square("g7"))
	_expect(state.forced_from == -1 and state.turn == State.IVORY and state.ply_count == 1,
		"Completing both jumps passes exactly one turn.")
	_expect((game.get("_moves_made") as Array)[0] == 1
		and (game.get("_captures_taken") as Array)[0] == 2
		and (game.get("_longest_chain") as Array)[0] == 2,
		"Turn statistics must distinguish a two-jump chain from two separate turns.")
	var ledger: PackedStringArray = game.get("_ledger")
	_expect(ledger.size() == 1 and ledger[0].contains("c3xe5xg7"),
		"The move ledger must keep a complete chain together.")
	var payload: Dictionary = game.call("_share_payload")
	_expect(payload["turn_count"] == 1 and payload["pieces_left"] == [2, 1],
		"The scorecard must carry completed turns and both sides' remaining checkers.")
	_settings.call("set_value", Options.SHOW_HINTS_KEY, true)
	await _free_game(game)


func _test_crowning() -> void:
	var game := await _new_game()
	var state := _position(game, {
		"b6": State.MAN, "c7": -State.MAN, "e7": -State.MAN, "h8": -State.MAN,
	})
	_play(game, "b6", "d8")
	_expect(state.board[_square("d8")] == State.KING and state.forced_from == -1
		and state.turn == State.IVORY, "Crowning must end the turn, not start a backward jump.")
	_expect((game.get("_promotions") as Array)[0] == 1
		and str(game.get("_last_move_text")).contains("turn ends"),
		"Crowning must be counted and explained without a chess promotion dialog.")
	_expect(not (game.get("_dialog") as Control).visible,
		"English checkers crowns automatically without offering a promotion choice.")
	var king_visible := false
	for piece: Dictionary in game.get("_view").get("_pieces"):
		if piece["square"] == _square("d8"):
			king_visible = piece["kind"] == State.KING
	_expect(king_visible, "The committed promotion must become a stacked 3D king.")
	await _free_game(game)


func _test_cpu_pause_and_replay() -> void:
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.IVORY)
	var game := await _new_game(true)
	var state: State = game.get("_state")
	_expect(int(game.get("_human_side")) == State.IVORY and state.turn == State.RED,
		"An Ivory human must face a Red CPU opening, with the human still in P1.")
	game.call("_on_square_pressed", _square("e3"))
	_expect(int(game.get("_selected")) == -1, "The human cannot select the CPU's opening move.")
	game.call("_update_round", 0.05, 0.0)
	var before := state.board.duplicate()
	var wait_before := float(game.get("_cpu_wait"))
	paused = true
	game.call("_update_round", 10.0, 0.0)
	_expect(state.board == before and float(game.get("_cpu_wait")) == wait_before,
		"Pause must suspend both CPU thinking and its move delay.")
	paused = false
	for step in 40:
		game.call("_update_round", 0.1, 0.0)
		if state.ply_count > 0:
			break
	_expect(state.ply_count == 1 and state.turn == State.IVORY,
		"The CPU must complete a legal Red opening, then wait for the Ivory human.")
	game.call("_on_play_again_pressed")
	state = _position(game, {
		"a3": State.MAN, "c3": State.MAN, "d4": -State.MAN,
		"f6": -State.MAN, "h8": -State.MAN,
	})
	for step in 40:
		game.call("_update_round", 0.1, 0.0)
		if state.ply_count > 0:
			break
	_expect(state.ply_count == 1 and state.turn == State.IVORY
		and state.board[_square("g7")] == State.MAN
		and (game.get("_captures_taken") as Array)[0] == 2,
		"The CPU must finish every jump before handing control back to the human.")
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.RED)
	_settings.call("set_value", Options.CPU_DIFFICULTY_KEY, Options.CPU_CUNNING)
	_expect(int(game.get("_human_side")) == State.IVORY
		and int(game.get("_difficulty")) == Options.CPU_CASUAL,
		"Changing side or difficulty mid-match must not swap live players.")
	game.call("_on_play_again_pressed")
	state = game.get("_state")
	_expect(int(game.get("_human_side")) == State.RED
		and int(game.get("_difficulty")) == Options.CPU_CUNNING and state.ply_count == 0,
		"Replay must adopt both next-match choices and cancel stale CPU work.")
	game.call("_update_round", 5.0, 0.0)
	_expect(state.ply_count == 0, "A cancelled Red CPU cannot move in a new Red-human match.")
	_settings.call("set_value", Options.CPU_DIFFICULTY_KEY, Options.CPU_CASUAL)
	await _free_game(game)


func _test_endings_and_seats() -> void:
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.IVORY)
	var game := await _new_game(true)
	var state := _position(game, {"c3": State.MAN, "d4": -State.MAN})
	for step in 20:
		game.call("_update_round", 0.1, 0.0)
		if state.finished:
			break
	_expect(state.finished and state.winner == State.IVORY,
		"The CPU taking the human's last checker must make the human win.")
	game.call("_complete_match")
	_expect((game.get_node("%ResultLabel") as Label).text == "IVORY WINS!",
		"Results must describe the model winner, not conventional checkers victory.")
	var payload: Dictionary = game.call("_share_payload")
	_expect(payload["score_values"] == [12, 11] and payload["pieces_left"] == [1, 0]
		and str(payload["score_caption"]).begins_with("IVORY - RED"),
		"Solo scores stay in human/CPU seat order while artwork stays explicitly Red/Ivory.")
	var awards: PackedStringArray = game.get("observed_achievements")
	_expect(awards.has("anti_checkers_giveaway") and awards.has("anti_checkers_outsmarted"),
		"An Ivory human giveaway win must earn the human's achievements.")
	await _free_game(game)
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.RED)
	game = await _new_game()
	var blocked := PackedInt32Array()
	blocked.resize(64)
	for square in 40:
		if State.is_playable(square):
			blocked[square] = State.MAN if square < 24 else -State.MAN
	state = game.get("_state")
	_expect(state.set_position(blocked, State.RED), "The blocked-side fixture must be legal.")
	game.call("_sync_match_scores")
	game.call("_end_round")
	_expect(state.winner == State.RED and (game.get("_scores") as Array) == [0, 4]
		and (game.get_node("%ResultLabel") as Label).text == "RED WINS!",
		"A blocked player with MORE pieces wins even when the displayed giveaway score is lower.")
	game.call("_on_play_again_pressed")
	state = _position(game, {"c3": State.MAN, "d4": -State.MAN})
	_play(game, "c3", "e5")
	paused = true
	await create_timer(0.45, true).timeout
	_expect(bool(game.get("_round_active")), "The final-move hold must pause with the scene.")
	paused = false
	game.call("_on_play_again_pressed")
	game.call("_complete_match")
	state = game.get("_state")
	_expect(not state.finished and state.ply_count == 0 and bool(game.get("_round_active"))
		and not (game.get_node("%RoundOver") as Control).visible,
		"An old completion timer cannot end the replayed match.")
	await _free_game(game)


func _test_resignation_and_abandon() -> void:
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.IVORY)
	var game := await _new_game(true)
	var state: State = game.get("_state")
	game.call("_request_resignation")
	_expect((game.get("_dialog") as Control).visible
		and int(game.get("_resigning_side")) == State.IVORY,
		"Solo resignation must ask for the human's side, even during the CPU turn.")
	game.call("_update_round", 4.0, 0.0)
	_expect(state.ply_count == 0, "CPU work must wait behind a decision dialog.")
	game.call("_cancel_selection")
	_expect(not state.finished and not (game.get("_dialog") as Control).visible,
		"Keep playing must dismiss resignation without mutating the match.")
	game.call("_request_resignation")
	game.call("_confirm_resignation")
	game.call("_complete_match")
	_expect(state.result_reason == "resignation" and state.winner == State.RED,
		"Conceding must award the opponent, never count as a giveaway win.")
	var awards: PackedStringArray = game.get("observed_achievements")
	_expect(not awards.has("anti_checkers_giveaway") and not awards.has("anti_checkers_outsmarted"),
		"A resigning human cannot earn the CPU-win or giveaway achievement.")
	game.call("_on_play_again_pressed")
	state = game.get("_state")
	game.call("_update_round", 0.1, 0.0)
	game.call("_abandon_match")
	game.call("_update_round", 5.0, 0.0)
	game.call("_complete_match")
	_expect(state.ply_count == 0 and not state.finished
		and (game.get("observed_achievements") as PackedStringArray).is_empty(),
		"Abandonment must cancel CPU/completion work without inventing a result.")
	await _free_game(game)
	_settings.call("set_value", Options.PLAYER_SIDE_KEY, State.RED)


func _test_camera_and_live_options() -> void:
	var game := await _new_game()
	var view: Node = game.get("_view")
	var camera := view.get("camera") as Camera3D
	var state: State = game.get("_state")
	var before := state.board.duplicate()
	_expect(bool(view.get("top_down")) and camera.basis.z.is_equal_approx(Vector3.UP),
		"Local humans must share a truly overhead camera.")
	Input.action_press(Options.CAMERA_RIGHT_ACTION)
	game.call("_update_camera_input", 0.1)
	Input.action_release(Options.CAMERA_RIGHT_ACTION)
	_expect(view.get("pan_offset") != Vector2.ZERO
		and camera.basis.z.is_equal_approx(Vector3.UP),
		"Local camera keys must pan without tilting.")
	var pan: Vector2 = view.get("pan_offset")
	(game.get("_match_panel").get("_resign") as Button).grab_focus()
	Input.action_press(Options.CAMERA_RIGHT_ACTION)
	game.call("_update_camera_input", 0.1)
	Input.action_release(Options.CAMERA_RIGHT_ACTION)
	_expect(view.get("pan_offset") == pan, "Keyboard button navigation must not pan the board.")
	(game.get("_board_input") as Control).grab_focus()
	game.call("_flip_board")
	_settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	_expect(not bool(view.call("camera_is_moving"))
		and camera.basis.z.is_equal_approx(Vector3.UP),
		"Reduced motion must settle a flip immediately without losing the overhead lock.")
	game.call("_reset_camera")
	_expect(view.call("square_direction", Vector2i(0, 1)) == Vector2i(0, 1),
		"Home must restore the original keyboard directions.")
	_settings.call("set_value", Options.PIECE_LABELS_KEY, false)
	_expect(not bool(game.get("_board_input").get("_piece_labels")),
		"The labels option must affect the existing board immediately.")
	_settings.call("set_value", Options.SHOW_HINTS_KEY, false)
	_expect(not bool(game.get("_board_input").get("_hints")),
		"The hints option must affect the existing board immediately.")
	game.call("_request_resignation")
	var pose := camera.transform
	game.call("_drag_camera", Vector2(140, 40))
	game.call("_zoom_camera", 1.0)
	_expect(camera.transform == pose and float(view.get("zoom_factor")) == 1.0,
		"Camera gestures cannot operate behind a decision.")
	game.call("_cancel_selection")
	_expect(state.board == before and state.ply_count == 0,
		"No presentation or accessibility option may change the checkers position.")
	_settings.call("set_value", Options.PIECE_LABELS_KEY, true)
	_settings.call("set_value", Options.SHOW_HINTS_KEY, true)
	_settings.call("set_value", Settings.REDUCED_MOTION_KEY, false)
	await _free_game(game)


func _position(game: Node, pieces: Dictionary, turn := State.RED) -> State:
	var board := PackedInt32Array()
	board.resize(64)
	for square: String in pieces:
		board[_square(square)] = int(pieces[square])
	var state: State = game.get("_state")
	_expect(state.set_position(board, turn), "The scene fixture position must be valid.")
	game.set("_legal", state.legal_moves())
	game.set("_selected", -1)
	game.set("_cpu_scheduled", false)
	(game.get("_cpu") as RefCounted).call("cancel")
	var colors: Array[Color] = game.call("_side_colors")
	(game.get("_view") as Node).call("reset", state, colors)
	game.call("_sync_match_scores")
	game.call("_present_position")
	game.call("_update_scores")
	return state


func _action(game: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	game.call("_handle_gameplay_input", event)


func _play(game: Node, source: String, destination: String) -> void:
	if int(game.get("_selected")) != _square(source):
		game.call("_on_square_pressed", _square(source))
	game.call("_on_square_pressed", _square(destination))


func _touch(game: Node, square: String) -> void:
	var view: Node = game.get("_view")
	var input := game.get("_board_input") as Control
	var point: Vector3 = view.call("square_position", _square(square))
	var projected: Vector2 = input.call("_project", point)
	_expect(int(input.call("_pick_square", projected)) == _square(square),
		"A tap aimed at %s must pick that square." % square)
	var event := InputEventScreenTouch.new()
	event.position = projected
	event.pressed = true
	input.call("_gui_input", event)


func _square(name: String) -> int:
	return name.unicode_at(0) - 97 + (int(name.substr(1)) - 1) * 8


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
