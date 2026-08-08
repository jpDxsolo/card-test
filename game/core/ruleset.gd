class_name Ruleset
extends Resource

## The variant config. Every field here exists to express at least one
## documented Pyramid variant (PLAN.md §5).
##
## Fields are declared in full, but only classic Pyramid is wired up. Unused
## data is harmless; unused branching logic is not. Nothing in this file
## branches -- it is pure data.

enum Shape { PYRAMID, TRIANGLE, GIZA }
enum DeckType { STANDARD_52, SPANISH_48 }
enum FillSource { NONE, TABLEAU, WASTE, BOTH }
enum WinCondition { CLEAR_ALL, CLEAR_TABLEAU }

@export_group("Deck")
@export var deck_composition: DeckType = DeckType.STANDARD_52
@export var target_sum: int = 13            ## 12 for a Spanish deck
@export var single_discard_value: int = 13  ## Kings go to the foundation alone

@export_group("Tableau")
@export var tableau_shape: Shape = Shape.PYRAMID
@export var tableau_rows: int = 7
@export var reserve_count: int = 0          ## 6 or 7 for the reserve variant
@export var extra_columns: int = 0          ## Giza: 8
@export var extra_column_depth: int = 0     ## Giza: 3

@export_group("Stock and Waste")
@export var stock_face_up: bool = false     ## true = MS Solitaire Collection style
@export var draw_count: int = 1             ## 3 for Tut's Tomb
@export var waste_pile_count: int = 1       ## 3 for Apophis
@export var redeals_allowed: int = 0        ## 2 for Par Pyramid, -1 = unlimited

@export_group("Matching")
@export var allow_covering_pair: bool = false  ## Ace on Queen removable together
@export var cell_count: int = 0
@export var cell_fill_from: FillSource = FillSource.NONE

@export_group("Win and Score")
@export var win_condition: WinCondition = WinCondition.CLEAR_ALL
