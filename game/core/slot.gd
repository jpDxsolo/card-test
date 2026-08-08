class_name Slot

## One position in the tableau. Immutable once the graph is built -- the graph
## is shared, static topology; only GameState changes as cards are removed.

enum Zone { TABLEAU, RESERVE, COLUMN }

var id: int
var zone: Zone

## Top-left corner in CARD UNITS, and the axes are not the same size:
## x is measured in card widths, y in card heights. So x += 1.0 is one card to
## the right, y += 1.0 is one card down, and (1, 1) is exactly one whole card.
##
## LayoutResolver must therefore scale x by card_size.x and y by card_size.y
## separately. Treating both axes as card widths squashes the pyramid and
## under-reports its height -- see PLAN.md §7.
var grid_pos: Vector2

## Slots that must be empty before this one is playable.
var covered_by: PackedInt32Array

func _init(
	p_id: int,
	p_zone: Zone,
	p_grid_pos: Vector2,
	p_covered_by: PackedInt32Array
) -> void:
	id = p_id
	zone = p_zone
	grid_pos = p_grid_pos
	covered_by = p_covered_by
