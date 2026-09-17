extends SceneTree

## Pure English/American losing-checkers regressions. Fixtures and seeded games
## exercise completed turns, not just move geometry; no scenes or settings change.

const State = preload("res://games/anti_checkers/board/checkers_state.gd")

var _failures := PackedStringArray()
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_opening_and_helpers()
	_test_compulsory_capture_and_choice()
	_test_men_and_edges()
	_test_short_kings()
	_test_chain_boundaries_and_branches()
	_test_crowning_ends_turn()
	_test_losing_objective()
	_test_repetition()
	_test_quiet_clock()
	_test_resignation()
	_test_atomic_move_rejection()
	_test_position_validation()
	_test_copy_isolation_and_reset()
	_test_seeded_games()
	if _failures.is_empty():
		print("Anti Checkers rules tests passed (%d checks)." % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_opening_and_helpers() -> void:
	var state := State.new()
	_expect(state.board.size() == 64, "The opening has 64 squares.")
	_expect(state.turn == State.RED, "Red always moves first.")
	_expect(
		state.piece_count(State.RED) == State.INITIAL_PIECES
		and state.piece_count(State.IVORY) == 12,
		"Both sides open with twelve men."
	)
	for square in range(64):
		var expected := State.EMPTY
		if State.is_playable(square):
			if square < 24:
				expected = State.MAN
			elif square >= 40:
				expected = -State.MAN
		_expect(state.board[square] == expected,
			"Opening square %s has the correct signed man." % State.square_name(square))
		_expect(
			State.is_playable(square) == ((square % 8 + (square >> 3)) % 2 == 0),
			"Exactly the a1-colour diagonals are playable."
		)
	_expect(
		not state.finished and state.winner == -1 and state.result_reason.is_empty()
		and state.ply_count == 0 and state.halfmove_clock == 0
		and state.forced_from == -1 and state.last_move.is_empty(),
		"Opening counters, result, and continuation are fresh."
	)
	var moves := state.legal_moves()
	_expect(moves.size() == 7, "There are exactly seven opening moves.")
	for move: Dictionary in moves:
		_expect(_canonical(move), "Canonical moves contain exactly four integer fields.")
		_expect(move["capture"] == -1 and move["promotion"] == State.EMPTY,
			"Every opening move is a quiet man move.")
	_expect_targets(state, "a3", ["b4"], "The left edge has one opening advance.")
	_expect_targets(state, "c3", ["b4", "d4"], "Interior men have two advances.")
	_expect_targets(state, "g3", ["f4", "h4"], "The right opening man stays on board.")
	_expect(state.moves_from(_square("b6")).is_empty(), "Ivory cannot move on Red's turn.")
	_expect(state.moves_from(-1).is_empty() and state.moves_from(64).is_empty()
		and state.moves_from(_square("b1")).is_empty(), "Invalid/light sources have no moves.")
	_expect(not state.captures_required(), "The opening has no compulsory captures.")
	_expect(State.side_of(State.MAN) == State.RED
		and State.side_of(State.KING) == State.RED
		and State.side_of(-State.MAN) == State.IVORY
		and State.side_of(-State.KING) == State.IVORY
		and State.side_of(State.EMPTY) == -1, "Signed piece ownership is consistent.")
	_expect(state.piece_count(-1) == 0 and state.piece_count(2) == 0,
		"Invalid sides do not count empty squares or pieces.")
	_expect(State.square_name(0) == "a1" and State.square_name(63) == "h8"
		and State.square_name(-1).is_empty() and State.square_name(64).is_empty(),
		"Algebraic names use a1=0 and reject off-board squares.")
	_expect(not State.is_playable(-1) and not State.is_playable(64),
		"Off-board squares cannot be playable.")
	var names: Array[String] = ["Empty", "Man", "King"]
	for kind in range(3):
		_expect(State.piece_name(kind) == names[kind]
			and State.piece_name(-kind) == names[kind], "Piece names accept either sign.")
	_expect(State.piece_name(3).is_empty(), "Unknown piece kinds have no name.")
	moves[0]["from"] = -1
	moves[0]["capture"] = 63
	moves.clear()
	var from_moves := state.moves_from(_square("c3"))
	from_moves[0]["promotion"] = State.KING
	_expect(state.legal_moves().size() == 7
		and state.moves_from(_square("c3"))[0]["promotion"] == State.EMPTY,
		"Mutating returned moves never changes future canonical moves.")
	_play(state, "a3", "b4")
	_expect(state.turn == State.IVORY and state.ply_count == 1
		and state.halfmove_clock == 0 and state.last_move["turn_finished"],
		"A quiet opening advance completes exactly one turn.")
	_expect(state.legal_moves().size() == 7, "Ivory also has seven opening replies.")


func _test_compulsory_capture_and_choice() -> void:
	var state := _position({
		"a3": State.MAN, "e3": State.MAN, "c1": State.MAN,
		"b4": -State.MAN, "f4": -State.MAN, "h8": -State.KING,
	})
	_expect(state.captures_required() and state.legal_moves().size() == 2,
		"A capture anywhere suppresses every quiet move, not other capturing pieces.")
	_expect_targets(state, "a3", ["c5"], "The left capture remains available.")
	_expect_targets(state, "e3", ["g5"], "A different piece may be chosen to capture.")
	_expect_targets(state, "c1", [], "A quiet piece cannot evade a global capture.")
	var before := _snapshot(state)
	_expect(not state.play_move(_move("e3", "d4")) and _snapshot(state) == before,
		"Rejecting a quiet move during compulsory capture is atomic.")
	var request := _move("a3", "c5")
	request["capture"] = _square("c1")
	request["promotion"] = State.KING
	request["turn_finished"] = false
	_expect(state.play_move(request), "Forged metadata does not invalidate legal endpoints.")
	request["to"] = _square("h8")
	_expect(state.board[_square("b4")] == State.EMPTY
		and state.board[_square("c1")] == State.MAN
		and state.board[_square("c5")] == State.MAN
		and state.last_move["capture"] == _square("b4")
		and state.last_move["promotion"] == State.EMPTY
		and state.last_move["to"] == _square("c5")
		and state.last_move.size() == 5 and state.last_move["turn_finished"],
		"Only the canonical enemy disappears; the caller cannot crown or alias last_move.")
	var choice := _position({
		"c3": State.MAN, "b4": -State.MAN, "d4": -State.MAN,
		"f6": -State.MAN, "h8": -State.KING,
	})
	_expect_targets(choice, "c3", ["a5", "e5"],
		"Both first jumps are legal even when one leads to a longer capture chain.")
	var shorter := choice.copy_state()
	_play(shorter, "c3", "a5")
	_expect(shorter.turn == State.IVORY and shorter.ply_count == 1,
		"English checkers permits choosing the shorter complete capture.")
	_play(choice, "c3", "e5")
	_expect_targets(choice, "e5", ["g7"], "The longer chosen chain must be finished.")


func _test_men_and_edges() -> void:
	_expect_targets(_position({"c3": State.MAN, "h8": -State.KING}),
		"c3", ["b4", "d4"], "Red men only step toward higher ranks.")
	_expect_targets(_position({"c5": -State.MAN, "a1": State.KING}, State.IVORY),
		"c5", ["b4", "d4"], "Ivory men only step toward lower ranks.")
	var red_back := _position({
		"c5": State.MAN, "b4": -State.MAN, "d4": -State.MAN,
	})
	_expect_targets(red_back, "c5", ["b6", "d6"], "Red men cannot jump backward.")
	_expect(not red_back.captures_required(), "Backward enemies do not force a man to jump.")
	var ivory_back := _position({
		"c3": -State.MAN, "b4": State.MAN, "d4": State.MAN,
	}, State.IVORY)
	_expect_targets(ivory_back, "c3", ["b2", "d2"], "Ivory men cannot jump backward.")
	_expect(not ivory_back.captures_required(), "Ivory's backward jumps are not compulsory.")
	_expect_targets(_position({
		"c3": State.MAN, "b4": -State.MAN, "d4": -State.MAN,
	}), "c3", ["a5", "e5"], "Red men may jump either forward diagonal.")
	_expect_targets(_position({
		"c5": -State.MAN, "b4": State.MAN, "d4": State.MAN,
	}, State.IVORY), "c5", ["a3", "e3"], "Ivory jumps toward decreasing ranks.")
	_expect_targets(_position({"h2": State.MAN, "a7": -State.MAN}),
		"h2", ["g3"], "Right-edge man moves never wrap files.")
	_expect_targets(_position({"a7": -State.MAN, "g1": State.MAN}, State.IVORY),
		"a7", ["b6"], "Left-edge Ivory moves never wrap files.")
	var cannot_reverse := _position({
		"c3": State.MAN, "d4": -State.MAN, "f4": -State.MAN,
	})
	_play(cannot_reverse, "c3", "e5")
	_expect(cannot_reverse.forced_from == -1 and cannot_reverse.turn == State.IVORY,
		"A man ends its turn when only a backward continuation would remain.")


func _test_short_kings() -> void:
	var king := _position({"d4": State.KING, "h8": -State.KING})
	_expect_targets(king, "d4", ["c3", "e3", "c5", "e5"],
		"Kings move exactly one diagonal in either direction.")
	_expect(not king.play_move(_move("d4", "a1"))
		and not king.play_move(_move("d4", "g7")),
		"Kings never fly along a clear diagonal.")
	_expect_targets(_position({"d4": -State.KING, "h8": State.KING}, State.IVORY),
		"d4", ["c3", "e3", "c5", "e5"], "Ivory kings have the same short geometry.")
	_expect_targets(_position({
		"d4": State.KING, "c3": -State.MAN, "e3": -State.MAN,
		"c5": -State.MAN, "e5": -State.MAN, "h8": -State.KING,
	}), "d4", ["b2", "f2", "b6", "f6"], "Kings jump adjacent enemies both ways.")
	var distant := _position({"d4": State.KING, "f6": -State.MAN})
	_expect(not distant.captures_required(), "A distant enemy cannot be jumped by a king.")
	_expect_targets(distant, "d4", ["c3", "e3", "c5", "e5"],
		"Distant enemies do not suppress short quiet moves.")
	_expect_targets(_position({
		"d4": State.KING, "e5": -State.MAN, "f6": -State.MAN,
	}), "d4", ["c3", "e3", "c5"], "An occupied landing square prevents a jump.")
	_expect_targets(_position({
		"d4": State.KING, "c3": State.MAN, "h8": -State.KING,
	}), "d4", ["e3", "c5", "e5"], "Friendly pieces cannot be jumped.")
	_expect_targets(_position({"h4": State.KING, "a5": -State.MAN}),
		"h4", ["g3", "g5"], "King steps and jumps cannot wrap board edges.")
	var reverse := _position({
		"c3": State.KING, "d4": -State.MAN, "f4": -State.MAN, "h8": -State.KING,
	})
	_play(reverse, "c3", "e5")
	_expect_targets(reverse, "e5", ["g3"], "A king must reverse direction within a chain.")
	_play(reverse, "e5", "g3")
	_expect(reverse.turn == State.IVORY and reverse.ply_count == 1,
		"A forward/backward king chain still counts as only one turn.")


func _test_chain_boundaries_and_branches() -> void:
	var state := _branch_position(17)
	var history: Dictionary = state._repetitions.duplicate()
	_play(state, "c3", "e5")
	_expect(state.turn == State.RED and state.forced_from == _square("e5")
		and state.ply_count == 0 and state.halfmove_clock == 17 and not state.finished,
		"The first jump neither changes side nor counts a completed turn or draw ply.")
	_expect(state.last_move["capture"] == _square("d4")
		and not state.last_move["turn_finished"] and state.last_move.size() == 5,
		"last_move describes the individual jump and pending continuation.")
	_expect(state._repetitions == history, "Intermediate jumps never record repetitions.")
	_expect_targets(state, "e5", ["c7", "g7"], "Every continuation branch may be chosen.")
	_expect_targets(state, "a3", [], "A different capturing piece is locked out mid-chain.")
	var before := _snapshot(state)
	_expect(not state.play_move(_move("a3", "c5")) and _snapshot(state) == before,
		"Switching pieces during a chain is rejected atomically.")
	_expect(not state.play_move(_move("e5", "d6")) and _snapshot(state) == before,
		"A chain cannot be ended by a quiet move.")
	var alternative := state.copy_state()
	_play(state, "e5", "c7")
	_play(alternative, "e5", "g7")
	for completed_state: State in [state, alternative]:
		_expect(completed_state.turn == State.IVORY
			and completed_state.forced_from == -1 and completed_state.ply_count == 1
			and completed_state.halfmove_clock == 0
			and completed_state.last_move["turn_finished"],
			"The final jump commits one completed turn, resets progress, and unlocks pieces.")
		_expect(completed_state._repetitions.size() == 1,
			"An irreversible completed turn starts a fresh relevant repetition history.")
	_expect(state.board != alternative.board, "Independent chain branches keep different boards.")


func _test_crowning_ends_turn() -> void:
	var red := _position({
		"b6": State.MAN, "c7": -State.MAN, "e7": -State.MAN,
	}, State.RED, 79)
	var moves := red.legal_moves()
	_expect(moves.size() == 1 and moves[0]["promotion"] == State.KING,
		"A jump onto Red's far rank declares automatic crowning.")
	_play(red, "b6", "d8")
	_expect(red.board[_square("d8")] == State.KING
		and red.board[_square("e7")] == -State.MAN
		and red.turn == State.IVORY and red.forced_from == -1
		and red.ply_count == 1 and red.halfmove_clock == 0
		and red.last_move["turn_finished"],
		"Red's crown ends the turn even though the new king could jump backward.")
	_expect(not red.play_move(_move("d8", "f6")),
		"Crowning cannot be followed by a same-turn king jump.")
	var ivory := _position({
		"g3": -State.MAN, "f2": State.MAN, "d2": State.MAN,
	}, State.IVORY, 79)
	_play(ivory, "g3", "e1")
	_expect(ivory.board[_square("e1")] == -State.KING
		and ivory.board[_square("d2")] == State.MAN
		and ivory.turn == State.RED and ivory.forced_from == -1
		and ivory.ply_count == 1 and ivory.last_move["promotion"] == State.KING,
		"Ivory crowns with its own sign and also ends its capture chain.")
	var quiet_red := _position({"c7": State.MAN, "h8": -State.KING})
	for move: Dictionary in quiet_red.legal_moves():
		_expect(move["promotion"] == State.KING, "Every far-rank quiet move auto-crowns.")
	var forged := _move("c7", "b8")
	forged["promotion"] = State.EMPTY
	_expect(quiet_red.play_move(forged)
		and quiet_red.board[_square("b8")] == State.KING,
		"Caller metadata cannot suppress mandatory promotion.")
	var quiet_ivory := _position({"b2": -State.MAN, "h2": State.MAN}, State.IVORY)
	_play(quiet_ivory, "b2", "a1")
	_expect(quiet_ivory.board[_square("a1")] == -State.KING,
		"Ivory also crowns after a quiet move.")


func _test_losing_objective() -> void:
	var last_enemy := _position({"c3": State.MAN, "d4": -State.MAN})
	_play(last_enemy, "c3", "e5")
	_expect(last_enemy.finished and last_enemy.winner == State.IVORY
		and last_enemy.result_reason == "no_pieces" and last_enemy.turn == State.IVORY
		and last_enemy.ply_count == 1,
		"Capturing the last enemy immediately awards that enemy the win.")
	_expect(last_enemy.legal_moves().is_empty() and not last_enemy.captures_required(),
		"A finished game exposes no moves or capture prompt.")
	for side in range(2):
		var only_enemy := {"h8": -State.KING} if side == State.RED else {"a1": State.KING}
		var empty_side := _position(only_enemy, side)
		_expect(empty_side.finished and empty_side.winner == side
			and empty_side.result_reason == "no_pieces",
			"A fixture with no pieces on the side to move resolves immediately.")
	var off_turn := _position({"a3": State.MAN})
	_expect(not off_turn.finished, "An empty side wins when its turn begins, not off turn.")
	_play(off_turn, "a3", "b4")
	_expect(off_turn.finished and off_turn.winner == State.IVORY,
		"Advancing the turn resolves the other side's empty army.")
	var red_blocked := _position({"a7": State.MAN, "b8": -State.KING})
	_expect(red_blocked.finished and red_blocked.winner == State.RED
		and red_blocked.result_reason == "no_moves",
		"A blocked Red man wins rather than loses or draws.")
	var ivory_blocked := _position({"h2": -State.MAN, "g1": State.KING}, State.IVORY)
	_expect(ivory_blocked.finished and ivory_blocked.winner == State.IVORY
		and ivory_blocked.result_reason == "no_moves",
		"A blocked Ivory man wins by the same rule.")
	var boundary := _position({
		"a3": -State.MAN, "b2": State.KING, "c1": State.MAN, "h8": State.KING,
	}, State.RED, 79)
	_play(boundary, "h8", "g7")
	_expect(boundary.finished and boundary.winner == State.IVORY
		and boundary.result_reason == "no_moves" and boundary.halfmove_clock == 80,
		"A blocked opponent wins on the completed move, before the 80-ply draw.")
	var no_pieces_draw := _position({"h8": -State.KING}, State.RED, State.DRAW_PLIES)
	_expect(no_pieces_draw.result_reason == "no_pieces" and no_pieces_draw.winner == State.RED,
		"A no-pieces win also takes precedence when installing a draw-threshold fixture.")


func _test_repetition() -> void:
	var state := _position({"a1": State.KING, "h8": -State.KING})
	_king_cycle(state)
	_expect(not state.finished and state.ply_count == 4,
		"The second completed occurrence is not a draw.")
	var copied := state.copy_state()
	_king_cycle(copied)
	_expect(copied.finished and copied.winner == -1
		and copied.result_reason == "repetition" and copied.ply_count == 8
		and copied.halfmove_clock == 8 and copied.forced_from == -1,
		"The third occurrence draws immediately at a completed-turn boundary.")
	_expect(not state.finished and state.ply_count == 4,
		"A copied game owns its repetition counts.")
	_king_cycle(state)
	_expect(state.finished and state.result_reason == "repetition",
		"Copying preserved, rather than reset, the original relevant history.")
	var red := _position({"a1": State.KING, "h8": -State.KING})
	var ivory := _position({"a1": State.KING, "h8": -State.KING}, State.IVORY)
	var man := _position({"a1": State.MAN, "h8": -State.KING})
	var clock := _position({"a1": State.KING, "h8": -State.KING}, State.RED, 21)
	_expect(red._position_key() != ivory._position_key(),
		"Identical boards with different sides to move are different positions.")
	_expect(red._position_key() != man._position_key(),
		"A king and a man on the same square are not a repetition.")
	_expect(red._position_key() == clock._position_key(),
		"The quiet clock is not part of repetition identity.")


func _test_quiet_clock() -> void:
	var state := _position({"a1": State.KING, "h8": -State.KING}, State.RED, 78)
	_play(state, "a1", "b2")
	_expect(state.halfmove_clock == 79 and not state.finished,
		"Seventy-nine completed quiet king plies are still playable.")
	_play(state, "h8", "g7")
	_expect(state.halfmove_clock == State.DRAW_PLIES and state.finished
		and state.winner == -1 and state.result_reason == "forty_moves"
		and state.ply_count == 2, "The 80th quiet king ply draws without another input.")
	var threshold := _position({"a1": State.KING, "h8": -State.KING},
		State.IVORY, State.DRAW_PLIES)
	_expect(threshold.finished and threshold.result_reason == "forty_moves",
		"Installing an already-reached quiet threshold evaluates the draw.")
	var man := _position({"a3": State.MAN, "h8": -State.KING}, State.RED, 79)
	_play(man, "a3", "b4")
	_expect(man.halfmove_clock == 0 and not man.finished,
		"A quiet man move resets the no-progress clock.")
	var crown := _position({"c7": State.MAN, "h8": -State.KING}, State.RED, 79)
	_play(crown, "c7", "b8")
	_expect(crown.halfmove_clock == 0 and not crown.finished,
		"A newly crowned piece was a man move, not a quiet king ply.")
	var capture := _position({
		"c3": State.KING, "d4": -State.MAN, "h8": -State.KING,
	}, State.RED, 79)
	_play(capture, "c3", "e5")
	_expect(capture.halfmove_clock == 0 and not capture.finished,
		"A king capture also resets the no-progress clock.")
	var chain := _position({
		"c3": State.KING, "d4": -State.MAN, "f4": -State.MAN, "h8": -State.KING,
	}, State.RED, 79)
	_play(chain, "c3", "e5")
	_expect(chain.halfmove_clock == 79 and chain.ply_count == 0 and not chain.finished,
		"An unfinished king chain neither increments nor resolves the completed-turn clock.")
	_play(chain, "e5", "g3")
	_expect(chain.halfmove_clock == 0 and chain.ply_count == 1 and not chain.finished,
		"Completing a king chain resets, rather than increments, the clock.")


func _test_resignation() -> void:
	for side in range(2):
		var state := State.new()
		var before_board := state.board.duplicate()
		_expect(state.resign(side), "Either side can resign on Red's turn.")
		_expect(state.finished and state.winner == 1 - side
			and state.result_reason == "resignation" and state.board == before_board
			and state.turn == State.RED and state.ply_count == 0
			and state.last_move.is_empty(), "Resignation awards the other side without a move.")
		var before := _snapshot(state)
		_expect(not state.resign(1 - side) and not state.play_move(_move("a3", "b4"))
			and _snapshot(state) == before, "A finished result cannot be reversed.")
	var invalid := State.new()
	var unchanged := _snapshot(invalid)
	_expect(not invalid.resign(-1) and not invalid.resign(2)
		and _snapshot(invalid) == unchanged, "Invalid resignation sides are rejected atomically.")
	var chain := _branch_position()
	_play(chain, "c3", "e5")
	var board_before := chain.board.duplicate()
	var last_before := chain.last_move.duplicate(true)
	_expect(chain.resign(State.IVORY) and chain.winner == State.RED
		and chain.forced_from == -1 and chain.ply_count == 0
		and chain.board == board_before and chain.last_move == last_before
		and chain.legal_moves().is_empty(),
		"Off-turn resignation can end a chain without inventing a completed move.")


func _test_atomic_move_rejection() -> void:
	var state := State.new()
	var before := _snapshot(state)
	var malformed: Array[Dictionary] = [
		{}, {"from": 16}, {"to": 25}, {"from": null, "to": 25},
		{"from": 16.0, "to": 25}, {"from": 16, "to": 25.0},
		{"from": true, "to": 25}, {"from": 16, "to": false},
		{"from": "16", "to": 25}, {"from": 16, "to": "25"},
		{"from": [16], "to": 25}, {"from": 16, "to": {}},
		{"from": -1, "to": 25}, {"from": 16, "to": 64},
		{"from": 64, "to": 25}, {"from": 16, "to": -1},
		_move("a3", "a3"), _move("a3", "c5"), _move("a3", "b3"),
		_move("a3", "c3"), _move("b6", "a5"), _move("b1", "c2"),
	]
	for request: Dictionary in malformed:
		_expect(not state.play_move(request), "Malformed or illegal endpoints must fail: %s" % request)
		_expect(_snapshot(state) == before, "Rejected requests preserve all state and history.")
	var request := _move("a3", "b4")
	request["capture"] = {"invented": true}
	request["promotion"] = "king"
	request["unrelated"] = [1, 2, 3]
	_expect(state.play_move(request), "Only endpoint types matter; supplied metadata is ignored.")
	_expect(state.last_move["capture"] == -1
		and state.last_move["promotion"] == State.EMPTY and state.last_move.size() == 5,
		"Unknown fields cannot enter canonical last_move metadata.")
	var stale := request.duplicate(true)
	var after := _snapshot(state)
	_expect(not state.play_move(stale) and _snapshot(state) == after,
		"A request from a previous position is rejected atomically.")
	request["from"] = -1
	_expect(state.last_move["from"] == _square("a3"), "Committed metadata has no caller alias.")


func _test_position_validation() -> void:
	var state := _branch_position(19)
	_play(state, "c3", "e5")
	var before := _snapshot(state)
	var invalid_boards: Array[PackedInt32Array] = []
	var short_board := PackedInt32Array()
	short_board.resize(63)
	invalid_boards.append(short_board)
	var long_board := PackedInt32Array()
	long_board.resize(65)
	invalid_boards.append(long_board)
	invalid_boards.append(_pieces({}))
	invalid_boards.append(_pieces({"a1": 3, "h8": -State.KING}))
	invalid_boards.append(_pieces({"a1": -3, "h8": State.KING}))
	invalid_boards.append(_pieces({"b1": State.MAN, "h8": -State.KING}))
	invalid_boards.append(_pieces({"b8": State.MAN, "h8": -State.KING}))
	invalid_boards.append(_pieces({"a1": -State.MAN, "h8": State.KING}))
	for pieces: PackedInt32Array in invalid_boards:
		_expect(not state.set_position(pieces) and _snapshot(state) == before,
			"Bad size, parity, kind, promotion rank, or all-empty fixtures reject atomically.")
	var valid := _pieces({"a1": State.MAN, "h8": -State.MAN})
	for side: int in [-1, 2]:
		_expect(not state.set_position(valid, side) and _snapshot(state) == before,
			"Invalid next-turn sides preserve a pending chain.")
	_expect(not state.set_position(valid, State.RED, -1) and _snapshot(state) == before,
		"A negative no-progress clock is invalid.")
	_expect(state.set_position(valid), "Men on their own starting back ranks are valid.")
	_expect(not state.finished and state.turn == State.RED and state.forced_from == -1
		and state.ply_count == 0 and state.halfmove_clock == 0
		and state.last_move.is_empty() and state._repetitions.size() == 1,
		"A new position clears a previous capture lock, metadata, and history.")
	valid[_square("a1")] = State.KING
	_expect(state.board[_square("a1")] == State.MAN, "Fixtures do not retain an input-board alias.")
	_expect(state.resign(State.RED), "The reset-result fixture starts from a finished state.")
	_expect(state.set_position(_pieces({"c3": State.KING, "h8": -State.KING}),
		State.IVORY, 12), "set_position may replace a finished game.")
	_expect(not state.finished and state.winner == -1 and state.result_reason.is_empty()
		and state.turn == State.IVORY and state.halfmove_clock == 12,
		"Installing a live position clears the old winner and reason.")


func _test_copy_isolation_and_reset() -> void:
	var state := _branch_position(23)
	_play(state, "c3", "e5")
	var original := _snapshot(state)
	var copied := state.copy_state()
	_expect(_snapshot(copied) == original, "Copies preserve every public field and relevant history.")
	copied.board[_square("a3")] = State.KING
	copied.last_move["capture"] = -1
	var key: String = copied._repetitions.keys()[0]
	copied._repetitions[key] = 99
	_expect(_snapshot(state) == original,
		"Boards, move dictionaries, and repetition dictionaries are independently owned.")
	copied = state.copy_state()
	_play(copied, "e5", "c7")
	_expect(_snapshot(state) == original, "Playing a copied continuation does not advance its source.")
	_expect(copied.resign(State.RED), "A completed copied turn may be resigned.")
	var terminal_copy := copied.copy_state()
	_expect(_snapshot(terminal_copy) == _snapshot(copied),
		"Copies preserve terminal results as well as live turns.")
	state.reset()
	_expect(_snapshot(state) == _snapshot(State.new()), "reset completely restores the opening.")
	copied.reset()
	_expect(terminal_copy.finished, "Resetting a source cannot change an existing terminal copy.")


func _test_seeded_games() -> void:
	for seed_value: int in [1, 7, 29, 101, 300, 907]:
		var state := State.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for step in range(512):
			if state.finished:
				break
			var legal := state.legal_moves()
			_expect(not legal.is_empty(), "Every live seeded position has a legal move.")
			if legal.is_empty():
				break
			var captures := state.captures_required()
			for move: Dictionary in legal:
				_expect(_canonical(move) and (int(move["capture"]) >= 0) == captures,
					"Seeded legal lists remain canonical and globally capture-filtered.")
			var chosen := legal[rng.randi_range(0, legal.size() - 1)]
			var previous_turn := state.turn
			var previous_ply := state.ply_count
			var previous_total := state.piece_count(State.RED) + state.piece_count(State.IVORY)
			var previous_board := state.board.duplicate()
			var copied := state.copy_state()
			_expect(copied.play_move(chosen) and state.board == previous_board,
				"Playing a seeded search copy leaves the live board untouched.")
			if not state.play_move(chosen):
				_expect(false, "A canonical seeded choice must always execute.")
				break
			_expect(_snapshot(copied) == _snapshot(state), "Copied and live transitions agree exactly.")
			_expect(_valid_board(state), "Seeded transitions preserve piece kinds, parity, and crowning.")
			var expected_total := previous_total - (1 if captures else 0)
			_expect(state.piece_count(State.RED) + state.piece_count(State.IVORY) == expected_total,
				"A committed jump removes exactly one piece; quiet moves remove none.")
			if state.forced_from >= 0:
				_expect(state.turn == previous_turn and state.ply_count == previous_ply
					and state.forced_from == int(chosen["to"])
					and not state.last_move["turn_finished"] and state.captures_required(),
					"Seeded continuation boundaries keep the same side and piece.")
			else:
				_expect(state.turn == 1 - previous_turn and state.ply_count == previous_ply + 1
					and state.last_move["turn_finished"], "Seeded completed turns flip exactly once.")
		_expect(state.finished, "A bounded seeded game reaches a win or automatic draw: %d" % seed_value)
		if state.finished and state.winner >= 0:
			_expect(state.winner == state.turn
				and (state.piece_count(state.winner) == 0 or state.result_reason == "no_moves"),
				"Seeded wins belong to the empty or blocked side whose turn just began.")


func _branch_position(clock: int = 0) -> State:
	return _position({
		"c3": State.MAN, "a3": State.MAN, "d4": -State.MAN,
		"d6": -State.MAN, "f6": -State.MAN, "b4": -State.MAN, "h8": -State.KING,
	}, State.RED, clock)


func _king_cycle(state: State) -> void:
	_play(state, "a1", "b2")
	_play(state, "h8", "g7")
	_play(state, "b2", "a1")
	_play(state, "g7", "h8")


func _position(
	placements: Dictionary, next_turn: int = State.RED, clock: int = 0
) -> State:
	var state := State.new()
	_expect(state.set_position(_pieces(placements), next_turn, clock),
		"Rule fixture must be a valid position: %s" % placements)
	return state


func _pieces(placements: Dictionary) -> PackedInt32Array:
	var pieces := PackedInt32Array()
	pieces.resize(64)
	for coordinate: String in placements:
		pieces[_square(coordinate)] = int(placements[coordinate])
	return pieces


func _square(coordinate: String) -> int:
	return coordinate.unicode_at(0) - 97 + 8 * (coordinate.unicode_at(1) - 49)


func _move(from_name: String, to_name: String) -> Dictionary:
	return {"from": _square(from_name), "to": _square(to_name)}


func _play(state: State, from_name: String, to_name: String) -> void:
	_expect(state.play_move(_move(from_name, to_name)),
		"Fixture move %s-%s must execute." % [from_name, to_name])


func _expect_targets(
	state: State, source: String, expected_names: Array[String], message: String
) -> void:
	var actual: Array[String] = []
	for move: Dictionary in state.moves_from(_square(source)):
		actual.append(State.square_name(int(move["to"])))
	actual.sort()
	var expected := expected_names.duplicate()
	expected.sort()
	_expect(actual == expected, "%s Got %s, expected %s." % [message, actual, expected])


func _canonical(move: Dictionary) -> bool:
	if move.size() != 4:
		return false
	for key: String in ["from", "to", "capture", "promotion"]:
		if typeof(move.get(key)) != TYPE_INT:
			return false
	return State.is_playable(int(move["from"])) and State.is_playable(int(move["to"])) \
		and int(move["promotion"]) in [State.EMPTY, State.KING] \
		and (int(move["capture"]) == -1 or State.is_playable(int(move["capture"])))


func _valid_board(state: State) -> bool:
	if state.board.size() != 64:
		return false
	for square in range(64):
		var piece := state.board[square]
		if piece == State.EMPTY:
			continue
		if not State.is_playable(square) or absi(piece) > State.KING:
			return false
		if (piece == State.MAN and square >= 56) or (piece == -State.MAN and square < 8):
			return false
	return true


func _snapshot(state: State) -> Dictionary:
	return {
		"board": state.board.duplicate(), "turn": state.turn, "winner": state.winner,
		"finished": state.finished, "reason": state.result_reason, "ply": state.ply_count,
		"clock": state.halfmove_clock, "forced": state.forced_from,
		"last": state.last_move.duplicate(true), "history": state._repetitions.duplicate(),
	}


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
