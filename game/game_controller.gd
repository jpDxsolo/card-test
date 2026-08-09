class_name GameController
extends Node2D

## The only place the view and the engine are both visible.
##
## Clicks become intents, intents are looked up against get_legal_moves(), and
## anything found there is applied and re-rendered. Legality is never re-derived
## here -- if a move is not in the engine's list, it does not happen. That is
## what stops the controller and the rules drifting apart.

const CLASSIC := "res://data/rulesets/classic_pyramid.tres"
const TUNING := "res://data/tuning.tres"
const NO_SELECTION := Vector2i(-1, -1)      ## (Move.Zone, index)

## 0 deals a random game. Set a specific seed to replay one.
@export var deal_seed := 0

var _ruleset: Ruleset
var _tuning: Tuning
var _graph: SlotGraph
var _state: GameState
var _board: BoardView
var _director: AnimationDirector
var _hud: Hud
var _selected := NO_SELECTION
var _seed := 0

## Whether the end-of-game flourish has already played for this deal.
## _show_outcome() runs after every change, and the cascade must not restart
## each time the player clicks a won board.
var _outcome_played := false


func _ready() -> void:
	_ruleset = load(CLASSIC) as Ruleset
	_tuning = load(TUNING) as Tuning
	_graph = SlotGraph.new(_ruleset)

	# HUD first: the board needs its height to know how much room to leave.
	# Draw order is unaffected -- Hud is a CanvasLayer and sits above regardless.
	_hud = Hud.new()
	add_child(_hud)
	_hud.new_game_requested.connect(func() -> void: new_game(randi()))

	_board = BoardView.new()
	add_child(_board)                  # must be in the tree before setup(): it reads the viewport
	_board.top_inset = _hud.reserved_height()
	_board.tuning = _tuning
	_board.setup(_graph, _ruleset)

	# Added after the board and at the same origin: identical coordinate space,
	# and every ghost draws above the cards without any z_index bookkeeping.
	_director = AnimationDirector.new()
	_director.tuning = _tuning
	add_child(_director)

	new_game(deal_seed if deal_seed != 0 else randi())


func new_game(game_seed: int) -> void:
	_director.skip()
	_board.stop_deal()
	_board.clear_holds()
	_seed = game_seed
	_state = RulesEngine.deal(_ruleset, _graph, game_seed)
	_selected = NO_SELECTION
	_outcome_played = false

	# The one animation that owns the whole board, so it is the one the director
	# holds input for. Everything else stays playable while it plays.
	var deal := _refresh(true)
	if deal != null:
		_director.enqueue(func() -> Tween: return deal, true)


func _unhandled_input(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed
	var new_game_key: bool = event is InputEventKey and event.pressed and event.keycode == KEY_R

	# A soft lock, not a dead window: input during the deal or the win cascade
	# skips it rather than being swallowed. Impatience gets you to a playable
	# board, which is the only thing the player wanted by clicking.
	if _director.is_input_locked() and (click or new_game_key):
		if not new_game_key:
			_skip_animation()
			get_viewport().set_input_as_handled()
			return

	if click:
		_on_click(_board.to_local(get_global_mouse_position()))
		get_viewport().set_input_as_handled()
	elif new_game_key:
		new_game(randi())
		get_viewport().set_input_as_handled()


## Drops everything in flight and snaps the board to the state. Safe at any
## moment: the state has always already committed, so this can only ever bring
## the view forward to meet it (PLAN.md §8).
func _skip_animation() -> void:
	_director.skip()
	_board.stop_deal()
	_board.clear_holds()                           # those cards are never arriving now
	_refresh()


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
		# The pair was illegal: say so on the card the player just clicked
		# (PLAN.md §9). The state has not changed, so this is the one animation
		# that plays on a real card rather than a ghost.
		_board.shake(pos.x, pos.y)

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


## Applies a move, then hands the director what it needs to show it happening.
##
## The flight geometry is read *before* apply() -- afterwards the cards are gone
## from the state and their rects mean nothing. The animation is queued after
## the re-sync, so it is always decoration over a board that is already correct.
func _play(move: Move) -> void:
	if move == null:
		return

	var cards: Array[int] = []
	var rects: Array[Rect2] = []
	match move.type:
		Move.Type.DISCARD_SINGLE:
			cards.append(_card_at(move.a_zone, move.a_index))
			rects.append(_board.rect_for(move.a_zone, move.a_index))
		Move.Type.MATCH_PAIR:
			cards.append(_card_at(move.a_zone, move.a_index))
			rects.append(_board.rect_for(move.a_zone, move.a_index))
			cards.append(_card_at(move.b_zone, move.b_index))
			rects.append(_board.rect_for(move.b_zone, move.b_index))
		Move.Type.DRAW_STOCK:
			for i in _ruleset.draw_count:
				var index := _state.stock_index + i
				if index < _state.stock.size():
					cards.append(_state.stock[index])

	var stock := _board.layout.stock
	var waste := _board.layout.wastes[0]
	var foundation := _board.layout.foundation

	RulesEngine.apply(_state, move, _ruleset)
	_selected = NO_SELECTION                       # a draw changes what waste[0] means

	# Hold the destination pile *before* the re-sync. The state has the card in
	# its new pile already, so without this the pile would show it while the
	# ghost carrying it was still crossing the screen -- the card would appear
	# to be in two places at once.
	var landed := cards.size()
	if move.type == Move.Type.DRAW_STOCK:
		_board.hold_waste(0, landed)
	else:
		_board.hold_foundation(landed)
	_refresh()

	if move.type == Move.Type.DRAW_STOCK:
		for card in cards:
			_director.fly_stock_to_waste(card, stock, waste,
				func() -> void: _board.hold_waste(0, -1))
	else:
		_director.fly_to_foundation(cards, rects, foundation,
			func() -> void: _board.hold_foundation(-landed))


func _card_at(zone: Move.Zone, index: int) -> int:
	if zone == Move.Zone.WASTE:
		return _state.peek_waste(index)
	return _state.tableau[index]


func _is_playable(pos: Vector2i) -> bool:
	if pos.x == Move.Zone.TABLEAU:
		return RulesEngine.is_exposed(_state, _graph, pos.y)
	return _state.peek_waste(pos.y) != Card.NONE


## Everything the player sees is redrawn from the state on every change, so
## there is no incremental bookkeeping to fall out of step with the game.
func _refresh(animate := false) -> Tween:
	var deal := _board.sync_to_state(_state, animate)
	_board.set_selection(_selected.x, _selected.y, _tuning.select_time)
	_hud.set_stats(RulesEngine.score(_state), _state.stock_remaining(), _waste_total(), _seed)
	_show_outcome()
	return deal


## Checked after every change rather than only after a move: a deal, a draw and
## a match can each be the thing that ends the game.
func _show_outcome() -> void:
	if RulesEngine.is_won(_state, _ruleset):
		if not _outcome_played:
			_outcome_played = true
			_director.win_cascade(
				_state.foundation, _board.layout.foundation, _board.content_area()
			)
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
