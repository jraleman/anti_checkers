extends RefCounted

## Records real board input and explicitly labelled practice positions. The
## game's own move validation, animations, compulsory chains and results run.

signal keycap_requested(text: String)

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const Options = preload("res://games/anti_checkers/anti_checkers_options.gd")
const STEPS: Array[Dictionary] = [
	{"time": 0.0, "title": "Give away your checkers",
		"body": "Red moves first. Click a checker, then its destination. Men move diagonally forward."},
	{"time": 5.5, "title": "Inspect the whole board",
		"body": "Right-drag to orbit; scroll to zoom. WASD and Enter also select squares. Home resets the view."},
	{"time": 11.0, "title": "Practice: captures are compulsory",
		"body": "A jump anywhere rules out quiet moves. Keep jumping with the same checker until its chain ends."},
	{"time": 17.0, "title": "Practice: reach the far row to crown",
		"body": "Crowning ends that turn. The stacked king can then step or jump in either diagonal direction."},
	{"time": 23.0, "title": "Practice: lose your last checker to win",
		"body": "Red offers its final checker; Ivory must take it. Having no legal move on your turn also wins."},
]

var _done: Dictionary[String, bool] = {}


## Unsupported variants must fail rather than silently record the wrong mode.
func configure(variant: String) -> bool:
	_done.clear()
	return variant == "solo"


## Captions identify the practice cuts instead of presenting them as a full match.
func steps() -> Array[Dictionary]:
	return STEPS


## Leave the final giveaway result visible before the recorder fades out.
func duration() -> float:
	return 29.0


## The opening is always Red against a seeded, visible CPU reply.
func settings_overrides() -> Dictionary:
	return {
		Options.PLAYER_SIDE_KEY: State.RED,
		Options.CPU_DIFFICULTY_KEY: Options.CPU_THOUGHTFUL,
		Options.SHOW_HINTS_KEY: true,
		Options.PIECE_LABELS_KEY: true,
	}


## The normal solo setup is used before the labelled practice cuts.
func configure_session(session: Node) -> void:
	session.call("configure_single_player")


## Pin the CPU's seed without replacing the live gameplay scene.
func start(scene: Node) -> void:
	(scene.get("_rng") as RandomNumberGenerator).seed = 14
	scene.call("_reset_round_state")
	(scene.get("_board_input") as Control).grab_focus()


## Every demonstrated move enters through the same square-selection path as a click.
func update(scene: Node, time: float, delta: float) -> void:
	if not bool(scene.get("_round_active")):
		return
	var state := scene.get("_state") as State
	if _once("opening", time >= 1.3):
		_move(scene, "c3", "d4")
	if _once("cpu_reply", state.ply_count >= 2):
		_freeze_cpu(scene)
	if time >= 6.0 and time < 7.0:
		scene.call("_drag_camera", Vector2(260, -65) * delta)
		if _once("camera", true):
			keycap_requested.emit("RMB")
	if _once("zoom", time >= 7.5):
		scene.call("_zoom_camera", 1.0)
		keycap_requested.emit("Wheel")
	if _once("reset_view", time >= 9.0):
		scene.call("_reset_camera")
		keycap_requested.emit("Home")
	if _once("chain_position", time >= 11.0):
		_position(scene, {"c3": State.MAN, "c1": State.MAN,
			"d4": -State.MAN, "f6": -State.MAN, "h8": -State.KING},
			"Practice position: the same checker must make both jumps.")
	if _once("first_jump", time >= 12.0):
		_move(scene, "c3", "e5")
		_done["forced_chain"] = state.forced_from == _square("e5")
	if _once("second_jump", time >= 13.5):
		_move(scene, "e5", "g7")
		_done["chain_completed"] = int((scene.get("_longest_chain") as Array)[State.RED]) == 2
	if _once("crown_position", time >= 17.0):
		_position(scene, {"b6": State.MAN, "c7": -State.MAN, "e7": -State.MAN},
			"Practice position: crowning ends the turn, even with a backward jump nearby.")
	if _once("crown", time >= 18.0):
		_move(scene, "b6", "d8")
		_done["crowned"] = state.board[_square("d8")] == State.KING \
			and state.turn == State.IVORY
	if _once("ivory_reply", time >= 19.4):
		_move(scene, "e7", "f6")
	if _once("king_backwards", time >= 20.8):
		_move(scene, "d8", "e7")
	if _once("finish_position", time >= 23.0):
		_position(scene, {"c3": State.MAN, "e5": -State.MAN},
			"Practice position: Red offers the last checker to win.")
	if _once("offer", time >= 24.2):
		_move(scene, "c3", "d4")
	if _once("giveaway", time >= 25.6):
		_move(scene, "e5", "c3")


## A movie of an untouched board or an incomplete lesson is not a valid take.
func validate_finished(scene: Node) -> bool:
	for milestone: String in [
		"opening", "cpu_reply", "camera", "zoom", "reset_view", "forced_chain",
		"chain_completed", "crowned", "king_backwards", "giveaway",
	]:
		if not _done.get(milestone, false):
			push_error("Anti Checkers tutorial missed: " + milestone)
			return false
	var state := scene.get("_state") as State
	return state.finished and state.winner == State.RED and state.result_reason == "no_pieces"


func _once(key: String, ready: bool) -> bool:
	if not ready or _done.has(key):
		return false
	_done[key] = true
	return true


func _freeze_cpu(scene: Node) -> void:
	scene.set_process(false)
	(scene.get("_cpu") as RefCounted).call("cancel")
	scene.set("_cpu_scheduled", false)


func _position(scene: Node, pieces: Dictionary, note: String) -> void:
	_freeze_cpu(scene)
	scene.set("_cpu_enabled", false)
	scene.call("_cancel_selection")
	for property: String in ["_moves_made", "_captures_taken", "_promotions", "_longest_chain"]:
		scene.set(property, [0, 0] as Array[int])
	scene.set("_chain_jumps", 0)
	scene.set("_ledger", PackedStringArray())
	scene.set("_last_move_text", note)
	var board := PackedInt32Array()
	board.resize(64)
	for square_name: String in pieces:
		board[_square(square_name)] = int(pieces[square_name])
	var state := scene.get("_state") as State
	if not state.set_position(board):
		_fail(scene, "Invalid practice position: " + note)
		return
	scene.set("_legal", state.legal_moves())
	var view := scene.get("_view") as Node
	view.call("reset", state, scene.call("_side_colors"))
	scene.call("_sync_match_scores")
	scene.call("_present_position")
	scene.call("_update_scores")


func _move(scene: Node, from_name: String, to_name: String) -> void:
	var state := scene.get("_state") as State
	var source := _square(from_name)
	var target := _square(to_name)
	scene.call("_on_square_pressed", source)
	scene.call("_on_square_pressed", target)
	if int(state.last_move.get("from", -1)) != source \
		or int(state.last_move.get("to", -1)) != target:
		_fail(scene, "The live board rejected %s-%s." % [from_name, to_name])
		return
	keycap_requested.emit("%s-%s" % [from_name, to_name])


func _square(square_name: String) -> int:
	return square_name.unicode_at(0) - 97 + (square_name.substr(1).to_int() - 1) * 8


func _fail(scene: Node, message: String) -> void:
	push_error("Anti Checkers tutorial: " + message)
	scene.get_tree().quit(1)
