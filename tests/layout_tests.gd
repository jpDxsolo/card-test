class_name LayoutTests

## Layout maths tests. Driven from rules_tests.gd so there is still one scene to
## run, but kept in its own file because this is view-layer geometry rather than
## game rules.

const CLASSIC := "res://data/rulesets/classic_pyramid.tres"

## Card size in source pixels. Deliberately a literal rather than read from
## CardTheme -- these tests check the geometry, not the current art pack.
const SOURCE := Vector2(42, 60)

const LANDSCAPE_VIEW := Vector2(1280, 720)
const PORTRAIT_VIEW := Vector2(400, 800)

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	_test_profile_choice()
	_test_profile_hysteresis()
	_test_card_aspect_preserved()
	_test_row_step_is_one_card_width()
	_test_row_overlap_is_half_a_card_height()
	_test_uniform_card_size()
	_test_board_fits_and_is_centred()
	_test_reserved_area_is_respected()
	_test_pile_counts()
	_test_degenerate_viewport()
	_test_hit_test_basics()
	_test_hit_test_prefers_the_card_on_top()
	_test_hit_test_ignores_empty_slots()


func _rules() -> Ruleset:
	return (load(CLASSIC) as Ruleset).duplicate() as Ruleset

func _layout(viewport: Vector2, previous := BoardLayout.Profile.LANDSCAPE) -> BoardLayout:
	return _layout_in(Rect2(Vector2.ZERO, viewport), previous)

func _layout_in(area: Rect2, previous := BoardLayout.Profile.LANDSCAPE) -> BoardLayout:
	var rules := _rules()
	return LayoutResolver.compute(SlotGraph.new(rules), rules, area, SOURCE, previous)

## Union of every rect in a layout.
func _bounds_of(layout: BoardLayout) -> Rect2:
	var box := layout.slots[0]
	for rect in layout.slots:
		box = box.merge(rect)
	box = box.merge(layout.stock).merge(layout.foundation)
	for rect in layout.wastes:
		box = box.merge(rect)
	return box


func _test_profile_choice() -> void:
	_check.call(
		LayoutResolver.choose_profile(LANDSCAPE_VIEW, BoardLayout.Profile.LANDSCAPE) == BoardLayout.Profile.LANDSCAPE,
		"layout: a 16:9 window is landscape"
	)
	_check.call(
		LayoutResolver.choose_profile(PORTRAIT_VIEW, BoardLayout.Profile.LANDSCAPE) == BoardLayout.Profile.PORTRAIT,
		"layout: a tall window flips to portrait"
	)

## A window dragged slowly through square must not oscillate. Aspect 1.0 keeps
## whichever profile it already had.
func _test_profile_hysteresis() -> void:
	var square := Vector2(600, 600)
	_check.call(
		LayoutResolver.choose_profile(square, BoardLayout.Profile.LANDSCAPE) == BoardLayout.Profile.LANDSCAPE,
		"layout: a square window stays landscape if it was landscape"
	)
	_check.call(
		LayoutResolver.choose_profile(square, BoardLayout.Profile.PORTRAIT) == BoardLayout.Profile.PORTRAIT,
		"layout: a square window stays portrait if it was portrait"
	)

func _test_card_aspect_preserved() -> void:
	for viewport in [LANDSCAPE_VIEW, PORTRAIT_VIEW]:
		var layout := _layout(viewport)
		_check.call(
			is_equal_approx(layout.card_size.y / layout.card_size.x, SOURCE.y / SOURCE.x),
			"layout: cards keep their source aspect ratio at %v" % viewport
		)

func _test_row_step_is_one_card_width() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	# Slots 21 and 22 are the first two of the bottom row.
	_check.call(
		is_equal_approx(layout.slots[22].position.x - layout.slots[21].position.x, layout.card_size.x),
		"layout: neighbours in a row are exactly one card width apart"
	)

## The anisotropic-units detector. grid_pos.y counts card HEIGHTS, so one row
## step must be half a card's *height*. Scaling both axes by card width -- the
## obvious mistake -- would make this 21px where the card is 60 tall.
func _test_row_overlap_is_half_a_card_height() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	_check.call(
		is_equal_approx(layout.slots[1].position.y - layout.slots[0].position.y, layout.card_size.y * 0.5),
		"layout: rows overlap by exactly half a card height"
	)

func _test_uniform_card_size() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	var uniform := true
	for rect in layout.slots:
		if not rect.size.is_equal_approx(layout.card_size):
			uniform = false
	if not layout.stock.size.is_equal_approx(layout.card_size):
		uniform = false
	if not layout.foundation.size.is_equal_approx(layout.card_size):
		uniform = false
	_check.call(uniform, "layout: every rect is exactly one card in size")

func _test_board_fits_and_is_centred() -> void:
	for viewport in [LANDSCAPE_VIEW, PORTRAIT_VIEW]:
		var layout := _layout(viewport)
		var board := _bounds_of(layout)
		var screen := Rect2(Vector2.ZERO, viewport)
		_check.call(screen.encloses(board), "layout: the whole board fits on screen at %v" % viewport)
		_check.call(
			board.get_center().is_equal_approx(viewport * 0.5),
			"layout: the board is centred at %v" % viewport
		)

## The HUD reserves a strip along the top. The board must fit under it, not
## merely be centred in a shifted box -- this is the overlap that put text on
## top of the pyramid's apex.
func _test_reserved_area_is_respected() -> void:
	var inset := 90.0
	var area := Rect2(0.0, inset, LANDSCAPE_VIEW.x, LANDSCAPE_VIEW.y - inset)
	var layout := _layout_in(area)
	var board := _bounds_of(layout)

	_check.call(area.encloses(board), "layout: the board stays inside the reserved area")
	_check.call(board.position.y >= inset, "layout: nothing is drawn above the HUD strip")
	_check.call(
		board.get_center().is_equal_approx(area.get_center()),
		"layout: the board centres on the area, not the viewport"
	)

	# A shorter area must produce smaller cards, not an overflowing board.
	_check.call(
		layout.card_size.y < _layout(LANDSCAPE_VIEW).card_size.y,
		"layout: reserving space shrinks the cards rather than clipping them"
	)

func _test_pile_counts() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	_check.call(layout.slots.size() == 28, "layout: 28 tableau rects")
	_check.call(layout.wastes.size() == 1, "layout: classic Pyramid has one waste rect")

	var rules := _rules()
	rules.waste_pile_count = 3                 # Apophis
	var apophis := LayoutResolver.compute(
		SlotGraph.new(rules), rules, Rect2(Vector2.ZERO, LANDSCAPE_VIEW), SOURCE
	)
	_check.call(apophis.wastes.size() == 3, "layout: three waste piles when the ruleset asks for three")

## The viewport is briefly zero-sized during startup and on some resizes.
func _test_degenerate_viewport() -> void:
	var layout := _layout(Vector2.ZERO)
	_check.call(layout.slots.is_empty(), "layout: a zero viewport yields no rects rather than NaNs")


## Every tableau slot holds a card, so nothing is transparent to clicks.
func _full_tableau() -> PackedInt32Array:
	var tableau := PackedInt32Array()
	tableau.resize(28)
	for i in 28:
		tableau[i] = i
	return tableau

func _test_hit_test_basics() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	var full := _full_tableau()

	var hit := LayoutResolver.hit_test(layout, layout.slots[21].get_center(), full)
	_check.call(hit == Vector2i(BoardLayout.Target.TABLEAU, 21), "hit: the centre of a slot hits that slot")

	hit = LayoutResolver.hit_test(layout, layout.stock.get_center(), full)
	_check.call(hit.x == BoardLayout.Target.STOCK, "hit: the stock is clickable")

	hit = LayoutResolver.hit_test(layout, layout.wastes[0].get_center(), full)
	_check.call(hit == Vector2i(BoardLayout.Target.WASTE, 0), "hit: the waste is clickable")

	hit = LayoutResolver.hit_test(layout, Vector2(-50, -50), full)
	_check.call(hit.x == BoardLayout.Target.NONE, "hit: a click off the board hits nothing")

## Rows overlap by half a card, so plenty of points sit inside two slots at once.
## The lower row covers the upper one, so it must win -- otherwise the player
## would select a card they can see is buried.
func _test_hit_test_prefers_the_card_on_top() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	var full := _full_tableau()

	# Slot 15 (row 5) and slot 21 (row 6) share a column; 21 covers 15.
	var overlap := layout.slots[21].position + Vector2(layout.card_size.x * 0.5, layout.card_size.y * 0.1)
	_check.call(layout.slots[15].has_point(overlap), "hit: the sample point really is inside both slots")
	_check.call(
		LayoutResolver.hit_test(layout, overlap, full) == Vector2i(BoardLayout.Target.TABLEAU, 21),
		"hit: where two rows overlap, the covering card wins"
	)

## Removing a card is exactly what should make the card beneath it clickable.
func _test_hit_test_ignores_empty_slots() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	var tableau := _full_tableau()
	var overlap := layout.slots[21].position + Vector2(layout.card_size.x * 0.5, layout.card_size.y * 0.1)

	tableau[21] = Card.NONE
	_check.call(
		LayoutResolver.hit_test(layout, overlap, tableau) == Vector2i(BoardLayout.Target.TABLEAU, 15),
		"hit: an emptied slot lets the click fall through to the card it covered"
	)
