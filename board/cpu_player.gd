extends RefCounted

## Seeded losing-checkers search with an explicit minimax stack. A jump is one
## work unit's move, not necessarily a turn: the same side owns an entire chain.
## Only fully completed iterative-deepening results replace the legal fallback.

const State = preload("res://games/anti_checkers/board/checkers_state.gd")

const _WIN_SCORE := 100000
const _INFINITY := 1000000
const _PIECE_WEIGHT := 100
## Each call has at most 96 small stack steps, even with an oversized budget.
const _MAX_BATCH_WORK := 96
## Depth is completed turns; mandatory continuations never consume extra depth.
const _DEPTH_LIMITS: Array[int] = [0, 3, 5]
## Total visited nodes per turn. Each needs at most three stack steps, so search
## is bounded independently of frame rate, branching, or capture-chain length.
const _NODE_LIMITS: Array[int] = [0, 1400, 3200]

class SearchFrame:
	extends RefCounted

	var state: State
	var depth_left: int
	var alpha: int
	var beta: int
	var maximizing: bool
	var entered: bool = false
	var moves: Array[Dictionary] = []
	var next_index: int = 0
	var best_score: int
	var best_move: Dictionary = {}

	func _init(
		position: State, depth: int, lower: int, upper: int, root_side: int
	) -> void:
		state = position
		depth_left = depth
		alpha = lower
		beta = upper
		maximizing = position.turn == root_side
		best_score = -_INFINITY if maximizing else _INFINITY


var completed: bool = true
var chosen_move: Dictionary = {}

var _level: int
var _seed_value: int
var _root_side: int = State.RED
var _rng := RandomNumberGenerator.new()
var _snapshot: State
var _root_moves: Array[Dictionary] = []
var _stack: Array[SearchFrame] = []
var _node_limit: int = 0
var _nodes_searched: int = 0
var _work_done: int = 0
var _search_depth: int = 0
var _completed_depth: int = 0


func _init(difficulty: int = 1, seed_value: int = 1) -> void:
	_level = clampi(difficulty, 0, 2)
	_seed_value = seed_value


## Owns a snapshot immediately; identical seeds and states reproduce choices
## regardless of batching, previous searches, or subsequent live-board changes.
func begin_turn(state: State) -> void:
	cancel()
	if state == null:
		return
	_snapshot = state.copy_state()
	_root_side = _snapshot.turn
	_root_moves = _snapshot.legal_moves()
	if _root_moves.is_empty():
		_finish_search()
		return
	_rng.seed = _seed_value
	_shuffle_root_moves()
	chosen_move = _root_moves[0].duplicate(true)
	_node_limit = _NODE_LIMITS[_level]
	if _level == 0 or _root_moves.size() == 1:
		_finish_search()
		return
	completed = false
	_search_depth = 1
	_start_depth()


## A budget counts small stack operations, each visiting at most one node.
## Zero/negative budgets do nothing; callers read completed to know when to play.
func think(node_budget: int = 48) -> void:
	var work_left := clampi(node_budget, 0, _MAX_BATCH_WORK)
	while work_left > 0 and not completed and _nodes_searched < _node_limit:
		_step_search()
		_work_done += 1
		work_left -= 1
	if not completed and _nodes_searched >= _node_limit:
		_finish_search()


## Cancellation discards all snapshots and choices; later think() cannot resume.
func cancel() -> void:
	completed = true
	chosen_move = {}
	_snapshot = null
	_root_moves.clear()
	_stack.clear()
	_node_limit = 0
	_nodes_searched = 0
	_work_done = 0
	_search_depth = 0
	_completed_depth = 0


func _shuffle_root_moves() -> void:
	for index in range(_root_moves.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var move := _root_moves[index]
		_root_moves[index] = _root_moves[other]
		_root_moves[other] = move


func _start_depth() -> void:
	var frame := SearchFrame.new(
		_snapshot, _search_depth, -_INFINITY, _INFINITY, _root_side
	)
	frame.moves = _root_moves.duplicate(true)
	_stack.append(frame)


func _step_search() -> void:
	var frame: SearchFrame = _stack.back()
	if not frame.entered:
		frame.entered = true
		_nodes_searched += 1
		if frame.state.finished:
			_return_score(_terminal_score(frame))
			return
		if frame.depth_left <= 0 and frame.state.forced_from < 0:
			_return_score(_evaluate(frame.state))
			return
		if _stack.size() > 1:
			frame.moves = frame.state.legal_moves()
		return
	if frame.next_index >= frame.moves.size():
		_return_score(frame.best_score)
		return
	var move := frame.moves[frame.next_index]
	frame.next_index += 1
	var next_state := frame.state.copy_state()
	if not next_state.play_move(move):
		push_error("Anti Checkers CPU generated an invalid search move.")
		_finish_search()
		return
	var turn_cost := 1 if next_state.turn != frame.state.turn else 0
	_stack.append(SearchFrame.new(
		next_state, frame.depth_left - turn_cost,
		frame.alpha, frame.beta, _root_side
	))


func _return_score(score: int) -> void:
	var frame: SearchFrame = _stack.pop_back()
	if _stack.is_empty():
		_completed_depth = _search_depth
		if not frame.best_move.is_empty():
			chosen_move = frame.best_move.duplicate(true)
			_root_moves.erase(frame.best_move)
			_root_moves.push_front(frame.best_move)
		if (
			_search_depth >= _DEPTH_LIMITS[_level]
			or absi(score) >= _WIN_SCORE - _DEPTH_LIMITS[_level]
		):
			_finish_search()
		else:
			_search_depth += 1
			_start_depth()
		return
	var parent: SearchFrame = _stack.back()
	var improves := (
		score > parent.best_score if parent.maximizing else score < parent.best_score
	)
	if improves:
		parent.best_score = score
		parent.best_move = parent.moves[parent.next_index - 1]
	if parent.maximizing:
		parent.alpha = maxi(parent.alpha, score)
	else:
		parent.beta = mini(parent.beta, score)
	if parent.alpha >= parent.beta:
		parent.next_index = parent.moves.size()


func _terminal_score(frame: SearchFrame) -> int:
	if frame.state.winner < 0:
		return 0
	var distance := _search_depth - frame.depth_left
	var value := _WIN_SCORE - distance
	return value if frame.state.winner == _root_side else -value


func _evaluate(state: State) -> int:
	var own := state.piece_count(_root_side)
	var opponent := state.piece_count(1 - _root_side)
	var score := (opponent - own) * _PIECE_WEIGHT
	var moves := state.legal_moves()
	var burden := mini(moves.size(), 24)
	if not moves.is_empty() and int(moves[0]["capture"]) >= 0:
		burden += 24
	# Mobility delays a no-moves win; being forced to take helps the other side.
	score += -burden if state.turn == _root_side else burden
	return score


func _finish_search() -> void:
	completed = true
	_stack.clear()
	_root_moves.clear()
	_snapshot = null
