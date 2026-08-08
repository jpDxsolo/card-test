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
