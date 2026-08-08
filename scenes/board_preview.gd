extends Node2D

## M2 checkpoint: deal a board and render it.
##
## No input yet -- clicking does nothing until M3 wires GameController in. What
## this proves is that the layout maths, the atlas and the state model agree:
## a dealt pyramid appears, the bottom row reads bright and everything above it
## dim, and resizing the window keeps it correct in both orientations.

const CLASSIC := "res://data/rulesets/classic_pyramid.tres"

@export var deal_seed := 12345

var _board: BoardView


func _ready() -> void:
	var rules := load(CLASSIC) as Ruleset
	var graph := SlotGraph.new(rules)
	var state := RulesEngine.deal(rules, graph, deal_seed)

	_board = BoardView.new()
	add_child(_board)              # must be in the tree before setup(): it reads the viewport
	_board.setup(graph, rules)
	_board.sync_to_state(state)
