extends MarginContainer
signal panel_detached(panel_id: String, window: Window)
## Fixed split tree with movable panel occupants and native detached windows.
const PANEL = preload("res://scripts/ui/DockPanel.gd")
const SLOT = preload("res://scripts/ui/DockSlot.gd")
const DEFAULT_ORDER: Array[String] = ["deck", "equalizer", "visualizer", "playlist", "library"]
var persistence_enabled: bool = true
var layout_path: String = "user://layout.cfg"
var panels: Dictionary = {}
var windows: Dictionary = {}
var order: Array[String] = DEFAULT_ORDER.duplicate()
var _slots: Array[VBoxContainer] = []
var _horizontal: HSplitContainer
var _left: VSplitContainer
var _right: VSplitContainer
var _last_saved: String = ""
var _lower: HSplitContainer
var hidden_panels: Dictionary = {}

func set_panel_visible(id: String, enabled: bool) -> void:
	if not panels.has(id): return
	if enabled: hidden_panels.erase(id)
	else: hidden_panels[id] = true
	_refresh_visibility()

func _refresh_visibility() -> void:
	for id in panels:
		panels[id].visible = not hidden_panels.has(id)
		if windows.has(id): windows[id].visible = not hidden_panels.has(id)
	for i in range(_slots.size()):
		_slots[i].visible = not hidden_panels.has(order[i]) and not windows.has(order[i])
	_left.visible = _slots[0].visible or _slots[1].visible
	_lower.visible = _slots[3].visible or _slots[4].visible
	_right.visible = _slots[2].visible or _lower.visible

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, 12)
	_horizontal = HSplitContainer.new()
	_horizontal.split_offset = -220
	add_child(_horizontal)
	_left = VSplitContainer.new()
	_left.split_offset = -50
	_right = VSplitContainer.new()
	_right.split_offset = 160
	_horizontal.add_child(_left)
	_horizontal.add_child(_right)
	var lower := HSplitContainer.new()
	_lower = lower
	_right.add_child(lower)
	for i in range(DEFAULT_ORDER.size()):
		var slot: VBoxContainer = SLOT.new()
		slot.slot_index = i
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2(270, 150)
		slot.panel_dropped.connect(dock_panel)
		_slots.append(slot)
		if i < 2: _left.add_child(slot)
		elif i == 2:
			_right.add_child(slot)
			_right.move_child(slot, 0)
		else: lower.add_child(slot)
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(save_layout)
	add_child(timer)

func add_panel(id: String, title: String) -> VBoxContainer:
	var panel: PanelContainer = PANEL.new()
	panel.name = id.capitalize().replace(" ", "") + "Panel"
	panel.setup(id, title)
	panel.detach_requested.connect(toggle_detached)
	panel.dock_requested.connect(dock_panel)
	panels[id] = panel
	_slots[order.find(id)].add_child(panel)
	panel.update_location(order.find(id), false)
	return panel.content

func dock_panel(id: String, slot: int) -> void:
	if not panels.has(id) or slot < 0 or slot >= DEFAULT_ORDER.size():
		return
	var source: int = order.find(id)
	if windows.has(id):
		var window: Window = windows[id]
		window.hide()
		panels[id].reparent(_slots[source], false)
		SkinManager.unregister_root(window)
		windows.erase(id)
		window.queue_free()
	var displaced: String = order[slot]
	order[slot] = id
	order[source] = displaced
	for i in range(DEFAULT_ORDER.size()):
		var panel: Control = panels[order[i]]
		if not windows.has(order[i]) and panel.get_parent() != _slots[i]:
			panel.reparent(_slots[i], false)
		panel.update_location(i, windows.has(order[i]))
	_refresh_visibility()
	save_layout()

func toggle_detached(id: String) -> void:
	if windows.has(id):
		dock_panel(id, order.find(id))
	else:
		detach_panel(id)

func detach_panel(id: String, rectangle: Rect2i = Rect2i()) -> void:
	if not panels.has(id) or windows.has(id):
		return
	var panel: Control = panels[id]
	var window := Window.new()
	window.title = "VizMP / " + id.capitalize()
	window.borderless = true
	window.transparent = true
	window.transparent_bg = true
	window.transient = true
	window.min_size = Vector2i(panel.get_combined_minimum_size().ceil()).max(Vector2i(300, 220))
	window.size = Vector2i(maxi(420, int(panel.size.x)), maxi(280, int(panel.size.y)))
	window.position = get_tree().root.position + Vector2i(60, 60)
	if rectangle.has_area():
		window.size = rectangle.size
		window.position = rectangle.position
	_clamp_window(window)
	add_child(window)
	windows[id] = window
	panel.reparent(window, false)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.update_location(order.find(id), true)
	window.close_requested.connect(func() -> void: dock_panel(id, order.find(id)))
	SkinManager.register_root(window)
	var grip := Button.new()
	grip.text = "◢"
	grip.tooltip_text = "Drag to resize window"
	grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.position = Vector2(-30, -30)
	grip.size = Vector2(28, 28)
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			DisplayServer.window_start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, window.get_window_id()))
	window.add_child(grip)
	window.show()
	_refresh_visibility()
	panel_detached.emit(id, window)
	save_layout()

func _clamp_window(window: Window) -> void:
	var screen: int = DisplayServer.get_screen_from_rect(Rect2i(window.position, window.size))
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var area: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if not area.has_area():
		return
	window.size = Vector2i(clampi(window.size.x, 300, maxi(300, area.size.x)), clampi(window.size.y, 220, maxi(220, area.size.y)))
	window.position = Vector2i(clampi(window.position.x, area.position.x, maxi(area.position.x, area.end.x - window.size.x)),
		clampi(window.position.y, area.position.y, maxi(area.position.y, area.end.y - window.size.y)))

func save_layout() -> void:
	if not persistence_enabled or panels.size() != DEFAULT_ORDER.size():
		return
	var config := ConfigFile.new()
	config.set_value("layout", "version", 1)
	config.set_value("layout", "lower_split", _lower.split_offset)
	config.set_value("layout", "order", order)
	config.set_value("layout", "splits", Vector3i(_horizontal.split_offset, _left.split_offset, _right.split_offset))
	for id in windows:
		var window: Window = windows[id]
		config.set_value("windows", id, Rect2i(window.position, window.size))
	var encoded: String = config.encode_to_text()
	if encoded != _last_saved and config.save(layout_path) == OK:
		_last_saved = encoded

func restore_layout() -> void:
	if not persistence_enabled:
		return
	var config := ConfigFile.new()
	if config.load(layout_path) != OK or config.get_value("layout", "version", 0) != 1:
		return
	var saved: Variant = config.get_value("layout", "order", [])
	if saved is Array and saved.size() == 4 and not saved.has("library"):
		saved.append("library")
	if saved is Array and saved.size() == DEFAULT_ORDER.size():
		var valid: bool = true
		for id in DEFAULT_ORDER:
			valid = valid and saved.count(id) == 1
		if valid:
			for i in range(DEFAULT_ORDER.size()):
				dock_panel(str(saved[i]), i)
	var splits: Variant = config.get_value("layout", "splits", null)
	if splits is Vector3i:
		_horizontal.split_offset = clampi(splits.x, -2000, 2000)
		_left.split_offset = clampi(splits.y, -2000, 2000)
		_right.split_offset = clampi(splits.z, -2000, 2000)
	_lower.split_offset = clampi(int(config.get_value("layout", "lower_split", 0)), -2000, 2000)
	for id in DEFAULT_ORDER:
		var rectangle: Variant = config.get_value("windows", id, Rect2i())
		if rectangle is Rect2i and rectangle.has_area():
			detach_panel(id, rectangle)

func reset_layout() -> void:
	for i in range(DEFAULT_ORDER.size()):
		dock_panel(DEFAULT_ORDER[i], i)
	_horizontal.split_offset = -220
	_left.split_offset = -50
	_right.split_offset = 160
	_lower.split_offset = 0
	save_layout()
