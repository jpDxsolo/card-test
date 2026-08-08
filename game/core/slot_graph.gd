class_name SlotGraph

## The tableau modelled as a directed graph of slots (PLAN.md §4).
##
## A slot is playable when every slot in its covered_by list is empty. That one
## rule, over different graphs, produces every documented variant's tableau --
## which is why nothing downstream (exposure, layout, hit testing, the solver)
## needs to know it is looking at a pyramid.
##
## Built once per deal and never mutated: cards are removed from GameState, not
## from here, so the solver can share one graph across every state it explores.

var slots: Array[Slot] = []

func _init(ruleset: Ruleset) -> void:
	match ruleset.tableau_shape:
		Ruleset.Shape.PYRAMID:
			_build_pyramid(ruleset.tableau_rows)
		_:
			push_error("SlotGraph: shape %d not implemented" % ruleset.tableau_shape)

func size() -> int:
	return slots.size()

## Bounding box in card units, including each card's own extent. Vector2.ONE
## here means one whole card -- one card width on x, one card height on y (see
## Slot.grid_pos). A 7-row pyramid measures 7 x 4: seven cards wide, four cards
## tall. LayoutResolver uses this in M2 to fit the tableau to the viewport, and
## must scale the two axes by card_size.x and card_size.y respectively.
func bounds() -> Rect2:
	if slots.is_empty():
		return Rect2()
	var box := Rect2(slots[0].grid_pos, Vector2.ONE)
	for slot in slots:
		box = box.merge(Rect2(slot.grid_pos, Vector2.ONE))
	return box

## Row r holds r+1 slots. Slot ids run left to right, top row first, so a
## slot's id is always its index in `slots`.
##
## x = c - r * 0.5 centres each row on x = 0, so the apex sits at 0 and a 7-row
## bottom row spans -3 to +3. y = r * 0.5 steps down half a card height per row,
## which is the 50% vertical overlap that makes a pyramid look like one.
func _build_pyramid(rows: int) -> void:
	for r in rows:
		for c in r + 1:
			var covered := PackedInt32Array()
			if r < rows - 1:
				var below := _row_start(r + 1) + c
				covered.append(below)
				covered.append(below + 1)
			slots.append(Slot.new(
				_row_start(r) + c,
				Slot.Zone.TABLEAU,
				Vector2(c - r * 0.5, r * 0.5),
				covered
			))

## First slot id of row r. The rows above it hold r*(r+1)/2 slots between them.
static func _row_start(r: int) -> int:
	@warning_ignore("integer_division")
	return r * (r + 1) / 2
