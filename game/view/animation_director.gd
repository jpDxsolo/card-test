class_name AnimationDirector
extends Node2D

## Serialises visual jobs so sequences cannot interleave into garbage (PLAN.md §8).
##
## The rule that makes this safe:
##
##     State commits immediately; the view catches up asynchronously.
##
## By the time any job here runs, RulesEngine has already changed the state and
## BoardView has already re-synced to it. Every card that flies across the screen
## is a throwaway ghost drawn on top of an already-correct board -- the board is
## never waiting on a tween to become right. That is what makes skip() safe to
## call at any moment, and why a dropped animation cannot desync anything.
##
## Lives beside BoardView rather than inside it: both sit at the origin with an
## identity transform, so they share a coordinate space, and being the later
## sibling puts every ghost above the board without z_index bookkeeping. Inside
## BoardView the ghosts would be destroyed by its _build().

signal idle

var tuning: Tuning

## Queue entries are {job: Callable, lock: bool}. The job returns the Tween to
## wait on, or null to continue immediately.
var _queue: Array[Dictionary] = []
var _running := false
var _current: Tween
var _ghosts: Array[CardNode] = []

## Counts queued-and-unfinished locking jobs rather than tracking the running
## one, so input is locked the instant a deal is queued -- not one frame later
## when it starts.
var _locks := 0


## True while a job that should swallow input is pending or running. Only the
## deal and the win sequence lock; everything else stays playable underneath,
## which is what stops the double-click desync the plan calls out.
func is_input_locked() -> bool:
	return _locks > 0


func is_busy() -> bool:
	return _running or not _queue.is_empty()


## Abandons everything in flight. Safe at any point precisely because the board
## is already correct -- this is the "skip animation" escape hatch.
func skip() -> void:
	_queue.clear()
	_locks = 0
	# Killing the running tween suppresses its finished signal, so no on_arrive
	# fires. Callers releasing what those callbacks would have released is the
	# point of BoardView.clear_holds().
	if _current != null and _current.is_valid():
		_current.kill()
	_current = null
	for ghost in _ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()
	_running = false
	idle.emit()


func enqueue(job: Callable, locks_input := false) -> void:
	_queue.append({"job": job, "lock": locks_input})
	if locks_input:
		_locks += 1
	if not _running:
		_pump()


## Both matched cards lift for a beat, then arc to the foundation and shrink.
## `cards` and `from` are parallel arrays; a single discard is just a one-card
## version of the same job, so Kings need no separate animation.
## `on_arrive` fires when the cards land, which is the caller's cue to let the
## destination pile show them (see BoardView.hold_foundation).
func fly_to_foundation(cards: Array[int], from: Array[Rect2], to: Rect2,
		on_arrive := Callable()) -> void:
	enqueue(func() -> Tween:
		var tween := create_tween()
		tween.set_parallel(true)
		for i in cards.size():
			var ghost := _ghost(cards[i], from[i])
			# Delay the flight by the pulse so the pair reads as a pair first.
			_arc_into(tween, ghost, from[i], _shrink(to, tuning.match_end_scale),
				tuning.match_flight_time, tuning.match_pulse_time)
		if on_arrive.is_valid():
			tween.finished.connect(on_arrive, CONNECT_ONE_SHOT)
		return tween)


## The drawn card turns over on its way from the stock to the waste.
func fly_stock_to_waste(card: int, from: Rect2, to: Rect2, on_arrive := Callable()) -> void:
	enqueue(func() -> Tween:
		var ghost := _ghost(Card.NONE, from)        # leaves the stock face down
		var tween := create_tween()
		tween.set_parallel(true)
		_arc_into(tween, ghost, from, to, tuning.draw_time, 0.0)
		tween.tween_callback(func() -> void:
			if is_instance_valid(ghost):
				ghost.flip_to(card, tuning.draw_time * 0.7)
		).set_delay(tuning.draw_time * 0.3)
		# The flip runs past the flight, so the waste waits for it to finish
		# rather than revealing the card while it is still edge-on.
		tween.tween_interval(tuning.draw_time * 1.1)
		if on_arrive.is_valid():
			tween.finished.connect(on_arrive, CONNECT_ONE_SHOT)
		return tween)


## The end-of-game flourish: cards sweep out of the foundation across the board.
## Capped by tuning.win_cards -- the foundation holds all 52 by now, and sending
## every one of them outlasts its welcome.
func win_cascade(cards: PackedInt32Array, from: Rect2, area: Rect2) -> void:
	if cards.is_empty():
		return
	var count := mini(cards.size(), tuning.win_cards)
	enqueue(func() -> Tween:
		var tween := create_tween()
		tween.set_parallel(true)
		for i in count:
			var card := cards[cards.size() - 1 - i]
			var ghost := _ghost(card, from)
			# Fan across the full width, alternating sides of the foundation.
			var spread := float(i) / maxf(float(count - 1), 1.0)
			var target := Rect2(
				Vector2(area.position.x + spread * maxf(area.size.x - from.size.x, 0.0),
					area.end.y - from.size.y * 0.5),
				from.size)
			_arc_into(tween, ghost, from, target, tuning.win_card_time, i * tuning.win_stagger)
			tween.tween_property(ghost, "self_modulate:a", 0.0, tuning.win_card_time * 0.5) \
				.set_delay(i * tuning.win_stagger + tuning.win_card_time * 0.5)
		return tween,
	true)


## Adds one arcing flight to `tween`, which must already be parallel. The ghost
## frees itself on arrival, so no job needs cleanup code of its own.
##
## The arc is a single hump: sin() is zero at both ends, so the card leaves and
## lands exactly on its rects however high it rises in between. Cards that
## travel in straight lines look dragged rather than thrown.
func _arc_into(tween: Tween, ghost: CardNode, from: Rect2, to: Rect2, time: float, delay: float) -> void:
	var lift := from.position.distance_to(to.position) * tuning.arc_height
	tween.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(ghost):
				return
			var pos := from.position.lerp(to.position, t)
			pos.y -= lift * sin(t * PI)
			ghost.place(Rect2(pos, from.size.lerp(to.size, t))),
		0.0, 1.0, time
	).set_delay(delay).set_trans(tuning.flight_trans).set_ease(tuning.flight_ease)

	tween.tween_callback(func() -> void:
		_ghosts.erase(ghost)
		if is_instance_valid(ghost):
			ghost.queue_free()
	).set_delay(delay + time)


## A throwaway card drawn above the board. Never consulted for anything: it
## exists for one flight and is freed.
func _ghost(card: int, rect: Rect2) -> CardNode:
	var node := CardNode.new()
	add_child(node)
	if card == Card.NONE:
		node.show_back()
	else:
		node.show_face(card)
	node.place(rect)
	_ghosts.append(node)
	return node


static func _shrink(rect: Rect2, factor: float) -> Rect2:
	var size := rect.size * factor
	return Rect2(rect.position + (rect.size - size) * 0.5, size)


## Deferred rather than recursive: a run of jobs that return null would
## otherwise nest one stack frame deeper each time.
func _pump() -> void:
	if _queue.is_empty():
		_running = false
		idle.emit()
		return

	_running = true
	var entry: Dictionary = _queue.pop_front()
	var tween: Tween = (entry["job"] as Callable).call()
	var release := func() -> void:
		if entry["lock"]:
			_locks = maxi(_locks - 1, 0)
		_current = null
		_pump()

	if tween == null or not tween.is_valid():
		release.call_deferred()
		return
	_current = tween
	tween.finished.connect(release, CONNECT_ONE_SHOT)
