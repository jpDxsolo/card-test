extends Node2D

## M0 calibration harness: renders every cell of the sheet so the theme metrics
## can be verified by eye. Expected result is a 14 x 4 grid — hearts, diamonds,
## clubs, spades top to bottom, A to K left to right, with blank / back / red
## joker / black joker down the last column.

@export var zoom := 1.5
@export var gap := 6.0

func _ready() -> void:
	var cell := CardAtlas.theme.card_size() * zoom
	for row in CardTheme.ROWS:
		for col in CardTheme.COLUMNS:
			var sprite := Sprite2D.new()
			sprite.texture = _texture_at(col, row)
			sprite.centered = false
			sprite.scale = Vector2(zoom, zoom)
			sprite.position = Vector2(
				gap + col * (cell.x + gap),
				gap + row * (cell.y + gap),
			)
			add_child(sprite)

func _texture_at(col: int, row: int) -> Texture2D:
	if col < Card.RANKS_PER_SUIT:
		return CardAtlas.face(Card.make(row, col))   # exercises the real lookup path
	return CardAtlas.cell(col, row)                  # extras: blank, back, jokers
