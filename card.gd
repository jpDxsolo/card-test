extends Area2D

var dragging := false
var drag_offset := Vector2.ZERO

func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed \
	and not dragging:
		dragging = true
		drag_offset = global_position - get_global_mouse_position()
		z_index = 100  # float above the other card while held
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if dragging and event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and not event.pressed:
		dragging = false
		z_index = 0

func _process(_delta: float) -> void:
	if dragging:
		global_position = get_global_mouse_position() + drag_offset
