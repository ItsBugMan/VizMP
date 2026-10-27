extends Label
## Docked headers support Godot drag/drop; detached headers drag native windows.
var panel_id: String

func _get_drag_data(_position: Vector2) -> Variant:
	if get_window() != get_tree().root:
		return null
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"vizmp_panel": panel_id}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if get_window() != get_tree().root:
			get_window().start_drag()
