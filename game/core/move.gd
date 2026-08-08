class_name Move

## A move as data, not behaviour.
##
## Representing moves this way is what lets one mechanism serve move
## generation, the hint system and the M7 solver alike -- and it is why undo,
## if we ever want it, is a history array plus an unapply() rather than a
## rewrite (PLAN.md §3).

enum Type { MATCH_PAIR, DISCARD_SINGLE, DRAW_STOCK }

## Where a playable card lives. Distinct from Slot.Zone, which describes
## positions inside the tableau; this addresses the whole board. CELL is absent
## until cells are actually dealt (M8).
enum Zone { TABLEAU, WASTE }

var type: Type
var a_zone: Zone
var a_index: int
var b_zone: Zone
var b_index: int


func _init(
	p_type: Type,
	p_a_zone: Zone = Zone.TABLEAU,
	p_a_index: int = -1,
	p_b_zone: Zone = Zone.TABLEAU,
	p_b_index: int = -1
) -> void:
	type = p_type
	a_zone = p_a_zone
	a_index = p_a_index
	b_zone = p_b_zone
	b_index = p_b_index


func describe() -> String:
	match type:
		Type.DRAW_STOCK:
			return "draw"
		Type.DISCARD_SINGLE:
			return "discard %s" % _where(a_zone, a_index)
		Type.MATCH_PAIR:
			return "match %s + %s" % [_where(a_zone, a_index), _where(b_zone, b_index)]
	return "unknown move"


static func _where(zone: Zone, index: int) -> String:
	var label := "tableau" if zone == Zone.TABLEAU else "waste"
	return "%s[%d]" % [label, index]
