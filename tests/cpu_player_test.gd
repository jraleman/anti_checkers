extends SceneTree

## Deterministic, node-free CPU regressions. Work-count assertions avoid timing
## assumptions; tactics include whole-turn lookahead through same-side jumps.

const State = preload("res://games/anti_checkers/board/checkers_state.gd")
const Cpu = preload("res://games/anti_checkers/board/cpu_player.gd")

var _failures := PackedStringArray()
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_legal_seeded_choices()
	_test_forced_moves_and_crowning()
	_test_winning_sacrifices()
	_test_same_side_chain_search()
	_test_incremental_bounds()
	_test_completed_depth_cutoff()
	_test_snapshots_cancel_and_restart()
	_test_terminal_inputs()
	_test_seeded_live_play()
	if _failures.is_empty():
		print("Anti Checkers CPU tests passed (%d checks)." % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_legal_seeded_choices() -> void:
	var red := State.new()
	var ivory := red.copy_state()
	_expect(ivory.play_move(_move("a3", "b4")), "The Ivory-turn fixture starts legally.")
	for state: State in [red, ivory]:
		var original := _snapshot(state)
		var legal := state.legal_moves()
		for level in range(3):
			for seed_value: int in [1, 17]:
				var first := Cpu.new(level, seed_value)
				first.begin_turn(state)
				_expect(legal.has(first.chosen_move),
					"Even unfinished search exposes a detached canonical legal fallback.")
				_drain(first, 7)
				var expected := first.chosen_move.duplicate(true)
				var second := Cpu.new(level, seed_value)
				second.begin_turn(state)
				_drain(second, 48)
				_expect(legal.has(expected) and expected.size() == 4,
					"Every difficulty chooses a canonical legal move for either side.")
				_expect(second.chosen_move == expected,
					"Identical seeds and snapshots agree across different batch sizes.")
				_expect(_snapshot(state) == original, "Search never mutates the live model.")
				_expect(first._nodes_searched <= Cpu._NODE_LIMITS[level],
					"The chosen difficulty's total node budget is a hard limit.")
				if level > 0:
					_expect(first._completed_depth >= 2,
						"Thoughtful and Cunning complete actual opponent lookahead.")
				first.begin_turn(state)
				_drain(first, 13)
				_expect(first.chosen_move == expected,
					"Reusing a CPU reproduces the same seeded position choice.")
	var easy_choices: Dictionary[String, bool] = {}
	for seed_value in range(1, 17):
		var easy := Cpu.new(0, seed_value)
		easy.begin_turn(red)
		_expect(easy.completed and easy._nodes_searched == 0
			and red.legal_moves().has(easy.chosen_move),
			"Casual selects a legal seeded random move without search work.")
		easy_choices[str(easy.chosen_move)] = true
	_expect(easy_choices.size() > 1, "Casual uses its seed instead of always picking the first move.")


func _test_forced_moves_and_crowning() -> void:
	var forced := _position({
		"a3": State.MAN, "e3": State.MAN, "b4": -State.MAN, "h8": -State.KING,
	})
	var crown := _position({
		"b6": State.MAN, "c7": -State.MAN, "e7": -State.MAN,
	})
	var choices := _position({
		"a3": State.MAN, "e3": State.MAN,
		"b4": -State.MAN, "f4": -State.MAN, "h8": -State.KING,
	})
	var last_enemy := _position({"c3": State.MAN, "d4": -State.MAN})
	for level in range(3):
		var cpu := Cpu.new(level, 73)
		cpu.begin_turn(forced)
		_expect(cpu.completed and cpu._nodes_searched == 0
			and forced.legal_moves().has(cpu.chosen_move)
			and cpu.chosen_move["to"] == _square("c5"),
			"A sole compulsory capture is selected immediately at every difficulty.")
		cpu.begin_turn(crown)
		_expect(cpu.completed and crown.legal_moves().has(cpu.chosen_move)
			and cpu.chosen_move["promotion"] == State.KING,
			"The CPU retains automatic crowning metadata even on a sole capture.")
		var crowned := crown.copy_state()
		_expect(crowned.play_move(cpu.chosen_move) and crowned.turn == State.IVORY
			and crowned.forced_from == -1, "A CPU crown ends the turn rather than jumping backward.")
		cpu.begin_turn(choices)
		_drain(cpu)
		_expect(choices.legal_moves().has(cpu.chosen_move)
			and int(cpu.chosen_move["capture"]) >= 0,
			"The CPU cannot choose a quiet move over globally compulsory captures.")
		cpu.begin_turn(last_enemy)
		var loss := last_enemy.copy_state()
		_expect(last_enemy.legal_moves().has(cpu.chosen_move)
			and loss.play_move(cpu.chosen_move)
			and loss.finished and loss.winner == State.IVORY,
			"A forced losing capture is still a legal choice, never an empty successful result.")


func _test_winning_sacrifices() -> void:
	var red := _position({"c3": State.MAN, "e5": -State.MAN})
	var ivory := _position({"c5": -State.MAN, "e3": State.MAN}, State.IVORY)
	var blocked := _position({
		"a7": State.MAN, "c3": State.MAN, "b8": -State.KING, "e5": -State.MAN,
	})
	for level: int in [1, 2]:
		for state: State in [red, ivory, blocked]:
			var cpu := Cpu.new(level, 91)
			cpu.begin_turn(state)
			_drain(cpu)
			_expect(cpu.chosen_move.get("to", -1) == _square("d4"),
				"Lookahead offers the mobile man instead of preserving conventional material.")
			_expect(cpu._completed_depth >= 2,
				"A winning sacrifice must see the forced opponent capture.")
			var line := state.copy_state()
			_expect(line.play_move(cpu.chosen_move), "A selected sacrifice is directly executable.")
			var replies := line.legal_moves()
			_expect(replies.size() == 1 and line.captures_required(),
				"The winning sacrifice forces the opponent's single capture.")
			if replies.size() != 1:
				continue
			_expect(line.play_move(replies[0]), "The opponent's forced capture executes.")
			var expected_reason := "no_moves" if state == blocked else "no_pieces"
			_expect(line.finished and line.winner == state.turn
				and line.result_reason == expected_reason,
				"Actual empty/blocked-side wins outrank material and mobility heuristics.")


func _test_same_side_chain_search() -> void:
	var state := _position({
		"c3": State.MAN, "b4": -State.MAN, "d4": -State.MAN,
		"d6": -State.MAN, "f6": -State.MAN, "d8": -State.MAN,
	})
	_expect(state.legal_moves().size() == 2,
		"The tactical fixture offers both a shorter and a branching longer capture.")
	var original := _snapshot(state)
	for level: int in [1, 2]:
		var cpu := Cpu.new(level, 37)
		cpu.begin_turn(state)
		_drain(cpu)
		_expect(cpu.chosen_move.get("to", -1) == _square("e5"),
			"Search must see its own winning continuation, not treat its next jump as an enemy move.")
		var line := state.copy_state()
		_expect(line.play_move(cpu.chosen_move), "The first tactical jump executes.")
		_expect(line.turn == State.RED and line.forced_from == _square("e5")
			and line.ply_count == 0 and line.legal_moves().size() == 2,
			"The next branching search belongs to the same side and same completed turn.")
		var mid_chain := _snapshot(line)
		cpu.begin_turn(line)
		_drain(cpu, 1)
		_expect(cpu.chosen_move.get("from", -1) == _square("e5")
			and cpu.chosen_move.get("to", -1) == _square("c7"),
			"From a forced continuation, the CPU chooses the branch that sacrifices its last man.")
		_expect(_snapshot(line) == mid_chain, "Continuation search cannot alter its source lock/history.")
		_expect(line.play_move(cpu.chosen_move) and line.turn == State.IVORY
			and line.ply_count == 1, "The second jump finally completes Red's turn.")
		var replies := line.legal_moves()
		_expect(replies.size() == 1 and int(replies[0]["capture"]) == _square("c7"),
			"The completed chain forces Ivory to take the CPU's final piece.")
		if replies.size() == 1:
			_expect(line.play_move(replies[0]) and line.finished
				and line.winner == State.RED and line.result_reason == "no_pieces",
				"Two same-side jumps followed by an enemy jump are a Red win, not a sign inversion.")
	_expect(_snapshot(state) == original, "Multi-jump lookahead leaves the original board unchanged.")
	var locked := _position({
		"a3": State.MAN, "c3": State.MAN, "b4": -State.MAN,
		"d4": -State.MAN, "f6": -State.MAN, "h8": -State.KING,
	})
	_expect(locked.play_move(_move("c3", "e5")), "The single-continuation fixture starts legally.")
	for level in range(3):
		var cpu := Cpu.new(level, 7)
		cpu.begin_turn(locked)
		_expect(cpu.completed and locked.legal_moves().has(cpu.chosen_move)
			and cpu.chosen_move["from"] == _square("e5"),
			"A forced sole continuation cannot switch to another capturing piece.")


func _test_incremental_bounds() -> void:
	var state := State.new()
	var cpu := Cpu.new(2, 5)
	cpu.think()
	_expect(cpu.completed and cpu.chosen_move.is_empty() and cpu._work_done == 0,
		"Thinking while idle does no work.")
	cpu.begin_turn(state)
	_expect(not cpu.completed and cpu._nodes_searched == 0 and cpu._work_done == 0,
		"begin_turn schedules high-level work rather than searching synchronously.")
	var fallback := cpu.chosen_move.duplicate(true)
	cpu.think(0)
	cpu.think(-100)
	_expect(not cpu.completed and cpu._work_done == 0 and cpu._nodes_searched == 0
		and cpu.chosen_move == fallback, "Non-positive budgets cannot search or change the fallback.")
	var before_work := cpu._work_done
	var before_nodes := cpu._nodes_searched
	cpu.think(2147483647)
	_expect(cpu._work_done - before_work <= Cpu._MAX_BATCH_WORK
		and cpu._nodes_searched - before_nodes <= Cpu._MAX_BATCH_WORK,
		"Even oversized caller budgets yield after the fixed batch cap.")
	_expect(not cpu.completed, "One oversized batch must not drain Cunning's opening search.")
	var calls := 0
	while not cpu.completed and calls <= 3 * Cpu._NODE_LIMITS[2]:
		before_work = cpu._work_done
		before_nodes = cpu._nodes_searched
		cpu.think(1)
		_expect(cpu._work_done - before_work <= 1
			and cpu._nodes_searched - before_nodes <= 1,
			"One-step batches cannot hide recursive expansion or unbounded unwinding.")
		calls += 1
	_expect(cpu.completed and cpu._nodes_searched <= Cpu._NODE_LIMITS[2]
		and cpu._work_done <= 3 * Cpu._NODE_LIMITS[2],
		"The entire search completes within its fixed total node and bookkeeping bounds.")
	_expect(cpu._completed_depth >= 2 and state.legal_moves().has(cpu.chosen_move),
		"Bounded incremental work still completes adversarial lookahead and a legal choice.")
	_expect(cpu._stack.is_empty() and cpu._snapshot == null and cpu._root_moves.is_empty(),
		"Finished searches release their owned search tree.")
	before_work = cpu._work_done
	before_nodes = cpu._nodes_searched
	var chosen := cpu.chosen_move.duplicate(true)
	cpu.think(48)
	_expect(cpu._work_done == before_work and cpu._nodes_searched == before_nodes
		and cpu.chosen_move == chosen, "Finished searches are idempotent.")
	_expect(Cpu._DEPTH_LIMITS[2] > Cpu._DEPTH_LIMITS[1]
		and Cpu._NODE_LIMITS[2] > Cpu._NODE_LIMITS[1],
		"Cunning has greater depth and total work allowance than Thoughtful.")


func _test_completed_depth_cutoff() -> void:
	var state := State.new()
	var cpu := Cpu.new(2, 11)
	cpu.begin_turn(state)
	var calls := 0
	while cpu._completed_depth < 1 and not cpu.completed and calls < 200:
		cpu.think(1)
		calls += 1
	_expect(cpu._completed_depth == 1 and not cpu.completed,
		"Iterative deepening commits a complete shallow result before deeper work.")
	var committed := cpu.chosen_move.duplicate(true)
	cpu._node_limit = cpu._nodes_searched + 2
	_drain(cpu)
	_expect(cpu._completed_depth == 1 and cpu.chosen_move == committed,
		"A hard cutoff preserves the completed depth instead of a partly searched root.")
	_expect(cpu._nodes_searched <= cpu._node_limit, "The total limit cannot be overshot.")
	var tiny := Cpu.new(2, 11)
	tiny.begin_turn(state)
	var fallback := tiny.chosen_move.duplicate(true)
	tiny._node_limit = 1
	tiny.think(1)
	_expect(tiny.completed and tiny._completed_depth == 0 and tiny.chosen_move == fallback
		and state.legal_moves().has(tiny.chosen_move),
		"Even a cutoff before depth one immediately completes with the original legal fallback.")


func _test_snapshots_cancel_and_restart() -> void:
	var live := State.new()
	var reference := Cpu.new(1, 17)
	reference.begin_turn(live)
	_drain(reference)
	var expected := reference.chosen_move.duplicate(true)
	var cpu := Cpu.new(1, 17)
	cpu.begin_turn(live)
	_expect(live.play_move(_move("a3", "b4")), "The live board may advance after a snapshot.")
	var advanced := _snapshot(live)
	_drain(cpu)
	_expect(cpu.chosen_move == expected and _snapshot(live) == advanced,
		"A pending search uses its owned position and cannot restore or alter a changed live board.")
	cpu.begin_turn(live)
	cpu.think(1)
	_expect(not cpu.completed, "Cancellation starts with real pending work.")
	cpu.cancel()
	_expect(cpu.completed and cpu.chosen_move.is_empty()
		and cpu._stack.is_empty() and cpu._root_moves.is_empty() and cpu._snapshot == null,
		"Cancellation discards both pending work and the fallback choice.")
	cpu.think(2147483647)
	_expect(cpu.completed and cpu.chosen_move.is_empty() and cpu._work_done == 0
		and _snapshot(live) == advanced, "Cancelled work cannot resume or mutate the source.")
	var fresh := State.new()
	cpu.begin_turn(fresh)
	_drain(cpu)
	_expect(cpu.chosen_move == expected, "Restarting after cancellation restores deterministic search.")
	cpu.begin_turn(fresh)
	cpu.think(1)
	cpu.begin_turn(live)
	_drain(cpu)
	reference.begin_turn(live)
	_drain(reference, 13)
	_expect(cpu.chosen_move == reference.chosen_move
		and live.legal_moves().has(cpu.chosen_move),
		"begin_turn replaces unfinished work instead of leaking a move from the old side.")


func _test_terminal_inputs() -> void:
	var no_pieces := _position({"h8": -State.KING})
	var no_moves := _position({"a7": State.MAN, "b8": -State.KING})
	var draw := _position({"a1": State.KING, "h8": -State.KING}, State.RED, 80)
	var resigned := State.new()
	_expect(resigned.resign(State.IVORY), "The resignation fixture finishes normally.")
	for level in range(3):
		var cpu := Cpu.new(level, 19)
		for terminal: State in [no_pieces, no_moves, draw, resigned]:
			var before := _snapshot(terminal)
			cpu.begin_turn(State.new())
			cpu.begin_turn(terminal)
			cpu.think()
			_expect(cpu.completed and cpu.chosen_move.is_empty()
				and cpu._nodes_searched == 0 and cpu._snapshot == null
				and _snapshot(terminal) == before,
				"Terminal positions discard old work and never fabricate a move or alter the result.")
		cpu.begin_turn(null)
		_expect(cpu.completed and cpu.chosen_move.is_empty(),
			"A null position safely cancels without leaving an old choice.")


func _test_seeded_live_play() -> void:
	for level in range(3):
		var state := State.new()
		var cpu := Cpu.new(level, 300 + level)
		for jump in range(24):
			if state.finished:
				break
			var before := _snapshot(state)
			cpu.begin_turn(state)
			_drain(cpu, 11)
			_expect(_snapshot(state) == before, "Repeated seeded turns never modify the source.")
			_expect(state.legal_moves().has(cpu.chosen_move),
				"Every seeded live turn or continuation has a canonical CPU choice.")
			if not state.play_move(cpu.chosen_move):
				_expect(false, "Every seeded CPU choice must execute directly.")
				break


func _drain(cpu: Cpu, budget: int = 48) -> void:
	var calls := 0
	var bounded := true
	while not cpu.completed and calls <= 3 * Cpu._NODE_LIMITS[2] + 1:
		var before := cpu._work_done
		cpu.think(budget)
		bounded = bounded and cpu._work_done - before <= mini(budget, Cpu._MAX_BATCH_WORK)
		calls += 1
	_expect(cpu.completed, "Incremental CPU search must finish within the total work limit.")
	_expect(bounded and cpu._work_done <= 3 * Cpu._NODE_LIMITS[2],
		"Every batch and the complete search obey deterministic operation-count bounds.")


func _position(
	placements: Dictionary, next_turn: int = State.RED, clock: int = 0
) -> State:
	var pieces := PackedInt32Array()
	pieces.resize(64)
	for coordinate: String in placements:
		pieces[_square(coordinate)] = int(placements[coordinate])
	var state := State.new()
	_expect(state.set_position(pieces, next_turn, clock),
		"CPU fixture must be a valid position: %s" % placements)
	return state


func _square(coordinate: String) -> int:
	return coordinate.unicode_at(0) - 97 + 8 * (coordinate.unicode_at(1) - 49)


func _move(from_name: String, to_name: String) -> Dictionary:
	return {"from": _square(from_name), "to": _square(to_name)}


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
