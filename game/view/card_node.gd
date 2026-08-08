class_name CardNode
extends Sprite2D

## One card on screen. Visual only: it holds no rules and makes no decisions.
## BoardView tells it what to show and where to sit.
##
## Extends Sprite2D directly rather than wrapping one -- there is nothing to
## author visually yet. When there is (glow, shadow, a selection outline) this
## becomes a scene with children, and nothing outside needs to change.

const DIM := Color(0.55, 0.55, 0.62)

var card_id := Card.NONE


func _init() -> void:
	centered = false


func show_face(id: int) -> void:
	card_id = id
	texture = CardAtlas.face(id)


func show_back() -> void:
	card_id = Card.NONE
	texture = CardAtlas.back()


func show_empty_slot() -> void:
	card_id = Card.NONE
	texture = CardAtlas.empty_slot()


## Position and scale this card to fill `rect` exactly. The source size comes
## from the texture, so this needs no knowledge of the theme.
func place(rect: Rect2) -> void:
	position = rect.position
	if texture == null:
		return
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	scale = rect.size / source


## Covered cards are dimmed so the playable ones read at a glance.
func set_dimmed(dim: bool) -> void:
	modulate = DIM if dim else Color.WHITE
