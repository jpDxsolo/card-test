extends Node

## M1 test runner. Open this scene and press F6.
##
## Expected values are hardcoded rather than recomputed from the production
## code. A test that derives its expectation using the same logic it is testing
## proves only that the code is self-consistent.

const CLASSIC := "res://data/rulesets/classic_pyramid.tres"

## First slot id of each row of a 7-row pyramid. Hardcoded on purpose.
const ROW_START: Array[int] = [0, 1, 3, 6, 10, 15, 21]

var _passed := 0
var _failed := 0

func _ready() -> void:
	_test_slot_counts()
	_test_ids_match_indices()
	_test_covering()
	_test_coverer_fan_out()
	_test_grid_positions()
	_test_bounds()
	_test_shipped_ruleset()
	_test_deal_shape()
	_test_deal_determinism()
	_test_exposure_at_deal()
	_test_exposure_uncovering()
	_test_state_copy()
	_test_kings_go_alone()
	_test_pair_to_thirteen()
	_test_pair_enumeration()
	_test_covered_cards_cannot_match()
	_test_apply_match_pair()
	_test_apply_draw()
	_test_draw_count_three()
	_test_win_conditions()
	_test_stuck()
	print("\n%d passed, %d failed" % [_passed, _failed])

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)

func _pyramid(rows: int) -> SlotGraph:
	var rules := Ruleset.new()
	rules.tableau_rows = rows
	return SlotGraph.new(rules)

func _test_slot_counts() -> void:
	_check(_pyramid(7).size() == 28, "7 rows -> 28 slots")
	_check(_pyramid(6).size() == 21, "6 rows -> 21 slots (the 21-card variant)")
	_check(_pyramid(1).size() == 1, "1 row -> 1 slot")

func _test_ids_match_indices() -> void:
	var graph := _pyramid(7)
	var bad := -1
	for i in graph.size():
		if graph.slots[i].id != i:
			bad = i
			break
	_check(bad == -1, "slot.id equals its array index (first mismatch at %d)" % bad)

func _test_covering() -> void:
	var graph := _pyramid(7)
	_check(graph.slots[0].covered_by == PackedInt32Array([1, 2]), "apex covered by 1 and 2")

	var bottom_clear := true
	for i in range(21, 28):
		if not graph.slots[i].covered_by.is_empty():
			bottom_clear = false
	_check(bottom_clear, "bottom row is uncovered")

	var pairs := true
	for i in 21:
		if graph.slots[i].covered_by.size() != 2:
			pairs = false
	_check(pairs, "every non-bottom slot has exactly 2 coverers")

## Checks the covering relation from the other direction. Slot (r, k) covers
## (r-1, k-1) and (r-1, k) where those exist, so the two slots at each row's
## ends cover exactly one slot above and the interior ones cover two.
##
## This is derived from pyramid geometry rather than from _build_pyramid, so a
## generator that mis-wires a single interior row fails here even though the
## apex check and the counts above would still pass.
func _test_coverer_fan_out() -> void:
	var graph := _pyramid(7)
	var fan := {}
	for slot in graph.slots:
		for coverer in slot.covered_by:
			fan[coverer] = fan.get(coverer, 0) + 1

	var ok := true
	for r in range(1, 7):
		for k in r + 1:
			var expected := 1 if (k == 0 or k == r) else 2
			if fan.get(ROW_START[r] + k, 0) != expected:
				ok = false
	_check(ok, "row ends cover 1 slot above, interior slots cover 2")

func _test_grid_positions() -> void:
	var graph := _pyramid(7)
	_check(graph.slots[0].grid_pos == Vector2(0, 0), "apex sits at the origin")
	_check(graph.slots[21].grid_pos == Vector2(-3, 3), "bottom-left at (-3, 3)")
	_check(graph.slots[27].grid_pos == Vector2(3, 3), "bottom-right at (3, 3)")

	var symmetric := true
	for r in 7:
		var left := graph.slots[ROW_START[r]]
		var right := graph.slots[ROW_START[r] + r]
		if not is_equal_approx(left.grid_pos.x, -right.grid_pos.x):
			symmetric = false
		if not is_equal_approx(left.grid_pos.y, right.grid_pos.y):
			symmetric = false
	_check(symmetric, "every row is symmetric about x = 0")

func _test_bounds() -> void:
	# Units are anisotropic: width in card widths, height in card heights.
	_check(_pyramid(7).bounds() == Rect2(-3, 0, 7, 4), "7-row pyramid is 7 x 4 card units")
	_check(_pyramid(6).bounds() == Rect2(-2.5, 0, 6, 3.5), "6-row pyramid is 6 x 3.5 card units")

## The resource the game actually ships. Everything above builds a Ruleset in
## code, so without this a bad value saved into the .tres would pass every test
## and still deal the wrong game.
func _test_shipped_ruleset() -> void:
	var rules := load(CLASSIC) as Ruleset
	_check(rules != null, "classic_pyramid.tres loads as a Ruleset")
	if rules == null:
		return
	_check(rules.tableau_shape == Ruleset.Shape.PYRAMID, "shipped ruleset: pyramid shape")
	_check(rules.tableau_rows == 7, "shipped ruleset: 7 rows")
	_check(rules.target_sum == 13, "shipped ruleset: target sum is 13")
	_check(rules.single_discard_value == 13, "shipped ruleset: kings discard alone")
	_check(rules.win_condition == Ruleset.WinCondition.CLEAR_ALL, "shipped ruleset: strict win")
	_check(SlotGraph.new(rules).size() == 28, "shipped ruleset builds a 28-slot tableau")


# --- M1b-1: dealing, exposure, state copying ---------------------------------

## Always a fresh copy. load() returns a shared cached resource, so a test that
## tweaked a field on it would silently corrupt every test that ran afterwards.
func _classic() -> Ruleset:
	return (load(CLASSIC) as Ruleset).duplicate() as Ruleset

func _test_deal_shape() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := RulesEngine.deal(rules, graph, 12345)
	_check(state.tableau.size() == 28, "deal: 28 tableau slots")
	_check(state.stock.size() == 24, "deal: 24 stock cards")
	_check(state.wastes.size() == 1, "deal: one waste pile")
	_check(state.wastes[0].is_empty(), "deal: waste starts empty")
	_check(state.stock_index == 0, "deal: nothing drawn yet")
	_check(state.stock_remaining() == 24, "deal: 24 cards remain in stock")

	var seen := {}
	for c in state.tableau:
		seen[c] = true
	for c in state.stock:
		seen[c] = true
	_check(seen.size() == 52, "deal: all 52 cards present exactly once")

func _test_deal_determinism() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var a := RulesEngine.deal(rules, graph, 99)
	var b := RulesEngine.deal(rules, graph, 99)
	var c := RulesEngine.deal(rules, graph, 100)
	_check(a.tableau == b.tableau, "same seed deals the same tableau")
	_check(a.stock == b.stock, "same seed deals the same stock")
	_check(a.tableau != c.tableau, "different seeds deal differently")

func _test_exposure_at_deal() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := RulesEngine.deal(rules, graph, 7)

	var bottom := true
	for i in range(21, 28):
		if not RulesEngine.is_exposed(state, graph, i):
			bottom = false
	_check(bottom, "exposure: the whole bottom row is exposed at deal")

	var upper := true
	for i in 21:
		if RulesEngine.is_exposed(state, graph, i):
			upper = false
	_check(upper, "exposure: nothing above the bottom row is exposed at deal")

## The rule players get wrong -- an Ace resting on a Queen blocks her. An
## is_exposed that used "any coverer gone" instead of "all coverers gone" would
## pass every other test in this file.
func _test_exposure_uncovering() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := RulesEngine.deal(rules, graph, 7)

	# Slot 15 is row 5, leftmost. Its coverers are 21 and 22.
	state.tableau[21] = Card.NONE
	_check(not RulesEngine.is_exposed(state, graph, 15), "exposure: one coverer left is still covered")

	state.tableau[22] = Card.NONE
	_check(RulesEngine.is_exposed(state, graph, 15), "exposure: slot opens when both coverers go")

	state.tableau[15] = Card.NONE
	_check(not RulesEngine.is_exposed(state, graph, 15), "exposure: an empty slot is not exposed")

func _test_state_copy() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var original := RulesEngine.deal(rules, graph, 42)
	var copy := GameState.new(original)

	_check(copy.tableau == original.tableau, "copy: tableau matches")
	_check(RulesEngine.score(original) == 28, "score: a fresh deal scores 28")

	copy.tableau[0] = Card.NONE
	copy.push_waste(0, 5)
	copy.stock_index = 9

	# Guard first: if push_waste silently no-ops, the deep-copy check below
	# would pass for the wrong reason.
	_check(copy.wastes[0].size() == 1, "copy: push_waste actually took effect")
	_check(original.tableau[0] != Card.NONE, "copy: mutating the copy leaves the original tableau alone")
	_check(original.wastes[0].is_empty(), "copy: waste piles are deep-copied, not shared")
	_check(original.stock_index == 0, "copy: scalars are independent")
	_check(RulesEngine.score(copy) == 27, "score: removing one tableau card scores 27")


# --- M1b-2: moves, legality, application -------------------------------------

# Rank indices, so the intent of each fixture is readable.
const ACE := 0
const TWO := 1
const THREE := 2
const QUEEN := 11
const KING := 12

## A board with nothing on it. Move-generation tests place their own cards so
## they never depend on what a particular shuffle happened to produce.
func _empty_state(graph: SlotGraph) -> GameState:
	var state := GameState.new()
	state.tableau = PackedInt32Array()
	state.tableau.resize(graph.size())
	state.tableau.fill(Card.NONE)
	state.stock = PackedInt32Array()
	state.stock_index = 0
	var piles: Array[PackedInt32Array] = [PackedInt32Array()]
	state.wastes = piles
	state.foundation = PackedInt32Array()
	state.cells = PackedInt32Array()
	return state

func _count(moves: Array[Move], t: Move.Type) -> int:
	var n := 0
	for move in moves:
		if move.type == t:
			n += 1
	return n

func _test_kings_go_alone() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.tableau[21] = Card.make(Card.Suit.SPADES, KING)

	var moves := RulesEngine.get_legal_moves(state, graph, rules)
	_check(_count(moves, Move.Type.DISCARD_SINGLE) == 1, "moves: a lone exposed King is discardable")
	_check(_count(moves, Move.Type.MATCH_PAIR) == 0, "moves: a King never also forms a pair")

func _test_pair_to_thirteen() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.tableau[21] = Card.make(Card.Suit.HEARTS, ACE)      # worth 1
	state.tableau[22] = Card.make(Card.Suit.SPADES, QUEEN)    # worth 12

	var moves := RulesEngine.get_legal_moves(state, graph, rules)
	_check(_count(moves, Move.Type.MATCH_PAIR) == 1, "moves: A + Q is one pair, emitted once not twice")

func _test_pair_enumeration() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.tableau[21] = Card.make(Card.Suit.HEARTS, ACE)
	state.tableau[22] = Card.make(Card.Suit.SPADES, QUEEN)
	state.tableau[23] = Card.make(Card.Suit.CLUBS, QUEEN)

	var moves := RulesEngine.get_legal_moves(state, graph, rules)
	_check(_count(moves, Move.Type.MATCH_PAIR) == 2, "moves: one Ace and two Queens make two distinct pairs")

## The rule that defines Pyramid. Slot 15 sits under 21 and 22, so its Ace is
## unplayable until both are gone -- even though the Queen it would pair with
## is sitting exposed the whole time.
func _test_covered_cards_cannot_match() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.tableau[15] = Card.make(Card.Suit.HEARTS, ACE)
	state.tableau[23] = Card.make(Card.Suit.SPADES, QUEEN)
	state.tableau[21] = Card.make(Card.Suit.CLUBS, TWO)       # blockers worth 2 and 3,
	state.tableau[22] = Card.make(Card.Suit.CLUBS, THREE)     # which pair with nothing here

	var moves := RulesEngine.get_legal_moves(state, graph, rules)
	_check(_count(moves, Move.Type.MATCH_PAIR) == 0, "moves: a covered Ace cannot pair with an exposed Queen")

	state.tableau[21] = Card.NONE
	_check(
		_count(RulesEngine.get_legal_moves(state, graph, rules), Move.Type.MATCH_PAIR) == 0,
		"moves: clearing one of two coverers is not enough"
	)

	state.tableau[22] = Card.NONE
	_check(
		_count(RulesEngine.get_legal_moves(state, graph, rules), Move.Type.MATCH_PAIR) == 1,
		"moves: clearing both coverers makes the pair legal"
	)

func _test_apply_match_pair() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.tableau[21] = Card.make(Card.Suit.HEARTS, ACE)
	state.tableau[22] = Card.make(Card.Suit.SPADES, QUEEN)

	var moves := RulesEngine.get_legal_moves(state, graph, rules)
	RulesEngine.apply(state, moves[0], rules)
	_check(state.tableau[21] == Card.NONE, "apply: the first card leaves the tableau")
	_check(state.tableau[22] == Card.NONE, "apply: the second card leaves the tableau")
	_check(state.foundation.size() == 2, "apply: both cards reach the foundation")
	_check(RulesEngine.score(state) == 0, "apply: the tableau is now clear")

func _test_apply_draw() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	var king := Card.make(Card.Suit.HEARTS, KING)
	state.stock = PackedInt32Array([king, Card.make(Card.Suit.CLUBS, TWO)])

	_check(
		_count(RulesEngine.get_legal_moves(state, graph, rules), Move.Type.DRAW_STOCK) == 1,
		"moves: drawing is legal while the stock has cards"
	)

	RulesEngine.apply(state, Move.new(Move.Type.DRAW_STOCK), rules)
	_check(state.stock_index == 1, "apply: drawing advances the stock pointer")
	_check(state.wastes[0].size() == 1, "apply: the drawn card lands on the waste")
	_check(state.peek_waste(0) == king, "apply: the card drawn is the top of the stock")

	# The waste top plays exactly like an exposed tableau card.
	_check(
		_count(RulesEngine.get_legal_moves(state, graph, rules), Move.Type.DISCARD_SINGLE) == 1,
		"moves: a King on the waste is discardable"
	)

	state.stock_index = 2
	_check(
		_count(RulesEngine.get_legal_moves(state, graph, rules), Move.Type.DRAW_STOCK) == 0,
		"moves: no draw once the stock is exhausted"
	)

func _test_draw_count_three() -> void:
	var rules := _classic()
	rules.draw_count = 3                      # Tut's Tomb deals three at a time
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.stock = PackedInt32Array([0, 1, 2, 3])

	RulesEngine.apply(state, Move.new(Move.Type.DRAW_STOCK), rules)
	_check(state.wastes[0].size() == 3, "draw_count 3: three cards move to the waste")
	_check(state.stock_index == 3, "draw_count 3: the stock pointer advances by three")

	RulesEngine.apply(state, Move.new(Move.Type.DRAW_STOCK), rules)
	_check(state.wastes[0].size() == 4, "draw_count 3: a short final draw takes what is left")

func _test_win_conditions() -> void:
	var strict := _classic()
	var graph := SlotGraph.new(strict)
	var state := _empty_state(graph)           # tableau already clear
	state.stock = PackedInt32Array([Card.make(Card.Suit.HEARTS, TWO)])

	_check(not RulesEngine.is_won(state, strict), "win: strict rules need the stock cleared too")

	var relaxed := _classic()
	relaxed.win_condition = Ruleset.WinCondition.CLEAR_TABLEAU
	_check(RulesEngine.is_won(state, relaxed), "win: relaxed rules win on a clear tableau alone")

	state.stock_index = 1
	_check(RulesEngine.is_won(state, strict), "win: strict rules win once stock and waste are empty")

func _test_stuck() -> void:
	var rules := _classic()
	var graph := SlotGraph.new(rules)
	var state := _empty_state(graph)
	state.tableau[21] = Card.make(Card.Suit.HEARTS, TWO)
	state.tableau[22] = Card.make(Card.Suit.CLUBS, THREE)

	_check(RulesEngine.is_stuck(state, graph, rules), "stuck: two cards summing to 5, no stock, no moves")
	_check(not RulesEngine.is_won(state, rules), "stuck: a stuck game is not a won one")
	_check(RulesEngine.is_over(state, graph, rules), "stuck: the game is over either way")
