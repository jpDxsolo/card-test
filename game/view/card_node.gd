class_name CardNode
extends Sprite2D

## One card on screen. Visual only: it holds no rules and makes no decisions.
## BoardView tells it what to show and where to sit.
##
## Extends Sprite2D directly rather than wrapping one -- there is nothing to
## author visually yet. When there is (glow, shadow, a real selection outline)
## this becomes a scene with children, and nothing outside needs to change.
##
## M5 note: every animated quantity is a plain member folded into _refresh(),
## never a direct write to `position` or `scale`. A tween drives the member and
## calls _refresh(); a layout change writes `_rect` and calls _refresh(). Because
## both go through the same funnel they cannot fight each other, and a resize
## mid-flight repositions the card instead of tearing it.

const DIM := Color(0.55, 0.55, 0.62)
const HIGHLIGHT := Color(1.0, 0.93, 0.55)
const LIFT := 0.07                          ## fraction of card height a selection rises

var card_id := Card.NONE

var _rect := Rect2()
var _dimmed := false
var _selected := false

## Animated. _lift is the selection rise, _offset the invalid shake, and _flip
## the horizontal squeeze of a card turning over (1 = face on, 0 = edge on).
var _lift := 0.0
var _offset := Vector2.ZERO
var _flip := 1.0

var _lift_tween: Tween
var _flip_tween: Tween


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


## `time` of 0 sets the selection instantly, which is what a full re-sync wants;
## the controller passes a real duration so the lift eases.
##
## Returns early when nothing changed: BoardView.set_selection() clears every
## card on every refresh, and without this guard that would spawn a tween per
## card per click.
func set_selected(on: bool, time := 0.0) -> void:
	if _selected == on:
		return
	_selected = on

	# Colour is not animated, so it lands immediately whatever the lift is doing.
	_refresh()

	var target := _rect.size.y * LIFT if on else 0.0
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	if time <= 0.0 or not is_inside_tree():
		_lift = target
		_refresh()
		return
	_lift_tween = create_tween()
	_lift_tween.tween_method(_set_lift, _lift, target, time).set_trans(Tween.TRANS_QUAD)


## Turns the card over, swapping to `id` at the point it is edge-on so the new
## face is never visible during the first half. Pass Card.NONE to turn face down.
func flip_to(id: int, time: float) -> Tween:
	cancel_flip()
	_flip_tween = create_tween()
	_flip_tween.tween_method(_set_flip, 1.0, 0.0, time * 0.5)
	_flip_tween.tween_callback(func() -> void:
		if id == Card.NONE:
			show_back()
		else:
			show_face(id))
	_flip_tween.tween_method(_set_flip, 0.0, 1.0, time * 0.5)
	return _flip_tween


## Abandons a turn in progress and leaves the card face on. Whatever texture it
## had reached is left alone -- the caller re-syncs from the state, which is the
## only thing that knows which face belongs here.
func cancel_flip() -> void:
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip = 1.0
	_refresh()


## A damped horizontal wobble: three passes that decay to nothing, so the card
## ends exactly where it started with no cleanup needed.
func shake(amplitude: float, time: float) -> Tween:
	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			_offset.x = sin(t * TAU * 1.5) * amplitude * (1.0 - t)
			_refresh(),
		0.0, 1.0, time
	)
	tween.tween_callback(func() -> void:
		_offset = Vector2.ZERO
		_refresh())
	return tween


func _set_lift(value: float) -> void:
	_lift = value
	_refresh()


func _set_flip(value: float) -> void:
	_flip = value
	_refresh()


## One place where visual state becomes transform and colour, so every setter
## above can be called in any order without fighting the others.
##
## A lifted card never needs a z_index bump: it rises into the row above, which
## has lower slot ids and is therefore already drawn behind it.
func _refresh() -> void:
	if texture != null:
		var source := texture.get_size()
		if source.x > 0.0 and source.y > 0.0:
			scale = (_rect.size / source) * Vector2(_flip, 1.0)

	# With centered = false a squeezed card would collapse towards its left
	# edge, so the inset keeps it turning about its own middle.
	var flip_inset := _rect.size.x * (1.0 - _flip) * 0.5
	position = _rect.position + Vector2(flip_inset, -_lift) + _offset

	if _selected:
		modulate = HIGHLIGHT
	elif _dimmed:
		modulate = DIM
	else:
		modulate = Color.WHITE
