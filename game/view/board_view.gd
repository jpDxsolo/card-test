class_name BoardView
extends Node2D

## Renders a GameState. Owns no rules: it is handed a state and makes the screen
## match it. Nothing here decides what is legal.
##
## The view is a pure function of the state -- sync_to_state() rebuilds the whole
## board from scratch every time, with no incremental bookkeeping to drift out of
## sync. That is what makes resume, skip-animation and desync recovery possible
## when animation arrives in M5 (PLAN.md §8).

## Last computed layout. M3 hit-tests clicks against this rather than using
## collision shapes, which would need rescaling on every resize (PLAN.md §9).
var layout: BoardLayout

## Pixels reserved along the top edge for the HUD. The board is laid out below
## it, so on-screen text never sits over a card.
var top_inset := 0.0

## Durations and curves. Set before setup(); only the deal reads it here.
var tuning: Tuning

var _graph: SlotGraph
var _ruleset: Ruleset
var _profile := BoardLayout.Profile.LANDSCAPE

var _area := Rect2()
var _deal: Tween

## The state as of the last sync, so a hold can re-render a pile without the
## caller having to hand the state back in.
var _last_state: GameState

## Cards already committed to a pile in the state but still in flight visually.
## Always returns to zero: every flight releases its hold on arrival, and
## clear_holds() covers the case where the flight is abandoned.
var _held_foundation := 0
var _held_wastes: PackedInt32Array
var _slots: Array[CardNode] = []
var _stock: CardNode
var _wastes: Array[CardNode] = []
var _foundation: CardNode


## Call after this node is in the tree: it reads the viewport size.
func setup(graph: SlotGraph, ruleset: Ruleset) -> void:
	_graph = graph
	_ruleset = ruleset
	_build()
	if not get_viewport().size_changed.is_connected(relayout):
		get_viewport().size_changed.connect(relayout)
	relayout()


## Rebuilds the whole board from the state (PLAN.md §8). This is the
## authoritative snap: it is what makes the view a pure function of the state,
## and it is the escape hatch for resume, skip-animation and desync recovery.
##
## `animate` plays the deal-in and returns its Tween; otherwise the return is
## null. Only the deal is animated from here, because only the deal changes the
## entire board at once -- every other animation is per-move and belongs to
## AnimationDirector, which draws it as ghosts *over* an already-correct board.
## The sync happens first either way, so an abandoned animation cannot desync.
func sync_to_state(state: GameState, animate := false) -> Tween:
	if _graph == null:
		return null
	_last_state = state

	for slot in _graph.slots:
		var node := _slots[slot.id]
		var card := state.tableau[slot.id]
		node.visible = card != Card.NONE
		if node.visible:
			node.show_face(card)
			node.set_dimmed(not RulesEngine.is_exposed(state, _graph, slot.id))

	if state.stock_remaining() > 0:
		_stock.show_back()
	else:
		_stock.show_empty_slot()

	for i in _wastes.size():
		_show_pile(_wastes[i], state.wastes[i], _held_wastes[i])

	_show_pile(_foundation, state.foundation, _held_foundation)

	_apply_layout()
	return _deal_tween() if animate else null


## Renders the top of a pile, ignoring the top `hold` cards.
##
## `hold` is how the view stays honest while a card is in flight. The state
## commits the moment a move is applied, but the card is still visibly crossing
## the screen -- without this the destination pile would show it before the
## animation delivering it had arrived, which reads as the card being in two
## places at once.
func _show_pile(node: CardNode, pile: PackedInt32Array, hold: int) -> void:
	var index := pile.size() - 1 - hold
	if index < 0:
		node.show_empty_slot()
	else:
		node.show_face(pile[index])


## Highlights one playable position, clearing any previous one. `zone` is a
## Move.Zone; pass a negative index for "nothing selected".
##
## Call after sync_to_state(), which resets every card's appearance.
func set_selection(zone: int, index: int, time := 0.0) -> void:
	for node in _slots:
		node.set_selected(false, time)
	for node in _wastes:
		node.set_selected(false, time)
	if index < 0:
		return
	if zone == Move.Zone.TABLEAU:
		_slots[index].set_selected(true, time)
	elif zone == Move.Zone.WASTE:
		_wastes[index].set_selected(true, time)


## Holds back the top `delta` cards of the foundation until their flight lands.
## Pass a negative delta to release. Re-renders immediately, so the caller does
## not need a full re-sync either side of a move.
func hold_foundation(delta: int) -> void:
	_held_foundation = maxi(_held_foundation + delta, 0)
	if _last_state != null:
		_show_pile(_foundation, _last_state.foundation, _held_foundation)
		_apply_layout()


func hold_waste(index: int, delta: int) -> void:
	if index < 0 or index >= _held_wastes.size():
		return
	_held_wastes[index] = maxi(_held_wastes[index] + delta, 0)
	if _last_state != null:
		_show_pile(_wastes[index], _last_state.wastes[index], _held_wastes[index])
		_apply_layout()


## Releases every hold at once. Called when animations are abandoned: the cards
## those holds were waiting on are never going to arrive, and the piles must
## show what the state actually says.
func clear_holds() -> void:
	_held_foundation = 0
	_held_wastes.fill(0)


## The region the board was last laid out into -- the viewport less the HUD
## strip. Animations that sweep across the board need somewhere to sweep to.
func content_area() -> Rect2:
	return _area


## Where a playable position currently sits, so the controller can hand the
## director a flight path without knowing how the board is laid out.
func rect_for(zone: int, index: int) -> Rect2:
	if zone == Move.Zone.WASTE:
		return layout.wastes[index]
	return layout.slots[index]


## Abandons a deal in flight, including the per-card flips it spawned. The
## caller must re-sync afterwards: the cards are left wherever the tween had got
## to, and only the state knows where they belong.
func stop_deal() -> void:
	if _deal != null and _deal.is_valid():
		_deal.kill()
	for node in _slots:
		node.cancel_flip()


## Shakes a card in place. Nothing moved in the state, so this is the one
## animation that plays on a real card rather than a ghost.
func shake(zone: int, index: int) -> Tween:
	var node := _wastes[index] if zone == Move.Zone.WASTE else _slots[index]
	return node.shake(layout.card_size.x * tuning.invalid_shake, tuning.invalid_time)


func relayout() -> void:
	if _graph == null:
		return
	var size := get_viewport_rect().size
	var area := Rect2(0.0, top_inset, size.x, maxf(size.y - top_inset, 0.0))
	_area = area
	layout = LayoutResolver.compute(
		_graph, _ruleset, area, CardAtlas.theme.card_size(), _profile
	)
	_profile = layout.profile
	_apply_layout()


## Every tableau card flies out of the stock to its slot, staggered, turning
## face up as it lands.
##
## The rects are read from `layout` inside the tween rather than captured when
## it is built, so a window resize mid-deal redirects the cards in flight
## instead of landing them where the board used to be.
func _deal_tween() -> Tween:
	stop_deal()
	var flip_time := tuning.deal_card_time * 0.5
	var tween := create_tween()
	_deal = tween
	tween.set_parallel(true)

	for slot in _graph.slots:
		var node := _slots[slot.id]
		if not node.visible:
			continue

		# Captured before show_back() clears it: this is the face to turn up on
		# arrival, and the node is the only thing that knows it right now.
		var face := node.card_id
		var id := slot.id
		var delay := id * tuning.deal_stagger
		node.show_back()
		node.place(layout.stock)

		tween.tween_method(
			func(t: float) -> void:
				var from := layout.stock
				var to := layout.slots[id]
				node.place(Rect2(
					from.position.lerp(to.position, t),
					from.size.lerp(to.size, t))),
			0.0, 1.0, tuning.deal_card_time
		).set_delay(delay).set_trans(tuning.flight_trans).set_ease(tuning.flight_ease)

		tween.tween_callback(func() -> void:
			node.flip_to(face, flip_time)
		).set_delay(delay + tuning.deal_card_time)

	# flip_to() runs its own nested tween, which this one cannot see. Without a
	# trailing interval the deal would report itself finished -- and release the
	# input lock -- while the last cards were still turning over.
	tween.tween_interval(
		(_graph.size() - 1) * tuning.deal_stagger + tuning.deal_card_time + flip_time
	)
	return tween


func _build() -> void:
	# remove_child before queue_free: freeing is deferred, so without the
	# removal a second setup() would briefly render two boards on top of
	# each other. Only matters once "new game" exists, which is why it is
	# cheaper to get right now than to debug later.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_slots.clear()
	_wastes.clear()

	# Piles first, so tableau cards draw above them if they ever overlap.
	_stock = _add_card()
	for i in _ruleset.waste_pile_count:
		_wastes.append(_add_card())
	_foundation = _add_card()

	_held_foundation = 0
	_held_wastes.resize(_wastes.size())
	_held_wastes.fill(0)

	# Slot ids run top row first, so adding in id order draws lower rows last --
	# on top. Which is exactly how a pyramid overlaps, for free.
	for slot in _graph.slots:
		_slots.append(_add_card())


func _add_card() -> CardNode:
	var node := CardNode.new()
	add_child(node)
	return node


func _apply_layout() -> void:
	if layout == null or layout.slots.is_empty():
		return
	for slot in _graph.slots:
		_slots[slot.id].place(layout.slots[slot.id])
	_stock.place(layout.stock)
	for i in _wastes.size():
		_wastes[i].place(layout.wastes[i])
	_foundation.place(layout.foundation)
