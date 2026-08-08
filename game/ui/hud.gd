class_name Hud
extends CanvasLayer

## Score readout and the end-of-game banner.
##
## A CanvasLayer, so it sits in viewport space and is untouched by the board's
## scaling and centring. It reports; it decides nothing.
##
## Everything here is built in code rather than authored as a scene. There is no
## visual design to speak of yet -- M6 replaces this with real menus -- and code
## keeps it in one readable file until then.

signal new_game_requested

const MARGIN := 16
const BANNER_PAD := 28

## Lines of stats text to reserve room for. One is enough in landscape; the
## line wraps to two in a narrow portrait window, so reserve for the worst case
## rather than measuring after the fact and relaying out.
const RESERVED_LINES := 2

var _stats: Label
var _center: CenterContainer
var _banner: PanelContainer
var _banner_text: Label


func _ready() -> void:
	layer = 10
	_build()


## Vertical strip the board must keep clear. Derived from the font rather than
## from the label's measured size, so it is correct before the first layout pass
## and never changes underneath the board.
func reserved_height() -> float:
	var font := _stats.get_theme_font("font")
	var font_size := _stats.get_theme_font_size("font_size")
	return MARGIN * 2.0 + font.get_height(font_size) * RESERVED_LINES


func set_stats(cards_left: int, stock_left: int, waste_left: int, game_seed: int) -> void:
	_stats.text = "Cards %d     Stock %d     Waste %d     Seed %d     [R] new game" % [
		cards_left, stock_left, waste_left, game_seed
	]


func show_outcome(message: String) -> void:
	_banner_text.text = message
	_banner.visible = true


func hide_outcome() -> void:
	_banner.visible = false


func _build() -> void:
	_stats = Label.new()
	# Sits over the cards, so it needs an outline to stay readable on any card.
	_stats.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats.add_theme_constant_override("outline_size", 5)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Spans the top so the line wraps in portrait instead of running off-screen.
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stats)
	_stats.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, MARGIN
	)

	# A full-rect CenterContainer set to ignore the mouse: it centres the banner
	# without capturing clicks anywhere else on the board.
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_banner = PanelContainer.new()
	_banner.visible = false
	_center.add_child(_banner)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, BANNER_PAD)
	_banner.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	pad.add_child(box)

	_banner_text = Label.new()
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.add_theme_font_size_override("font_size", 28)
	box.add_child(_banner_text)

	var again := Button.new()
	again.text = "Deal again"
	again.pressed.connect(func() -> void: new_game_requested.emit())
	box.add_child(again)
