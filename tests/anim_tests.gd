extends Node2D

## M5 animation smoke tests. Open this scene and press F6.
##
## Unlike rules_tests.gd these need a scene tree, real tweens and real frames,
## so they live in their own scene rather than being folded into that runner.
##
## What they are actually for: the plan's §8 promise is that the view is a pure
## function of the state and animation only ever decorates it. That promise is
## easy to state and easy to break -- a tween that keeps writing to a card after
## a re-sync desyncs the board silently, and no rules test would ever see it.
## Every assertion here is a version of "after the dust settles, the board still
## matches the state".

const CLASSIC := "res://data/rulesets/classic_pyramid.tres"

## Card centres must land within this many pixels of their layout rect. Not
## zero: tween callbacks and the final snap can land a frame apart.
const TOLERANCE := 0.5

var _passed := 0
var _failed := 0
## Deliberately untyped: Godot treats underscore-prefixed members as private
## when they are reached through a typed reference, and these tests need to see
## the controller's internals to assert anything worth asserting.
var _game: Node


func _ready() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame

	await _test_deal_locks_then_releases_input()
	await _test_board_matches_layout_after_deal()
	await _test_skip_mid_deal_leaves_board_correct()
	await _test_match_frees_its_ghosts()
	await _test_draw_leaves_board_in_sync()
	await _test_invalid_shake_returns_the_card()
	await _test_selection_lift_does_not_move_the_hit_target()
	await _test_foundation_waits_for_the_cards_to_arrive()
	await _test_waste_waits_for_the_drawn_card()
	await _test_skip_releases_pile_holds()
	await _test_win_cascade_locks_and_cleans_up()

	print("\n%d passed, %d failed" % [_passed, _failed])


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


## The deal is one of only two things allowed to swallow input (PLAN.md §8).
func _test_deal_locks_then_releases_input() -> void:
	_game.new_game(12345)
	_check(_game._director.is_input_locked(), "deal: input locks as soon as the deal is queued")
	await _settle()
	_check(not _game._director.is_input_locked(), "deal: input unlocks once the deal finishes")


func _test_board_matches_layout_after_deal() -> void:
	_game.new_game(999)
	await _settle()
	_check(_drifted_slots() == 0, "deal: every card ends on its layout rect")
	_check(_game._board._slots[0].card_id == _game._state.tableau[0],
		"deal: cards land showing the face the state says they hold")


## The interesting case: abandoning the deal part-way animates real card nodes,
## not ghosts, so the cards are left mid-flight. Only a re-sync can rescue them.
func _test_skip_mid_deal_leaves_board_correct() -> void:
	_game.new_game(4242)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_drifted_slots() > 0, "skip: cards really are mid-flight before the skip")

	_game._skip_animation()
	await get_tree().process_frame
	_check(_drifted_slots() == 0, "skip: the board snaps back onto its layout")
	_check(not _game._director.is_input_locked(), "skip: the input lock is released")
	_check(_game._board._slots[0].card_id == _game._state.tableau[0],
		"skip: interrupted flips still end on the right face")


func _test_match_frees_its_ghosts() -> void:
	_game.new_game(777)
	_game._skip_animation()
	await get_tree().process_frame

	var move: Move = _first_move(Move.Type.MATCH_PAIR)
	if move == null:
		_check(true, "match: (no pair in this deal, skipped)")
		return

	var before: int = _game._state.foundation.size()
	_game._play(move)
	_check(_game._state.foundation.size() == before + 2,
		"match: the state commits immediately, without waiting for the tween")
	_check(_game._board._slots[move.a_index].visible == false or move.a_zone != Move.Zone.TABLEAU,
		"match: the board hides the card before the ghost has finished flying")

	await _settle()
	_check(_game._director.get_child_count() == 0, "match: every ghost is freed when it lands")
	_check(_drifted_slots() == 0, "match: the rest of the board never moved")


func _test_draw_leaves_board_in_sync() -> void:
	_game.new_game(31337)
	_game._skip_animation()
	await get_tree().process_frame

	var move: Move = _first_move(Move.Type.DRAW_STOCK)
	var before: int = _game._state.stock_remaining()
	_game._play(move)
	_check(_game._state.stock_remaining() == before - 1, "draw: the stock decrements at once")

	await _settle()
	_check(_game._director.get_child_count() == 0, "draw: the flying card is freed")
	_check(_game._board._wastes[0].card_id == _game._state.peek_waste(0),
		"draw: the waste shows what the state says is on top")


## The shake is the one animation that moves a real, still-live card, so it has
## to put it back exactly.
func _test_invalid_shake_returns_the_card() -> void:
	_game.new_game(2468)
	_game._skip_animation()
	await get_tree().process_frame

	var node: CardNode = _game._board._slots[27]
	var home := node.position
	var tween: Tween = _game._board.shake(Move.Zone.TABLEAU, 27)
	await get_tree().process_frame
	_check(node.position != home, "invalid: the card actually moves")
	await tween.finished
	_check(node.position.distance_to(home) < TOLERANCE, "invalid: the card returns to where it started")


## Hit testing is done against LayoutResolver rects, not against the node, so a
## lifted card must not become clickable somewhere it is not drawn -- and more
## importantly must stay clickable where it is.
func _test_selection_lift_does_not_move_the_hit_target() -> void:
	_game.new_game(1357)
	_game._skip_animation()
	await get_tree().process_frame

	var rect: Rect2 = _game._board.layout.slots[27]
	_game._board.set_selection(Move.Zone.TABLEAU, 27, 0.05)
	await get_tree().create_timer(0.1).timeout
	_check(_game._board.layout.slots[27] == rect, "select: lifting a card does not change its hit rect")
	_check(LayoutResolver.hit_test(_game._board.layout, rect.get_center(), _game._state.tableau)
		== Vector2i(BoardLayout.Target.TABLEAU, 27),
		"select: a lifted card is still hit where it is laid out")


## A destination pile must not show a card that is still visibly flying towards
## it -- otherwise the card is in two places at once.
func _test_foundation_waits_for_the_cards_to_arrive() -> void:
	_game.new_game(777)
	_game._skip_animation()
	await get_tree().process_frame

	var move: Move = _first_move(Move.Type.MATCH_PAIR)
	if move == null:
		_check(true, "foundation hold: (no pair in this deal, skipped)")
		return

	var before: int = _game._board._foundation.card_id
	_game._play(move)
	await get_tree().process_frame
	_check(_game._board._foundation.card_id == before,
		"foundation hold: the pile still shows its old top while the pair flies")

	await _settle()
	var top: int = _game._state.foundation[_game._state.foundation.size() - 1]
	_check(_game._board._foundation.card_id == top,
		"foundation hold: the pile shows the new top once the cards land")


func _test_waste_waits_for_the_drawn_card() -> void:
	_game.new_game(31337)
	_game._skip_animation()
	await get_tree().process_frame

	var before: int = _game._board._wastes[0].card_id
	_game._play(_first_move(Move.Type.DRAW_STOCK))
	await get_tree().process_frame
	_check(_game._board._wastes[0].card_id == before,
		"waste hold: the waste still shows its old top while the card flies")

	await _settle()
	_check(_game._board._wastes[0].card_id == _game._state.peek_waste(0),
		"waste hold: the waste shows the drawn card once it lands")


## A hold is a promise that a card will arrive. Skipping breaks that promise, so
## the holds have to be released or the pile would under-report forever.
func _test_skip_releases_pile_holds() -> void:
	_game.new_game(31337)
	_game._skip_animation()
	await get_tree().process_frame

	_game._play(_first_move(Move.Type.DRAW_STOCK))
	await get_tree().process_frame
	_game._skip_animation()
	await get_tree().process_frame

	_check(_game._board._wastes[0].card_id == _game._state.peek_waste(0),
		"skip: an abandoned flight still leaves the waste showing the state")
	_check(_game._board._held_wastes[0] == 0, "skip: the waste hold is released")
	_check(_game._board._held_foundation == 0, "skip: the foundation hold is released")


## The hardest path to reach by playing, and therefore the one most likely to
## rot unnoticed. The position is forced rather than played out: this asserts the
## cascade's bookkeeping, not that the game is winnable.
func _test_win_cascade_locks_and_cleans_up() -> void:
	_game.new_game(555)
	_game._skip_animation()
	await get_tree().process_frame

	var cleared := PackedInt32Array()
	for i in _game._state.tableau.size():
		if _game._state.tableau[i] != Card.NONE:
			cleared.append(_game._state.tableau[i])
		_game._state.tableau[i] = Card.NONE
	_game._state.foundation = cleared
	_game._state.stock_index = _game._state.stock.size()
	for i in _game._state.wastes.size():
		_game._state.wastes[i] = PackedInt32Array()

	_check(RulesEngine.is_won(_game._state, _game._ruleset), "win: the forced position really is a win")
	_game._refresh()
	_check(_game._director.is_input_locked(), "win: the cascade holds input while it plays")

	# Re-entering _show_outcome() must not queue a second cascade.
	_game._refresh()
	await _settle()
	_check(_game._director.get_child_count() == 0, "win: every cascade ghost is freed")
	_check(not _game._director.is_input_locked(), "win: input is released when the cascade ends")


## Cards whose node is not sitting on its layout rect. The single measure of
## "the view has caught up with the state".
func _drifted_slots() -> int:
	var drifted := 0
	for slot in _game._graph.slots:
		var node: CardNode = _game._board._slots[slot.id]
		if not node.visible:
			continue
		if node.position.distance_to(_game._board.layout.slots[slot.id].position) > TOLERANCE:
			drifted += 1
	return drifted


func _first_move(type: Move.Type) -> Move:
	for move in RulesEngine.get_legal_moves(_game._state, _game._graph, _game._ruleset):
		if move.type == type:
			return move
	return null


## Waits for the director's queue to drain. Every test that asserts a resting
## board has to go through here first.
func _settle() -> void:
	while _game._director.is_busy():
		await get_tree().process_frame
	await get_tree().process_frame
