class_name RulesEngine

## Stateless rules. Nothing is remembered between calls: `state` is what
## changes, `graph` is fixed topology, `ruleset` is the variant config.
##
## Nothing in this file touches a Node, a texture or a position. That is what
## keeps it testable headlessly and fast enough for the M7 solver.

static func deal(ruleset: Ruleset, graph: SlotGraph, deal_seed: int) -> GameState:
	var cards := Deck.shuffled(ruleset, deal_seed)
	var state := GameState.new()

	# Tableau size comes from the graph, not the ruleset. That is why Triangle,
	# a six-row pyramid and Giza all deal correctly without touching this.
	state.tableau = cards.slice(0, graph.size())
	state.stock = cards.slice(graph.size())
	state.stock_index = 0

	state.wastes = []
	for i in ruleset.waste_pile_count:
		state.wastes.append(PackedInt32Array())

	state.foundation = PackedInt32Array()
	state.cells = PackedInt32Array()
	state.cells.resize(ruleset.cell_count)
	state.cells.fill(Card.NONE)
	state.redeals_used = 0
	return state


## A slot is playable when it still holds a card and every slot covering it is
## empty. This one rule, applied over different graphs, is the entire variant
## system -- nothing here knows it is looking at a pyramid.
static func is_exposed(state: GameState, graph: SlotGraph, slot_id: int) -> bool:
	if state.tableau[slot_id] == Card.NONE:
		return false
	for coverer in graph.slots[slot_id].covered_by:
		if state.tableau[coverer] != Card.NONE:
			return false
	return true


## Cards still on the tableau. A perfect game ends at 0.
static func score(state: GameState) -> int:
	var remaining := 0
	for card in state.tableau:
		if card != Card.NONE:
			remaining += 1
	return remaining


## Every legal move in the current position.
##
## One source of truth: game-over detection, the hint system and the M7 solver
## all read this. Resist ever writing a faster special-cased second version --
## divergence between two implementations of "what can the player do" is where
## solitaire bugs live.
static func get_legal_moves(state: GameState, graph: SlotGraph, ruleset: Ruleset) -> Array[Move]:
	var moves: Array[Move] = []
	var spots := _playable(state, graph)

	# A card worth single_discard_value goes to the foundation alone, and can
	# never also form a pair: with target_sum == single_discard_value == 13, a
	# partner would have to be worth 0, and the lowest card is worth 1.
	# The `as Move.Zone` casts are required, not decorative: spots pack the zone
	# into a Vector3i component, and GDScript warns on a bare int reaching an
	# enum-typed parameter.
	for spot in spots:
		if spot.z == ruleset.single_discard_value:
			moves.append(Move.new(Move.Type.DISCARD_SINGLE, spot.x as Move.Zone, spot.y))

	# j starts at i+1, so each unordered pair is emitted exactly once.
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if spots[i].z + spots[j].z == ruleset.target_sum:
				moves.append(Move.new(
					Move.Type.MATCH_PAIR,
					spots[i].x as Move.Zone, spots[i].y,
					spots[j].x as Move.Zone, spots[j].y
				))

	if state.stock_remaining() > 0:
		moves.append(Move.new(Move.Type.DRAW_STOCK))

	return moves


static func apply(state: GameState, move: Move, ruleset: Ruleset) -> void:
	match move.type:
		Move.Type.DRAW_STOCK:
			for i in ruleset.draw_count:
				if state.stock_remaining() <= 0:
					break
				state.push_waste(0, state.stock[state.stock_index])
				state.stock_index += 1
		Move.Type.DISCARD_SINGLE:
			state.push_foundation(_take(state, move.a_zone, move.a_index))
		Move.Type.MATCH_PAIR:
			state.push_foundation(_take(state, move.a_zone, move.a_index))
			state.push_foundation(_take(state, move.b_zone, move.b_index))
		_:
			push_error("RulesEngine.apply: unknown move type %d" % move.type)


static func is_won(state: GameState, ruleset: Ruleset) -> bool:
	if score(state) > 0:
		return false
	match ruleset.win_condition:
		Ruleset.WinCondition.CLEAR_TABLEAU:
			return true
		Ruleset.WinCondition.CLEAR_ALL:
			return state.stock_remaining() == 0 and _wastes_empty(state)
	return false


static func is_stuck(state: GameState, graph: SlotGraph, ruleset: Ruleset) -> bool:
	return get_legal_moves(state, graph, ruleset).is_empty()


static func is_over(state: GameState, graph: SlotGraph, ruleset: Ruleset) -> bool:
	return is_won(state, ruleset) or is_stuck(state, graph, ruleset)


## Every position holding a card that could take part in a match right now, as
## (zone, index, card value) triples packed into a Vector3i.
static func _playable(state: GameState, graph: SlotGraph) -> Array[Vector3i]:
	var spots: Array[Vector3i] = []
	for slot_id in graph.size():
		if is_exposed(state, graph, slot_id):
			spots.append(Vector3i(
				Move.Zone.TABLEAU, slot_id, Card.value_of(state.tableau[slot_id])
			))
	for pile_index in state.wastes.size():
		var top := state.peek_waste(pile_index)
		if top != Card.NONE:
			spots.append(Vector3i(
				Move.Zone.WASTE, pile_index, Card.value_of(top)
			))
	return spots


## Removes a card from wherever it lives and returns it.
static func _take(state: GameState, zone: Move.Zone, index: int) -> int:
	match zone:
		Move.Zone.TABLEAU:
			var card := state.tableau[index]
			state.tableau[index] = Card.NONE
			return card
		Move.Zone.WASTE:
			return state.pop_waste(index)
	push_error("RulesEngine._take: unknown zone %d" % zone)
	return Card.NONE


static func _wastes_empty(state: GameState) -> bool:
	for pile in state.wastes:
		if not pile.is_empty():
			return false
	return true
