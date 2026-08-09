class_name Tuning
extends Resource

## Every animation duration and curve in one place (PLAN.md §8).
##
## Game feel is found by iteration, and iteration is only pleasant when the
## numbers live somewhere you can change without reading code. Like Ruleset,
## this is pure data: nothing here branches, and nothing here knows what a card
## is. Anything that reads a duration reads it from an instance of this.

@export_group("Deal")
## Flight time for one card. Every card takes this long; they differ only in
## when they start.
@export var deal_card_time := 0.38
## Gap between one card leaving the stock and the next. 28 cards at 0.05, plus
## the last card's flight and flip, puts the whole deal a little under two
## seconds -- unhurried enough to watch, short enough not to sit through.
@export var deal_stagger := 0.05

@export_group("Match")
## A beat where both cards sit highlighted before they leave, so the player sees
## which pair was taken rather than just watching two cards vanish.
@export var match_pulse_time := 0.10
@export var match_flight_time := 0.40
## Cards shrink slightly on the way to the foundation, which reads as distance.
@export var match_end_scale := 0.78

@export_group("Draw")
@export var draw_time := 0.22

@export_group("Feedback")
@export var select_time := 0.08
@export var invalid_time := 0.15
## Shake amplitude as a fraction of a card width, so it scales with the board.
@export var invalid_shake := 0.10

@export_group("Win")
@export var win_card_time := 0.45
@export var win_stagger := 0.06
## Cards in the winning cascade. The foundation holds 52 by then; sweeping all
## of them outlasts its welcome.
@export var win_cards := 12

@export_group("Curves")
## Height of a flight's arc as a fraction of the distance travelled. Cards that
## travel in straight lines look like they are being dragged, not thrown.
@export var arc_height := 0.18
@export var flight_trans: Tween.TransitionType = Tween.TRANS_QUAD
@export var flight_ease: Tween.EaseType = Tween.EASE_OUT
