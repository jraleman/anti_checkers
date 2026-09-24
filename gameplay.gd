extends GameShell

## English giveaway checkers inside the shared pause, settings and results shell.

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const CpuPlayer = preload("res://games/anti_checkers/board/cpu_player.gd")
const Options = preload("res://games/anti_checkers/anti_checkers_options.gd")
const BoardView = preload("res://games/anti_checkers/board/board_view.gd")
const BoardInput = preload("res://games/anti_checkers/ui/board_input.gd")
const MatchPanel = preload("res://games/anti_checkers/ui/match_panel.gd")
const MatchDialog = preload("res://games/anti_checkers/ui/match_dialog.gd")
const CheckersAudio = preload("res://games/anti_checkers/board/checkers_audio.gd")
const CPU_PAUSE := 0.50

var _state: State
var _cpu: CpuPlayer
var _cpu_enabled := true
var _human_side := State.RED
var _cpu_side := State.IVORY
var _difficulty := Options.DEFAULT_CPU_DIFFICULTY
var _cpu_scheduled := false
var _cpu_failed := false
var _cpu_wait := 0.0
var _show_hints := true
var _piece_labels := true
var _selected := -1
var _cursor := 20
var _keyboard_cursor := false
var _legal: Array[Dictionary] = []
var _moves_made: Array[int] = [0, 0]
var _captures_taken: Array[int] = [0, 0]
var _promotions: Array[int] = [0, 0]
var _longest_chain: Array[int] = [0, 0]
var _chain_jumps := 0
var _ledger := PackedStringArray()
var _last_move_text := "Red moves first."
var _resigning_side := -1
var _view: BoardView
var _board_container: SubViewportContainer
var _board_viewport: SubViewport
var _board_input: BoardInput
var _match_panel: MatchPanel
var _dialog: MatchDialog
var _completion_timer: Timer
var _completion_pending := false
var _completion_round_id := -1
var _entering := false
var _leaving := false
var _sounds: Dictionary[String, AudioStreamWAV] = {}
var _ui_factor := 1.0
var _hud_font_sizes: Dictionary[Control, int] = {}
var _capture_inset := 0.0


func _ready() -> void:
	_entering = Router.is_transitioning()
	if _entering:
		Router.transition_finished.connect(_on_entered, CONNECT_ONE_SHOT)
	AudioManager.stop_music(0.2)
	super()


func _process(delta: float) -> void:
	if _abort_if_exiting():
		return
	_update_camera_input(delta)
	super(delta)


func _exit_tree() -> void:
	_abandon_match()


## The folder's manifest is the only registration needed for --game=anti_checkers.
func game_id() -> String:
	return Options.GAME_ID


func _load_round_settings() -> void:
	super()
	_difficulty = Settings.tunable_choice(Options.CPU_DIFFICULTY_KEY)
	_show_hints = Settings.tunable_bool(Options.SHOW_HINTS_KEY)
	_piece_labels = Settings.tunable_bool(Options.PIECE_LABELS_KEY)


func _prepare_session() -> void:
	super()
	_cpu_enabled = GameSession.is_single_player()
	if not _cpu_enabled and GameSession.player_two_is_cpu():
		GameSession.configure_multiplayer(
			GameSession.PlayerTwoController.HUMAN, GameSession.cpu_difficulty
		)
	_human_side = (
		Settings.tunable_choice(Options.PLAYER_SIDE_KEY) if _cpu_enabled else State.RED
	)
	_cpu_side = 1 - _human_side


func _build_playfield() -> void:
	_board_container = SubViewportContainer.new()
	_board_container.name = "CheckersBoardView"
	_board_container.stretch = true
	_board_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(_board_container)
	_board_viewport = SubViewport.new()
	_board_viewport.name = "CheckersViewport"
	_board_viewport.own_world_3d = true
	_board_viewport.transparent_bg = true
	_board_viewport.gui_disable_input = true
	_board_viewport.msaa_3d = Viewport.MSAA_2X
	_board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_board_container.add_child(_board_viewport)
	_view = BoardView.new()
	_view.name = "CheckersTable"
	_board_viewport.add_child(_view)
	_view.set_reduced_motion(_reduced_motion_enabled)
	var overlay := _hud.get_node("Overlay")
	_board_input = BoardInput.new()
	_board_input.name = "CheckersBoardInput"
	overlay.add_child(_board_input)
	_board_input.bind_view(_view)
	_board_input.square_pressed.connect(_on_square_pressed)
	_board_input.square_hovered.connect(_on_square_hovered)
	_board_input.camera_dragged.connect(_drag_camera)
	_board_input.camera_zoomed.connect(_zoom_camera)
	_board_input.key_input.connect(_handle_gameplay_input)
	_match_panel = MatchPanel.new()
	_match_panel.name = "MatchPanel"
	overlay.add_child(_match_panel)
	_match_panel.flip_requested.connect(_flip_board)
	_match_panel.reset_camera_requested.connect(_reset_camera)
	_match_panel.zoom_requested.connect(_zoom_camera)
	_match_panel.resign_requested.connect(_request_resignation)
	_dialog = MatchDialog.new()
	_dialog.name = "MatchDecision"
	_hud.add_child(_dialog)
	_dialog.resignation_confirmed.connect(_confirm_resignation)
	_dialog.cancelled.connect(_cancel_selection)
	_completion_timer = Timer.new()
	_completion_timer.name = "MatchCompletion"
	_completion_timer.one_shot = true
	_completion_timer.timeout.connect(_complete_match)
	add_child(_completion_timer)
	_sounds = CheckersAudio.make_cues()
	get_viewport().size_changed.connect(_resize_board)
	(_player_one_card.get_parent() as Control).resized.connect(_layout_board)
	_hint.resized.connect(_layout_board)
	(_hint.get_parent().get_parent() as Control).item_rect_changed.connect(_layout_board)
	_board_viewport.size_changed.connect(_sync_projection)
	_resize_board()
	AudioManager.attach_ui_sounds(_match_panel)
	AudioManager.attach_ui_sounds(_dialog)


func _start_round() -> void:
	if not _abort_if_exiting():
		super()


func _reset_round_state() -> void:
	_finish_round()
	_prepare_session()
	_state = State.new()
	_cpu = CpuPlayer.new(_difficulty, _rng.randi())
	_cpu_failed = false
	_selected = -1
	_cursor = 20 if _human_side == State.RED else 43
	_keyboard_cursor = false
	_moves_made = [0, 0]
	_captures_taken = [0, 0]
	_promotions = [0, 0]
	_longest_chain = [0, 0]
	_chain_jumps = 0
	_ledger.clear()
	_last_move_text = "Red moves first."
	_legal = _state.legal_moves()
	_view.configure_camera(not _cpu_enabled, _human_side)
	_view.reset(_state, _side_colors())
	_present_position()


func _activate_round() -> void:
	_announcement.hide()
	_board_input.grab_focus.call_deferred()
	AudioManager.request_caption(
		"%s to move. Give away all your checkers to win." % _side_player_name(State.RED)
	)


func _update_round(delta: float, _time_left: float) -> void:
	if (
		get_tree().paused or _completion_pending or _dialog.visible
		or _state.finished or _cpu_failed or _leaving
	):
		return
	if not _cpu_enabled or _state.turn != _cpu_side:
		return
	if not _cpu_scheduled:
		_cpu.begin_turn(_state)
		_cpu_scheduled = true
		_cpu_wait = CPU_PAUSE
	_cpu_wait -= delta
	if not _cpu.completed:
		_cpu.think(48)
	if _cpu.completed and _cpu_wait <= 0.0 and not _view.camera_is_moving():
		if _cpu.chosen_move.is_empty():
			_cpu_failed = true
			push_error("Anti Checkers CPU returned no move for a playable position.")
			_feedback("CPU could not choose a move. Pause and restart the match.")
			return
		_commit_move(_cpu.chosen_move)


func _handle_gameplay_input(event: InputEvent) -> void:
	if (
		not _round_active or _leaving or get_tree().paused or not event.is_pressed()
		or _dialog.visible or not _board_input.has_focus()
	):
		return
	for action in [
		Options.CAMERA_UP_ACTION, Options.CAMERA_DOWN_ACTION,
		Options.CAMERA_LEFT_ACTION, Options.CAMERA_RIGHT_ACTION,
	]:
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			return
	if event.is_echo():
		return
	if event.is_action_pressed(Options.CAMERA_RESET_ACTION):
		get_viewport().set_input_as_handled()
		_reset_camera()
		return
	if event.is_action_pressed(Options.FLIP_ACTION):
		get_viewport().set_input_as_handled()
		_flip_board()
		return
	if event.is_action_pressed(Options.CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		_cancel_selection()
		return
	if not _human_can_move():
		return
	var direction := Vector2i.ZERO
	if event.is_action_pressed(Options.CURSOR_UP_ACTION):
		direction.y = 1
	elif event.is_action_pressed(Options.CURSOR_DOWN_ACTION):
		direction.y = -1
	elif event.is_action_pressed(Options.CURSOR_LEFT_ACTION):
		direction.x = -1
	elif event.is_action_pressed(Options.CURSOR_RIGHT_ACTION):
		direction.x = 1
	elif event.is_action_pressed(Options.SELECT_ACTION):
		get_viewport().set_input_as_handled()
		_keyboard_cursor = true
		_on_square_pressed(_cursor)
		return
	else:
		return
	get_viewport().set_input_as_handled()
	direction = _view.square_direction(direction)
	var file := clampi(_cursor % 8 + direction.x, 0, 7)
	var rank := clampi(_cursor / 8 + direction.y, 0, 7)
	_cursor = file + rank * 8
	_keyboard_cursor = true
	_present_position()


func _human_can_move() -> bool:
	return (
		_state != null and _round_active and not _leaving and not get_tree().paused
		and not _state.finished and not _completion_pending and not _dialog.visible
		and not _view.camera_is_moving()
		and not (_cpu_enabled and _state.turn == _cpu_side)
	)


func _on_square_pressed(square: int) -> void:
	if not _human_can_move():
		return
	if square < 0:
		_cancel_selection()
		return
	if not State.is_playable(square):
		_feedback("Checkers use the dark squares. Choose a dark square.")
		return
	_cursor = square
	if _selected >= 0:
		for move in _legal:
			if int(move["from"]) == _selected and int(move["to"]) == square:
				_commit_move(move)
				return
	if square == _selected and _state.forced_from < 0:
		_cancel_selection()
		return
	if _state.forced_from >= 0 and square != _state.forced_from:
		_feedback("Keep jumping with the checker on %s." % State.square_name(_state.forced_from))
		return
	if State.side_of(_state.board[square]) == _state.turn:
		for move in _legal:
			if int(move["from"]) == square:
				_selected = square
				_present_position()
				return
		_feedback(
			"A capture is available elsewhere. Choose a checker that can jump."
			if _capture_required() else "That checker has no legal move."
		)
		return
	_feedback("Choose a %s checker or a legal destination." % _side_name(_state.turn))


func _commit_move(move: Dictionary) -> void:
	if (
		_abort_if_exiting() or not _round_active or _state.finished
		or get_tree().paused or _dialog.visible or _completion_pending
	):
		return
	var side := _state.turn
	var continued := _state.forced_from >= 0
	if not _state.play_move(move):
		push_error("Anti Checkers rejected a move supplied by its legal-move list.")
		_feedback("That move is no longer legal. Select a checker again.")
		return
	_cpu.cancel()
	_cpu_scheduled = false
	var captured := int(_state.last_move["capture"]) >= 0
	var crowned := int(_state.last_move["promotion"]) == State.KING
	if captured:
		_captures_taken[side] += 1
		_chain_jumps += 1
	if crowned:
		_promotions[side] += 1
	if bool(_state.last_move["turn_finished"]):
		_moves_made[side] += 1
		_longest_chain[side] = maxi(_longest_chain[side], _chain_jumps)
		_chain_jumps = 0
	_selected = _state.forced_from
	_legal = _state.legal_moves()
	_cursor = _selected if _selected >= 0 else (
		int(_legal[0]["from"]) if not _legal.is_empty() else int(_state.last_move["to"])
	)
	_sync_match_scores()
	_append_move(side, _state.last_move, continued)
	_view.present_move(_state.last_move, _state)
	_present_position()
	_update_scores()
	_update_streaks()
	_play_sound("crown" if crowned else "capture" if captured else "move")
	AudioManager.request_caption(_last_move_text + (
		" Keep jumping with the same checker." if _state.forced_from >= 0 else
		" Capture required." if _capture_required() else ""
	))
	if _state.finished:
		_queue_completion()


func _append_move(side: int, move: Dictionary, continued: bool) -> void:
	var target := State.square_name(int(move["to"]))
	var separator := "x" if int(move["capture"]) >= 0 else "-"
	var notation := State.square_name(int(move["from"])) + separator + target
	var crowned := int(move["promotion"]) == State.KING
	if continued:
		_ledger[_ledger.size() - 1] += "x" + target
	else:
		var number := _state.ply_count + (0 if bool(move["turn_finished"]) else 1)
		_ledger.append("%d. %s  %s" % [number, _side_name(side), notation])
	if crowned:
		_ledger[_ledger.size() - 1] += "=K"
	_last_move_text = "%s %s %s." % [
		_side_name(side), "continued" if continued else "played", notation,
	]
	if crowned:
		_last_move_text += " Crowned a king; the turn ends."


func _cancel_selection() -> void:
	_selected = _state.forced_from
	_resigning_side = -1
	_dialog.dismiss()
	_present_position()
	if _state.forced_from >= 0:
		_feedback("Finish the jump chain from %s." % State.square_name(_state.forced_from))
	if _round_active:
		_board_input.grab_focus()


func _camera_available() -> bool:
	return (
		_state != null and _round_active and not _leaving and not get_tree().paused
		and not _completion_pending and not _dialog.visible and not _state.finished
	)


func _update_camera_input(delta: float) -> void:
	if _camera_available() and _board_input.has_focus():
		_view.move_camera(Input.get_vector(
			Options.CAMERA_LEFT_ACTION, Options.CAMERA_RIGHT_ACTION,
			Options.CAMERA_UP_ACTION, Options.CAMERA_DOWN_ACTION
		), delta)


func _drag_camera(relative: Vector2) -> void:
	if _camera_available():
		_view.drag_camera(relative)


func _zoom_camera(steps: float) -> void:
	if _camera_available():
		_view.zoom_camera(steps)


func _flip_board() -> void:
	if _camera_available():
		_view.flip_board()
		_board_input.grab_focus()


func _reset_camera() -> void:
	if _camera_available():
		_view.reset_camera()
		_board_input.grab_focus()


func _request_resignation() -> void:
	if not _camera_available():
		return
	_resigning_side = _human_side if _cpu_enabled else _state.turn
	_dialog.show_resignation(_side_name(_resigning_side))


func _confirm_resignation() -> void:
	if _abort_if_exiting() or not _round_active or get_tree().paused:
		return
	if not _state.resign(_resigning_side):
		push_error("Anti Checkers could not apply the confirmed resignation.")
		_feedback("This match can no longer be resigned.")
		return
	_dialog.dismiss()
	_legal.clear()
	_cpu.cancel()
	_present_position()
	_queue_completion()


func _queue_completion() -> void:
	_cpu.cancel()
	_completion_pending = true
	_completion_round_id = _round_id
	_completion_timer.start(0.01 if _reduced_motion_enabled else BoardView.MOVE_SECONDS + 0.08)


func _complete_match() -> void:
	if _completion_pending and _completion_round_id == _round_id and _state.finished:
		_end_round()


func _end_round() -> void:
	if _abort_if_exiting() or not _round_active:
		return
	if _state.finished:
		_play_sound("finish")
		AudioManager.request_caption(_outcome_text())
	super()


func _finish_round() -> void:
	_cpu_scheduled = false
	_completion_pending = false
	_completion_round_id = -1
	_resigning_side = -1
	if _cpu != null:
		_cpu.cancel()
	if _completion_timer != null:
		_completion_timer.stop()
	if _dialog != null:
		_dialog.dismiss()


func _present_position() -> void:
	if _state == null or _board_input == null:
		return
	_board_input.present(_state, _selected, _cursor, _legal,
		_show_hints, _piece_labels, _keyboard_cursor)
	_match_panel.present(
		_outcome_text() if _state.finished else "%s to move" % _side_player_name(_state.turn),
		_capture_required(), State.square_name(_state.forced_from),
		_cpu_enabled and _state.turn == _cpu_side, _state.finished
	)
	_match_panel.set_ledger(_ledger, _last_move_text)
	_describe_square(_cursor)
	_time_caption.text = "TURN"
	_time_label.text = "%02d" % maxi(1, _state.ply_count + (0 if _state.finished else 1))


func _capture_required() -> bool:
	return not _legal.is_empty() and int(_legal[0]["capture"]) >= 0


func _on_square_hovered(square: int) -> void:
	if _state != null and not _dialog.visible:
		_describe_square(_cursor if square < 0 and _keyboard_cursor else square)


func _describe_square(square: int) -> void:
	var text := "Click / tap a checker, then its destination."
	if square >= 0 and square < 64:
		text = _square_description(square)
	if _selected >= 0:
		text = "Selected %s.\n%s" % [
			_square_description(_selected),
			"Continue this checker's jumps." if _state.forced_from >= 0
			else "Choose a legal destination.",
		]
	_match_panel.describe_square(text)
	_board_input.accessibility_description = text + (
		" Keep jumping with the same checker." if _state.forced_from >= 0 else
		" Capture required." if _capture_required() else " No capture available."
	)


func _square_description(square: int) -> String:
	var piece := _state.board[square]
	if piece == State.EMPTY:
		return "%s: %s" % [
			State.square_name(square),
			"empty dark square" if State.is_playable(square) else "light square, not playable",
		]
	return "%s %s on %s" % [
		_side_name(State.side_of(piece)), State.piece_name(piece).to_lower(),
		State.square_name(square),
	]


func _feedback(text: String) -> void:
	_match_panel.describe_square(text)
	_board_input.accessibility_description = text
	AudioManager.request_caption(text)


func _reset_round_gauge() -> void:
	super()
	_time_progress.hide()
	_time_caption.text = "TURN"
	_time_label.text = "01"


func _update_scores() -> void:
	if _state != null:
		for player in 2:
			_score_label(player).text = str(_state.piece_count(_side_for_player(player)))


func _update_streaks() -> void:
	for player in 2:
		_streak_label(player).text = "%d / 12 GIVEN AWAY" % _scores[player]


func _sync_match_scores() -> void:
	for player in 2:
		var side := _side_for_player(player)
		_scores[player] = State.INITIAL_PIECES - _state.piece_count(side)
		_best_streaks[player] = _promotions[side]


# Model indices are colours; shell indices are seats, with the human always P1.
func _side_for_player(player: int) -> int:
	return _human_side if player == PLAYER_ONE else 1 - _human_side


func _player_for_side(side: int) -> int:
	return PLAYER_ONE if side == _human_side else PLAYER_TWO


func _side_colors() -> Array[Color]:
	return [
		_player_color(_player_for_side(State.RED)),
		_player_color(_player_for_side(State.IVORY)),
	]


func _configure_mode_ui() -> void:
	super()
	_player_one_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for control: Control in [
		_player_two_card, _round_versus, _round_player_two_card,
		_stats_versus, _player_two_stats_card,
	]:
		control.show()
	var labels := Settings.player_labels_enabled()
	_player_one_caption.text = ("P1 / " if labels else "") + _side_name(_human_side).to_upper()
	_player_two_caption.text = (
		"CPU / " if _cpu_enabled else "P2 / " if labels else ""
	) + _side_name(1 - _human_side).to_upper()
	_round_player_two_caption.text = _player_two_caption.text + " GIVEN AWAY"
	_player_two_stats_title.text = _player_two_caption.text
	(_round_player_one_score.get_parent().get_node("Caption") as Label).text = (
		_player_one_caption.text + " GIVEN AWAY"
	)
	(_player_one_stats_score.get_parent().get_node("Title") as Label).text = (
		_player_one_caption.text
	)
	_callout.hide()
	_hint.text = "Give away every checker. Captures and complete jump chains are compulsory."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_hint.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round_instructions.text = "Twelve new checkers. One more chance to give them all away."
	_share_card_hint.text = "Save this match's card. Its QR opens DeskCanSaw Games."
	if _match_panel != null:
		var keys := PackedStringArray()
		var camera_keys := PackedStringArray()
		for action in [
			Options.CURSOR_UP_ACTION, Options.CURSOR_DOWN_ACTION,
			Options.CURSOR_LEFT_ACTION, Options.CURSOR_RIGHT_ACTION,
		]:
			keys.append(Settings.control_key_label(action))
		for action in [
			Options.CAMERA_UP_ACTION, Options.CAMERA_DOWN_ACTION,
			Options.CAMERA_LEFT_ACTION, Options.CAMERA_RIGHT_ACTION,
		]:
			camera_keys.append(Settings.control_key_label(action))
		_match_panel.set_key_hint((
			"%s: squares\n%s: select | %s: cancel\n"
			+ "Right drag / %s: %s\nWheel / +/-: zoom | %s: reset\n%s: flip | Esc: pause"
		) % [
			" / ".join(keys), Settings.control_key_label(Options.SELECT_ACTION),
			Settings.control_key_label(Options.CANCEL_ACTION), " / ".join(camera_keys),
			"orbit" if _cpu_enabled else "pan",
			Settings.control_key_label(Options.CAMERA_RESET_ACTION),
			Settings.control_key_label(Options.FLIP_ACTION),
		])
		_present_position()


func _active_player_indices() -> Array[int]:
	return [PLAYER_ONE, PLAYER_TWO]


func _player_name(player: int) -> String:
	return _side_player_name(_side_for_player(player))


func _side_player_name(side: int) -> String:
	return (
		"CPU (%s)" % _side_name(side)
		if _cpu_enabled and side == _cpu_side else _side_name(side)
	)


func _side_name(side: int) -> String:
	return "Red" if side == State.RED else "Ivory"


func _round_mode_summary() -> String:
	return (
		"%s vs %s CPU (%s) - Untimed" % [
			_side_name(_human_side), ["Casual", "Thoughtful", "Cunning"][_difficulty],
			_side_name(_cpu_side),
		] if _cpu_enabled else "Local Multiplayer - Untimed"
	)


func _outcome_text() -> String:
	if not _state.finished:
		return "Match stopped"
	return "%s wins!" % _side_player_name(_state.winner) if _state.winner >= 0 else "Draw"


func _describe_round_outcome(_one: int, _two: int) -> Dictionary:
	var reason := "This match was interrupted; no result was recorded."
	match _state.result_reason:
		"no_pieces":
			reason = "%s gave away every checker." % _side_player_name(_state.winner)
		"no_moves":
			reason = "%s has no legal move. In Anti Checkers, that is a win." % (
				_side_player_name(_state.winner)
			)
		"repetition":
			reason = "The same position occurred three times."
		"forty_moves":
			reason = "Forty moves each without a capture or man move."
		"resignation":
			reason = "%s resigned." % _side_player_name(1 - _state.winner)
	return {
		"result": _outcome_text().to_upper(),
		"subtitle": "%s %s played." % [reason, _turn_phrase()],
		"color": _player_color(_player_for_side(_state.winner))
			if _state.winner >= 0 else Color("fff0dc"),
	}


func _round_totals() -> Dictionary:
	return {"hits": _state.ply_count, "attempts": _state.ply_count}


func _player_stats(player: int) -> Dictionary:
	var side := _side_for_player(player)
	return {
		"score": _scores[player], "hits": _moves_made[side],
		"misses": _captures_taken[side],
		"accuracy": _accuracy_percent(_scores[player], State.INITIAL_PIECES),
		"streak": _promotions[side],
	}


func _populate_score_screen(result_text: String, result_color: Color) -> void:
	super(result_text, result_color)
	_game_accuracy_stat.text = str(_state.piece_count(State.RED) + _state.piece_count(State.IVORY))
	_player_one_stats_streak.text = str(_promotions[_side_for_player(PLAYER_ONE)])
	_player_two_stats_streak.text = str(_promotions[_side_for_player(PLAYER_TWO)])


func _best_combo_summary() -> String:
	return "%s / %d given away / longest jump chain: %d" % [
		_turn_phrase(), int(_scores[0]) + int(_scores[1]),
		maxi(_longest_chain[0], _longest_chain[1]),
	]


func _turn_phrase() -> String:
	return "%d %s" % [_state.ply_count, "turn" if _state.ply_count == 1 else "turns"]


func _share_payload() -> Dictionary:
	var data := super()
	data["score_caption"] = "%s - %s GIVEN AWAY" % [
		_side_name(_side_for_player(PLAYER_ONE)).to_upper(),
		_side_name(_side_for_player(PLAYER_TWO)).to_upper(),
	]
	data["score"] = "%d - %d" % [_scores[0], _scores[1]]
	data["score_values"] = [_scores[0], _scores[1]]
	data["secondary_color"] = player_two_color
	data["pieces_left"] = [_state.piece_count(State.RED), _state.piece_count(State.IVORY)]
	data["turn_count"] = _state.ply_count
	data["accuracy_caption"] = "PIECES LEFT"
	data["accuracy"] = str(_state.piece_count(State.RED) + _state.piece_count(State.IVORY))
	data["accuracy_value"] = _state.piece_count(State.RED) + _state.piece_count(State.IVORY)
	data["hits_caption"] = "TURNS PLAYED"
	data["misses_value"] = _captures_taken[0] + _captures_taken[1]
	data["combo_caption"] = "KINGS CROWNED"
	data["combo"] = str(_promotions[0] + _promotions[1])
	data["combo_value"] = _promotions[0] + _promotions[1]
	data["challenge"] = "CAN YOU GIVE IT ALL AWAY?"
	data["cta"] = "TAKE A SEAT"
	data["qr_heading"] = "DISCOVER MORE GAMES"
	data["qr_copy"] = "Discover more games from DeskCanSaw."
	data["rematch_title"] = "JUMP. GIVE. WIN."
	data["rematch_copy"] = "Compulsory jumps. Unwanted crowns. A lighter way to win."
	return data


func _award_round_achievements(_one: int, _two: int) -> void:
	if not _state.finished:
		return
	_unlock_round_achievement("anti_checkers_first_match")
	var human_won := _state.winner >= 0 and (
		not _cpu_enabled or _state.winner == _human_side
	)
	if human_won and _state.result_reason == "no_pieces":
		_unlock_round_achievement("anti_checkers_giveaway")
	if human_won and _cpu_enabled:
		_unlock_round_achievement("anti_checkers_outsmarted")
	if _longest_chain[_human_side] > 1 or (
		not _cpu_enabled and _longest_chain[1 - _human_side] > 1
	):
		_unlock_round_achievement("anti_checkers_chain")


func _record_round(one: int, two: int) -> String:
	return super(one, two) if _state.finished else ""


func _set_reduced_motion_enabled(value: bool) -> void:
	super(value)
	if _view != null:
		_view.set_reduced_motion(value)
	if value and _completion_pending:
		_completion_timer.start(0.01)


func _spawn_round_confetti(color: Color) -> void:
	if _intense_effects_enabled:
		super(color)


func _on_game_setting_changed(key: String, _value: Variant) -> void:
	if key == Options.SHOW_HINTS_KEY or key == Options.PIECE_LABELS_KEY:
		_show_hints = Settings.tunable_bool(Options.SHOW_HINTS_KEY)
		_piece_labels = Settings.tunable_bool(Options.PIECE_LABELS_KEY)
		_present_position()


func _on_pause_closed() -> void:
	super()
	if _dialog.visible:
		_dialog.focus_decision()
	elif _round_active:
		_board_input.grab_focus()


func _resize_board() -> void:
	var dimensions := get_viewport_rect().size
	var compact := dimensions.y > dimensions.x
	var preference := float(Settings.get_value("ui/scale", 1.0))
	_ui_factor = maxf(
		1.0, dimensions.x * preference / maxf(get_window().size.x, 1.0) / 1.5
	)
	var pause_parent := _time_label.get_parent() if compact else _player_one_card.get_parent()
	if _pause_button.get_parent() != pause_parent:
		_pause_button.reparent(pause_parent, false)
	for card in [_player_one_card, _player_two_card]:
		card.custom_minimum_size.x = (dimensions.x - 84) * 0.28 if compact else 300.0
	for label in [
		_player_one_streak, _player_two_streak, _player_one_caption,
		_player_two_caption, _mode_title,
	]:
		label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART if compact else TextServer.AUTOWRAP_OFF
		)
	if compact:
		_mode_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	for control: Control in [
		_player_one_caption, _player_two_caption, _player_one_score, _player_two_score,
		_player_one_streak, _player_two_streak, _time_label, _time_caption,
		_mode_title, _hint, _pause_button,
	]:
		if not _hud_font_sizes.has(control):
			_hud_font_sizes[control] = control.get_theme_font_size("font_size")
		control.add_theme_font_size_override(
			"font_size", roundi(_hud_font_sizes[control] * _ui_factor)
		)
	_pause_button.custom_minimum_size = (
		Vector2(0, 66) if compact else Vector2(132, 48)
	) * _ui_factor
	_match_panel.set_readability_scale(_ui_factor, compact)
	_dialog.set_readability_scale(_ui_factor, compact)
	_layout_board.call_deferred()


func _playfield_bounds() -> Rect2:
	var dimensions := get_viewport_rect().size
	var top_bar := _player_one_card.get_parent() as Control
	var top := maxf(TOP_CLEARANCE, top_bar.get_global_rect().end.y + 18 * _ui_factor)
	var bottom := minf(
		dimensions.y - 35 * _ui_factor,
		(_hint.get_parent() as Control).get_global_rect().position.y - 16 * _ui_factor
	)
	bottom = minf(bottom, dimensions.y - _capture_inset)
	return Rect2(Vector2(SIDE_CLEARANCE, top),
		Vector2(maxf(dimensions.x - SIDE_CLEARANCE * 2, 1), maxf(bottom - top, 1)))


func _set_capture_inset(bottom: float) -> void:
	_capture_inset = maxf(bottom, 0.0)
	_layout_board.call_deferred()


func _layout_board() -> void:
	if _board_container == null or not is_inside_tree():
		return
	var bounds := _playfield_bounds()
	var board_rect := bounds
	var panel_rect := bounds
	if get_viewport_rect().size.y > get_viewport_rect().size.x:
		board_rect.size.y = minf(bounds.size.y * 0.60, bounds.size.x * 1.14)
		panel_rect.position.y = board_rect.end.y + 18
		panel_rect.size.y = maxf(bounds.end.y - panel_rect.position.y, 0.0)
	else:
		panel_rect.size.x = clampf(bounds.size.x * 0.27, 370, 470)
		panel_rect.position.x = bounds.end.x - panel_rect.size.x
		board_rect.size.x = maxf(panel_rect.position.x - bounds.position.x - 18, 1.0)
	_board_container.position = board_rect.position
	_board_container.size = board_rect.size
	_board_input.position = board_rect.position
	_board_input.size = board_rect.size
	_match_panel.position = panel_rect.position
	_match_panel.size = panel_rect.size
	_sync_projection.call_deferred()


func _sync_projection() -> void:
	if _view != null and is_inside_tree():
		_view.resize_view(Vector2(_board_viewport.size))


func _play_sound(cue: String) -> void:
	if DisplayServer.get_name() != "headless":
		AudioManager.play_sfx(_sounds[cue], -12.0)


func _on_entered(_path: String) -> void:
	_entering = false


func _abort_if_exiting() -> bool:
	if not _leaving and Router.is_transitioning() and not _entering:
		_abandon_match()
	return _leaving


func _abandon_match() -> void:
	_leaving = true
	_round_active = false
	if _round_timer != null:
		_round_timer.stop()
	_finish_round()


func _on_exit_to_main_menu_pressed() -> void:
	_abandon_match()
	Router.goto(main_menu_scene)
