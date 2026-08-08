class_name GameState

## The entire mutable game. Deliberately plain data -- no Nodes, no SlotGraph
## reference, nothing that cannot be copied cheaply. The M7 solver will
## duplicate this hundreds of thousands of times per deal.
##
## The tableau's *shape* lives in SlotGraph, which is immutable and shared, so
## it travels alongside this rather than inside it.

var tableau: PackedInt32Array               ## slot id -> card id, or Card.NONE
var stock: PackedInt32Array                 ## the full stock, in draw order
var stock_index: int = 0                    ## how many have been drawn
var wastes: Array[PackedInt32Array] = []    ## 1 pile normally, 3 for Apophis
var foundation: PackedInt32Array = PackedInt32Array()
var cells: PackedInt32Array = PackedInt32Array()
var redeals_used: int = 0


## Copy constructor -- callers write GameState.new(existing).
##
## This cannot be a clone() method: a script cannot refer to its own class_name
## as a value, so `GameState.new()` inside this file is a compile error. The
## type annotation on the parameter below is fine; only the constructor call is
## restricted.
func _init(source: GameState = null) -> void:
	if source == null:
		return
	tableau = source.tableau.duplicate()
	stock = source.stock.duplicate()
	stock_index = source.stock_index
	foundation = source.foundation.duplicate()
	cells = source.cells.duplicate()
	redeals_used = source.redeals_used

	# wastes is a regular Array holding packed arrays, so it is a *reference*
	# while everything else here is a value type. Without this loop the copy
	# would share waste piles with its source.
	wastes = []
	for pile in source.wastes:
		wastes.append(pile.duplicate())


func stock_remaining() -> int:
	return stock.size() - stock_index


## Appends to a waste pile, writing the result back.
##
## Packed arrays are copy-on-write values, so `wastes[i].append(x)` may mutate a
## temporary rather than the stored pile. Always go through this.
func push_waste(pile_index: int, card_id: int) -> void:
	var pile := wastes[pile_index]
	pile.append(card_id)
	wastes[pile_index] = pile
