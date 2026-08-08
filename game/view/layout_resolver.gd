class_name LayoutResolver

## Turns the abstract slot graph into pixel rectangles for a given viewport.
##
## Pure maths -- no Nodes, so it is unit-testable. Everything upstream works in
## card units; this is the only place they become pixels, and the only place
## that needs to know how big a card is.
##
## The units are anisotropic (see Slot.grid_pos): grid_pos.x counts card
## WIDTHS, grid_pos.y counts card HEIGHTS. So positions are scaled by the pixel
## card size componentwise -- never by a single scalar. Getting this wrong
## squashes the rows to a 65% overlap and makes the board overflow the box that
## was just fitted to it.

const MARGIN := 0.94       ## fraction of the viewport the board may fill
const PILE_GAP := 0.25     ## space between piles, in card units

## Aspect thresholds for choosing a profile. The gap between them is
## hysteresis: a window dragged through square does not flicker back and forth.
const TO_LANDSCAPE := 1.1
const TO_PORTRAIT := 0.9


static func choose_profile(viewport: Vector2, previous: BoardLayout.Profile) -> BoardLayout.Profile:
	if viewport.y <= 0.0:
		return previous
	var aspect := viewport.x / viewport.y
	if previous == BoardLayout.Profile.PORTRAIT:
		return BoardLayout.Profile.LANDSCAPE if aspect > TO_LANDSCAPE else BoardLayout.Profile.PORTRAIT
	return BoardLayout.Profile.PORTRAIT if aspect < TO_PORTRAIT else BoardLayout.Profile.LANDSCAPE


## `source_card` is the card's size in source pixels, e.g. CardTheme.card_size().
## `previous` is last frame's profile, fed back so hysteresis works; pass the
## default on the first call.
static func compute(
	graph: SlotGraph,
	ruleset: Ruleset,
	viewport: Vector2,
	source_card: Vector2,
	previous: BoardLayout.Profile = BoardLayout.Profile.LANDSCAPE
) -> BoardLayout:
	var layout := BoardLayout.new()
	layout.profile = choose_profile(viewport, previous)
	if viewport.x <= 0.0 or viewport.y <= 0.0 or graph.size() == 0:
		return layout

	# 1. Place everything in card units.
	var tableau := graph.bounds()
	var anchors := _pile_anchors(tableau, ruleset, layout.profile)

	# 2. Bounding box of the whole board, cards included.
	var content := tableau
	for anchor in anchors:
		content = content.merge(Rect2(anchor, Vector2.ONE))

	# 3. The largest uniform scale that still fits. Note each axis is measured
	#    against its own card dimension.
	var scale := minf(
		viewport.x / (content.size.x * source_card.x),
		viewport.y / (content.size.y * source_card.y)
	) * MARGIN
	layout.card_size = source_card * scale

	# 4. Centre the board and convert every anchor to pixels.
	var board_px := content.size * layout.card_size
	var origin := (viewport - board_px) * 0.5

	layout.slots.resize(graph.size())
	for slot in graph.slots:
		layout.slots[slot.id] = _rect(slot.grid_pos, content, origin, layout.card_size)

	layout.stock = _rect(anchors[0], content, origin, layout.card_size)
	layout.wastes = []
	for i in ruleset.waste_pile_count:
		layout.wastes.append(_rect(anchors[1 + i], content, origin, layout.card_size))
	layout.foundation = _rect(anchors[anchors.size() - 1], content, origin, layout.card_size)
	return layout


## Top-left of each pile in card units, ordered stock, waste(s), foundation.
##
## This is the only place the two profiles actually differ. Landscape stacks the
## piles in a column beside the tableau, because a pyramid plus a row underneath
## is nearly square and wastes most of a 16:9 window. Portrait puts them in a row
## below, where the vertical room exists.
static func _pile_anchors(
	tableau: Rect2, ruleset: Ruleset, profile: BoardLayout.Profile
) -> Array[Vector2]:
	var count := 2 + ruleset.waste_pile_count      # stock + waste(s) + foundation
	var step := 1.0 + PILE_GAP
	var span := count * 1.0 + (count - 1) * PILE_GAP
	var anchors: Array[Vector2] = []

	if profile == BoardLayout.Profile.LANDSCAPE:
		var x := tableau.end.x + PILE_GAP
		var y := tableau.position.y + (tableau.size.y - span) * 0.5
		for i in count:
			anchors.append(Vector2(x, y + i * step))
	else:
		var y := tableau.end.y + PILE_GAP
		var x := tableau.position.x + (tableau.size.x - span) * 0.5
		for i in count:
			anchors.append(Vector2(x + i * step, y))
	return anchors


## What sits under `point`, as (BoardLayout.Target, index). Pure, so it is
## unit-testable without a scene tree; BoardView never needs collision shapes.
##
## `tableau` is the state's slot-to-card array. Empty slots must not absorb
## clicks: in a pyramid, removing a card is precisely what should make the card
## it was covering clickable.
static func hit_test(layout: BoardLayout, point: Vector2, tableau: PackedInt32Array) -> Vector2i:
	if layout == null:
		return Vector2i(BoardLayout.Target.NONE, -1)

	# Reverse of draw order, so the card visually on top wins. Slot ids run top
	# row first, so counting down tests lower rows -- the covering ones -- first.
	for i in range(layout.slots.size() - 1, -1, -1):
		if i < tableau.size() and tableau[i] == Card.NONE:
			continue
		if layout.slots[i].has_point(point):
			return Vector2i(BoardLayout.Target.TABLEAU, i)

	for i in range(layout.wastes.size() - 1, -1, -1):
		if layout.wastes[i].has_point(point):
			return Vector2i(BoardLayout.Target.WASTE, i)

	if layout.stock.has_point(point):
		return Vector2i(BoardLayout.Target.STOCK, 0)

	return Vector2i(BoardLayout.Target.NONE, -1)


static func _rect(unit_pos: Vector2, content: Rect2, origin: Vector2, card_px: Vector2) -> Rect2:
	return Rect2(origin + (unit_pos - content.position) * card_px, card_px)
