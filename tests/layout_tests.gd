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
	_test_pile_counts()
	_test_degenerate_viewport()


func _rules() -> Ruleset:
	return (load(CLASSIC) as Ruleset).duplicate() as Ruleset

func _layout(viewport: Vector2, previous := BoardLayout.Profile.LANDSCAPE) -> BoardLayout:
	var rules := _rules()
	return LayoutResolver.compute(SlotGraph.new(rules), rules, viewport, SOURCE, previous)


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
		var board := layout.slots[0]
		for rect in layout.slots:
			board = board.merge(rect)
		board = board.merge(layout.stock).merge(layout.foundation)
		for rect in layout.wastes:
			board = board.merge(rect)

		var screen := Rect2(Vector2.ZERO, viewport)
		_check.call(screen.encloses(board), "layout: the whole board fits on screen at %v" % viewport)
		_check.call(
			board.get_center().is_equal_approx(viewport * 0.5),
			"layout: the board is centred at %v" % viewport
		)

func _test_pile_counts() -> void:
	var layout := _layout(LANDSCAPE_VIEW)
	_check.call(layout.slots.size() == 28, "layout: 28 tableau rects")
	_check.call(layout.wastes.size() == 1, "layout: classic Pyramid has one waste rect")

	var rules := _rules()
	rules.waste_pile_count = 3                 # Apophis
	var apophis := LayoutResolver.compute(
		SlotGraph.new(rules), rules, LANDSCAPE_VIEW, SOURCE
	)
	_check.call(apophis.wastes.size() == 3, "layout: three waste piles when the ruleset asks for three")

## The viewport is briefly zero-sized during startup and on some resizes.
func _test_degenerate_viewport() -> void:
	var layout := _layout(Vector2.ZERO)
	_check.call(layout.slots.is_empty(), "layout: a zero viewport yields no rects rather than NaNs")
