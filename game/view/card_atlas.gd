extends Node

## Slices the card sheet into AtlasTextures once at startup and caches them.
## Creating these per-frame would allocate garbage on every card draw.
##
## One flat cache covers every cell on the sheet; the semantic accessors
## (face / back / empty_slot) are just named lookups into it.

const DEFAULT_THEME := "res://data/themes/kenney_default.tres"

var theme: CardTheme

var _cells: Array[AtlasTexture] = []   # flat, row-major: row * COLUMNS + col

func _ready() -> void:
	load_theme(load(DEFAULT_THEME))

func load_theme(new_theme: CardTheme) -> void:
	assert(new_theme != null and new_theme.atlas != null, "CardTheme is missing its atlas")
	theme = new_theme
	_rebuild()

## Any cell on the sheet, by grid coordinate. For tooling and for the extras in
## column 13 (blank, back, jokers) that have no gameplay meaning.
func cell(col: int, row: int) -> AtlasTexture:
	return _cells[row * CardTheme.COLUMNS + col]

func face(card_id: int) -> AtlasTexture:
	return cell(Card.rank_of(card_id), Card.suit_of(card_id))

func back() -> AtlasTexture:
	return cell(theme.back_cell.x, theme.back_cell.y)

func empty_slot() -> AtlasTexture:
	return cell(theme.empty_slot_cell.x, theme.empty_slot_cell.y)

func _rebuild() -> void:
	_cells.resize(CardTheme.COLUMNS * CardTheme.ROWS)
	for row in CardTheme.ROWS:
		for col in CardTheme.COLUMNS:
			_cells[row * CardTheme.COLUMNS + col] = _slice(theme.cell_region(col, row))

func _slice(region: Rect2) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = theme.atlas
	tex.region = region
	tex.filter_clip = true
	return tex
