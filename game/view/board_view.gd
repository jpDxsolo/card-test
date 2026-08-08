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

var _graph: SlotGraph
var _ruleset: Ruleset
var _profile := BoardLayout.Profile.LANDSCAPE

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


func sync_to_state(state: GameState) -> void:
	if _graph == null:
		return

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
		var top := state.peek_waste(i)
		if top == Card.NONE:
			_wastes[i].show_empty_slot()
		else:
			_wastes[i].show_face(top)

	if state.foundation.is_empty():
		_foundation.show_empty_slot()
	else:
		_foundation.show_face(state.foundation[state.foundation.size() - 1])

	_apply_layout()


## Highlights one playable position, clearing any previous one. `zone` is a
## Move.Zone; pass a negative index for "nothing selected".
##
## Call after sync_to_state(), which resets every card's appearance.
func set_selection(zone: int, index: int) -> void:
	for node in _slots:
		node.set_selected(false)
	for node in _wastes:
		node.set_selected(false)
	if index < 0:
		return
	if zone == Move.Zone.TABLEAU:
		_slots[index].set_selected(true)
	elif zone == Move.Zone.WASTE:
		_wastes[index].set_selected(true)


func relayout() -> void:
	if _graph == null:
		return
	layout = LayoutResolver.compute(
		_graph, _ruleset, get_viewport_rect().size, CardAtlas.theme.card_size(), _profile
	)
	_profile = layout.profile
	_apply_layout()


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
