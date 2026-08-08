class_name GameController
extends Node2D

## The only place the view and the engine are both visible.
##
## Clicks become intents, intents are looked up against get_legal_moves(), and
## anything found there is applied and re-rendered. Legality is never re-derived
## here -- if a move is not in the engine's list, it does not happen. That is
## what stops the controller and the rules drifting apart.

const CLASSIC := "res://data/rulesets/classic_pyramid.tres"
const NO_SELECTION := Vector2i(-1, -1)      ## (Move.Zone, index)

## 0 deals a random game. Set a specific seed to replay one.
@export var deal_seed := 0

var _ruleset: Ruleset
var _graph: SlotGraph
var _state: GameState
var _board: BoardView
var _hud: Hud
var _selected := NO_SELECTION
var _seed := 0


func _ready() -> void:
	_ruleset = load(CLASSIC) as Ruleset
	_graph = SlotGraph.new(_ruleset)

	# HUD first: the board needs its height to know how much room to leave.
	# Draw order is unaffected -- Hud is a CanvasLayer and sits above regardless.
	_hud = Hud.new()
	add_child(_hud)
	_hud.new_game_requested.connect(func() -> void: new_game(randi()))

	_board = BoardView.new()
	add_child(_board)                  # must be in the tree before setup(): it reads the viewport
	_board.top_inset = _hud.reserved_height()
	_board.setup(_graph, _ruleset)

	new_game(deal_seed if deal_seed != 0 else randi())


func new_game(game_seed: int) -> void:
	_seed = game_seed
	_state = RulesEngine.deal(_ruleset, _graph, game_seed)
	_selected = NO_SELECTION
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		_on_click(_board.to_local(get_global_mouse_position()))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		new_game(randi())
		get_viewport().set_input_as_handled()


func _on_click(local_point: Vector2) -> void:
	var hit := LayoutResolver.hit_test(_board.layout, local_point, _state.tableau)
	match hit.x:
		BoardLayout.Target.STOCK:
			_play(_find(Move.Type.DRAW_STOCK, NO_SELECTION, NO_SELECTION))
		BoardLayout.Target.TABLEAU:
			_click_card(Vector2i(Move.Zone.TABLEAU, hit.y))
		BoardLayout.Target.WASTE:
			_click_card(Vector2i(Move.Zone.WASTE, hit.y))
		_:
			# Clicking the background clears the selection. Clicking a covered
			# card does nothing at all -- see _click_card.
			_selected = NO_SELECTION
			_refresh()


func _click_card(pos: Vector2i) -> void:
	if not _is_playable(pos):
		return                                     # covered cards ignore input entirely

	# A King goes to the foundation alone, so it resolves on a single click.
	var single := _find(Move.Type.DISCARD_SINGLE, pos, NO_SELECTION)
	if single != null:
		_play(single)
		return

	if _selected == pos:
		_selected = NO_SELECTION
		_refresh()
		return

	if _selected != NO_SELECTION:
		var pair := _find(Move.Type.MATCH_PAIR, _selected, pos)
		if pair != null:
			_play(pair)
			return

	# Nothing was selected, or the pair was illegal. Selecting the card just
	# clicked is friendlier than clearing and making the player start again.
	_selected = pos
	_refresh()


## Looks up a move in the engine's own list rather than constructing one and
## trusting it. If it is not here, it is not legal, and there is no second
## opinion to disagree with.
func _find(type: Move.Type, a: Vector2i, b: Vector2i) -> Move:
	for move in RulesEngine.get_legal_moves(_state, _graph, _ruleset):
		if move.type != type:
			continue
		match type:
			Move.Type.DRAW_STOCK:
				return move
			Move.Type.DISCARD_SINGLE:
				if Vector2i(move.a_zone, move.a_index) == a:
					return move
			Move.Type.MATCH_PAIR:
				var x := Vector2i(move.a_zone, move.a_index)
				var y := Vector2i(move.b_zone, move.b_index)
				if (x == a and y == b) or (x == b and y == a):
					return move
	return null


func _play(move: Move) -> void:
	if move == null:
		return
	RulesEngine.apply(_state, move, _ruleset)
	_selected = NO_SELECTION                       # a draw changes what waste[0] means
	_refresh()


func _is_playable(pos: Vector2i) -> bool:
	if pos.x == Move.Zone.TABLEAU:
		return RulesEngine.is_exposed(_state, _graph, pos.y)
	return _state.peek_waste(pos.y) != Card.NONE


## Everything the player sees is redrawn from the state on every change, so
## there is no incremental bookkeeping to fall out of step with the game.
func _refresh() -> void:
	_board.sync_to_state(_state)
	_board.set_selection(_selected.x, _selected.y)
	_hud.set_stats(RulesEngine.score(_state), _state.stock_remaining(), _waste_total(), _seed)
	_show_outcome()


## Checked after every change rather than only after a move: a deal, a draw and
## a match can each be the thing that ends the game.
func _show_outcome() -> void:
	if RulesEngine.is_won(_state, _ruleset):
		_hud.show_outcome("You win\nEvery card cleared")
	elif RulesEngine.is_stuck(_state, _graph, _ruleset):
		_hud.show_outcome("No moves left\n%d cards remaining" % RulesEngine.score(_state))
	else:
		_hud.hide_outcome()


func _waste_total() -> int:
	var total := 0
	for pile in _state.wastes:
		total += pile.size()
	return total
