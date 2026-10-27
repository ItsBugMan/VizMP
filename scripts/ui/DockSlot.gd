extends VBoxContainer
signal panel_dropped(panel_id: String, slot: int)
var slot_index: int

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("vizmp_panel") is String

func _drop_data(_position: Vector2, data: Variant) -> void:
	panel_dropped.emit(data.vizmp_panel, slot_index)
