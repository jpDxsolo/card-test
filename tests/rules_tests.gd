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

func _classic() -> Ruleset:
	return load(CLASSIC) as Ruleset

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
