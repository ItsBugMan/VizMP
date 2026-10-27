extends PanelContainer
signal detach_requested(panel_id: String)
signal dock_requested(panel_id: String, slot: int)
const HANDLE = preload("res://scripts/ui/DockHandle.gd")
var panel_id: String
var content: VBoxContainer
var _slot_menu: OptionButton
var _detach: Button

func setup(id: String, title: String) -> void:
	panel_id = id
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var chrome := preload("res://scripts/ui/SkinChrome.gd").new()
	column.add_child(chrome)
	var handle: Label = HANDLE.new()
	handle.panel_id = id
	handle.text = title.to_upper()
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.tooltip_text = "Drag onto another panel to swap. Drag a detached header to move its window."
	header.add_child(handle)
	_slot_menu = OptionButton.new()
	_slot_menu.tooltip_text = "Dock in this slot; swap with its current panel."
	for label in ["Upper left", "Lower left", "Upper right", "Lower center", "Lower right"]:
		_slot_menu.add_item(label)
	_slot_menu.item_selected.connect(func(slot: int) -> void: dock_requested.emit(panel_id, slot))
	header.add_child(_slot_menu)
	_detach = Button.new()
	_detach.text = "↗"
	_detach.tooltip_text = "Detach into a borderless window"
	_detach.pressed.connect(func() -> void: detach_requested.emit(panel_id))
	header.add_child(_detach)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

func update_location(slot: int, detached: bool) -> void:
	_slot_menu.select(slot)
	_detach.text = "↙" if detached else "↗"
	_detach.tooltip_text = "Return to dock" if detached else "Detach into a borderless window"
