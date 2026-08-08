class_name CardNode
extends Sprite2D

## One card on screen. Visual only: it holds no rules and makes no decisions.
## BoardView tells it what to show and where to sit.
##
## Extends Sprite2D directly rather than wrapping one -- there is nothing to
## author visually yet. When there is (glow, shadow, a real selection outline)
## this becomes a scene with children, and nothing outside needs to change.

const DIM := Color(0.55, 0.55, 0.62)
const HIGHLIGHT := Color(1.0, 0.93, 0.55)
const LIFT := 0.07                          ## fraction of card height a selection rises

var card_id := Card.NONE

var _rect := Rect2()
var _dimmed := false
var _selected := false


func _init() -> void:
	centered = false


func show_face(id: int) -> void:
	card_id = id
	texture = CardAtlas.face(id)
	_refresh()


func show_back() -> void:
	card_id = Card.NONE
	texture = CardAtlas.back()
	_refresh()


func show_empty_slot() -> void:
	card_id = Card.NONE
	texture = CardAtlas.empty_slot()
	_refresh()


## Position and scale this card to fill `rect`. The source size comes from the
## texture, so this needs no knowledge of the theme.
func place(rect: Rect2) -> void:
	_rect = rect
	_refresh()


## Covered cards are dimmed so the playable ones read at a glance.
func set_dimmed(on: bool) -> void:
	_dimmed = on
	_refresh()


func set_selected(on: bool) -> void:
	_selected = on
	_refresh()


## One place where visual state becomes transform and colour, so the three
## setters above can be called in any order without fighting each other.
##
## A lifted card never needs a z_index bump: it rises into the row above, which
## has lower slot ids and is therefore already drawn behind it.
func _refresh() -> void:
	if texture != null:
		var source := texture.get_size()
		if source.x > 0.0 and source.y > 0.0:
			scale = _rect.size / source

	var lift := _rect.size.y * LIFT if _selected else 0.0
	position = _rect.position - Vector2(0.0, lift)

	if _selected:
		modulate = HIGHLIGHT
	elif _dimmed:
		modulate = DIM
	else:
		modulate = Color.WHITE
