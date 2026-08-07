class_name CardTheme
extends Resource

## Describes how a card sheet is laid out. All texture addressing in the game
## goes through here, so swapping art packs is a .tres change, not a code change.
##
## Defaults below are the measured metrics for the Kenney sheet in assets/cards.
## A theme for different art must override every one of them — see PLAN.md §6.

const COLUMNS := 14
const ROWS := 4

@export var atlas: Texture2D

@export_group("Sheet Grid")
@export var cell_size := Vector2i(64, 64)
@export var margin := Vector2i(0, 0)
@export var spacing := Vector2i(1, 1)

## The visible artwork within each cell. Kenney pads every 64x64 cell with
## transparent space; we trim to the art so that layout distances and click
## targets refer to the card the player can actually see.
@export var card_rect := Rect2i(11, 2, 42, 60)

@export_group("Special Cells")
@export var back_cell := Vector2i(13, 1)
@export var empty_slot_cell := Vector2i(13, 0)


## Source-pixel size of a card. This is the unit LayoutResolver works in.
func card_size() -> Vector2:
	return Vector2(card_rect.size)


func cell_region(col: int, row: int) -> Rect2:
	var cell_origin := Vector2(
		margin.x + col * (cell_size.x + spacing.x),
		margin.y + row * (cell_size.y + spacing.y)
	)
	return Rect2(cell_origin + Vector2(card_rect.position), Vector2(card_rect.size))
