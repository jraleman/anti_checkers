extends RefCounted

## Node-free English/American losing checkers. Captures are compulsory, but
## neither the longest chain nor flying kings belong to this ruleset.
## Use set_position() rather than editing the board so turn history stays valid.

const CheckersState = preload("res://games/anti_checkers/board/checkers_state.gd")

const EMPTY := 0
const MAN := 1
const KING := 2
const RED := 0
const IVORY := 1
const INITIAL_PIECES := 12
const DRAW_PLIES := 80

const _DIAGONALS: Array[Vector2i] = [
	Vector2i(-1, 1), Vector2i(1, 1),
	Vector2i(-1, -1), Vector2i(1, -1),
]

var board := PackedInt32Array()
var turn: int = RED
var winner: int = -1
var finished: bool = false
var result_reason: String = ""
var ply_count: int = 0
var halfmove_clock: int = 0
var forced_from: int = -1
var last_move: Dictionary = {}

var _repetitions: Dictionary[String, int] = {}


func _init() -> void:
	reset()


## Red starts on the low three ranks; every reset discards the previous match.
func reset() -> void:
	board = PackedInt32Array()
	board.resize(64)
	for square in range(64):
		if not is_playable(square):
			continue
		var rank_index := square >> 3
		if rank_index < 3:
			board[square] = MAN
		elif rank_index > 4:
			board[square] = -MAN
	turn = RED
	winner = -1
	finished = false
	result_reason = ""
	ply_count = 0
	halfmove_clock = 0
	forced_from = -1
	last_move = {}
	_repetitions = {}
	_record_position()


## Returns detached, single-step moves, globally filtered for compulsory jumps.
## During a chain, only the piece that made the previous jump may move.
func legal_moves() -> Array[Dictionary]:
	if finished:
		return []
	return _generate_moves()


## Filtering the side's legal moves preserves captures owed by another piece.
func moves_from(square: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if not is_playable(square):
		return moves
	for move: Dictionary in legal_moves():
		if int(move["from"]) == square:
			moves.append(move)
	return moves


## A live side must jump if any of its legal moves is a capture.
func captures_required() -> bool:
	var moves := legal_moves()
	return not moves.is_empty() and int(moves[0]["capture"]) >= 0


## Only integer endpoints are trusted. Capture and automatic crowning metadata
## are recomputed, so malformed or stale requests cannot partially change a turn.
func play_move(move: Dictionary) -> bool:
	if finished:
		return false
	var from_value: Variant = move.get("from")
	var to_value: Variant = move.get("to")
	if typeof(from_value) != TYPE_INT or typeof(to_value) != TYPE_INT:
		return false
	for canonical: Dictionary in legal_moves():
		if canonical["from"] == from_value and canonical["to"] == to_value:
			_apply_move(canonical)
			return true
	return false


## Either side may concede, including off turn or during a capture chain.
func resign(side: int) -> bool:
	if finished or (side != RED and side != IVORY):
		return false
	_win(1 - side, "resignation")
	return true


## Kings still count as one piece: shedding every piece is the objective.
func piece_count(side: int) -> int:
	if side != RED and side != IVORY:
		return 0
	var count := 0
	for piece: int in board:
		if side_of(piece) == side:
			count += 1
	return count


## Search snapshots own their board, continuation, metadata, and draw history.
func copy_state() -> CheckersState:
	var copied := CheckersState.new()
	copied.board = board.duplicate()
	copied.turn = turn
	copied.winner = winner
	copied.finished = finished
	copied.result_reason = result_reason
	copied.ply_count = ply_count
	copied.halfmove_clock = halfmove_clock
	copied.forced_from = forced_from
	copied.last_move = last_move.duplicate(true)
	copied._repetitions = _repetitions.duplicate()
	return copied


## Installs an owned, completed-turn fixture atomically and resolves its result.
## A side may be empty, but not both; men cannot remain on their crowning rank.
func set_position(
	pieces: PackedInt32Array,
	next_turn: int = RED,
	reversible_plies: int = 0
) -> bool:
	if (
		pieces.size() != 64
		or (next_turn != RED and next_turn != IVORY)
		or reversible_plies < 0
	):
		return false
	var occupied := false
	for square in range(64):
		var piece := pieces[square]
		if piece == EMPTY:
			continue
		if piece < -KING or piece > KING or not is_playable(square):
			return false
		if (piece == MAN and square >= 56) or (piece == -MAN and square < 8):
			return false
		occupied = true
	if not occupied:
		return false
	board = pieces.duplicate()
	turn = next_turn
	winner = -1
	finished = false
	result_reason = ""
	ply_count = 0
	halfmove_clock = reversible_plies
	forced_from = -1
	last_move = {}
	_repetitions = {}
	_record_position()
	_resolve_result()
	return true


## Signed pieces identify their owner; an empty square has no side.
static func side_of(piece: int) -> int:
	if piece == EMPTY:
		return -1
	return RED if piece > 0 else IVORY


## Algebraic names keep the board's a1=0 orientation out of presentation code.
static func square_name(square: int) -> String:
	if square < 0 or square >= 64:
		return ""
	return "%s%d" % [String.chr(97 + square % 8), (square >> 3) + 1]


## Only the 32 dark squares, including a1, may contain pieces or destinations.
static func is_playable(square: int) -> bool:
	return square >= 0 and square < 64 and ((square % 8 + (square >> 3)) % 2 == 0)


## Accepts signed board pieces as well as unsigned piece kinds.
static func piece_name(kind: int) -> String:
	match absi(kind):
		EMPTY:
			return "Empty"
		MAN:
			return "Man"
		KING:
			return "King"
	return ""


func _generate_moves() -> Array[Dictionary]:
	if forced_from >= 0:
		return _jumps_from(forced_from)
	var quiet: Array[Dictionary] = []
	var captures: Array[Dictionary] = []
	for square in range(64):
		if side_of(board[square]) == turn:
			_piece_moves(square, quiet, captures)
	return captures if not captures.is_empty() else quiet


func _jumps_from(square: int) -> Array[Dictionary]:
	var quiet: Array[Dictionary] = []
	var captures: Array[Dictionary] = []
	_piece_moves(square, quiet, captures)
	return captures


func _piece_moves(
	square: int, quiet: Array[Dictionary], captures: Array[Dictionary]
) -> void:
	var piece := board[square]
	var side := side_of(piece)
	if side < 0:
		return
	var file_index := square % 8
	var rank_index := square >> 3
	var forward := 1 if side == RED else -1
	for direction: Vector2i in _DIAGONALS:
		if absi(piece) == MAN and direction.y != forward:
			continue
		var next_file := file_index + direction.x
		var next_rank := rank_index + direction.y
		if next_file < 0 or next_file > 7 or next_rank < 0 or next_rank > 7:
			continue
		var adjacent := next_file + 8 * next_rank
		if board[adjacent] == EMPTY:
			_append_move(quiet, square, adjacent, -1)
			continue
		if side_of(board[adjacent]) == side:
			continue
		var landing_file := next_file + direction.x
		var landing_rank := next_rank + direction.y
		if (
			landing_file < 0 or landing_file > 7
			or landing_rank < 0 or landing_rank > 7
		):
			continue
		var landing := landing_file + 8 * landing_rank
		if board[landing] == EMPTY:
			_append_move(captures, square, landing, adjacent)


func _append_move(
	moves: Array[Dictionary], from_square: int, to_square: int, capture: int
) -> void:
	var piece := board[from_square]
	var promotion := EMPTY
	if (piece == MAN and to_square >= 56) or (piece == -MAN and to_square < 8):
		promotion = KING
	moves.append({
		"from": from_square, "to": to_square,
		"capture": capture, "promotion": promotion,
	})


func _apply_move(move: Dictionary) -> void:
	var from_square: int = move["from"]
	var to_square: int = move["to"]
	var capture: int = move["capture"]
	var promotion: int = move["promotion"]
	var piece := board[from_square]
	board[from_square] = EMPTY
	if capture >= 0:
		board[capture] = EMPTY
	board[to_square] = piece
	if promotion == KING:
		board[to_square] = KING if turn == RED else -KING
	last_move = move.duplicate(true)
	if capture >= 0 and promotion == EMPTY and not _jumps_from(to_square).is_empty():
		forced_from = to_square
		last_move["turn_finished"] = false
		return
	forced_from = -1
	last_move["turn_finished"] = true
	turn = 1 - turn
	ply_count += 1
	if capture >= 0 or absi(piece) == MAN:
		halfmove_clock = 0
		# Neither lost pieces nor forward-only men can recreate an older position.
		_repetitions = {}
	else:
		halfmove_clock += 1
	_record_position()
	_resolve_result()


func _position_key() -> String:
	return str(turn, ":", board)


func _record_position() -> void:
	var key := _position_key()
	_repetitions[key] = int(_repetitions.get(key, 0)) + 1


func _resolve_result() -> void:
	if piece_count(turn) == 0:
		_win(turn, "no_pieces")
	elif _generate_moves().is_empty():
		_win(turn, "no_moves")
	elif int(_repetitions.get(_position_key(), 0)) >= 3:
		_draw("repetition")
	elif halfmove_clock >= DRAW_PLIES:
		_draw("forty_moves")


func _win(side: int, reason: String) -> void:
	finished = true
	winner = side
	result_reason = reason
	forced_from = -1


func _draw(reason: String) -> void:
	finished = true
	winner = -1
	result_reason = reason
	forced_from = -1
