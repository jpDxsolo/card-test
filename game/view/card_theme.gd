class_name CardTheme
extends Resource


const COLUMNS := 14
const ROWS := 4

@export var atlas: Texture2D

@export_group("Sheet Grid")
@export var cell_size := Vector2i(64, 64)
@export var margin := Vector2i(0, 0)
@export var spacing := Vector2i(1, 1)

@export var card_rect := Rect2i(11, 2, 42, 60)

@export_group("Special Cells")
@export var back_cell := Vector2i(13, 1)
@export var empty_slot_cell := Vector2i(13, 0)

func card_size() -> Vector2:
	return Vector2(card_rect.size)
	
func cell_region(col: int, row: int) -> Rect2:
	var cell_origin := Vector2(
		margin.x + col * (cell_size.x + spacing.x),
		margin.y + row * (cell_size.y + spacing.y)
	)
	return Rect2(cell_origin + Vector2(card_rect.position), Vector2(card_rect.size))
