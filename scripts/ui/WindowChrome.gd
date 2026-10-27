extends Control
## Native window movement keeps snapping and multi-monitor behavior intact.
signal close_requested
var bar: PanelContainer
var grip: Button
var maximize: Button
var _restore_rect := Rect2i(100, 100, 1280, 800)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar = PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size.y = 38
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color("#101117")
	rail.border_color = Color("#625b6f")
	rail.border_width_bottom = 1
	rail.set_content_margin_all(4)
	bar.add_theme_stylebox_override("panel", rail)
	add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var title := Label.new()
	title.text = "  VIZMP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.tooltip_text = "Drag to move · Double-click to maximize · F10 restores window borders"
	title.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click: toggle_maximized()
			else: get_window().start_drag())
	row.add_child(title)
	for caption in ["—", "□", "×"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(42, 28)
		row.add_child(button)
		match caption:
			"—":
				button.tooltip_text = "Minimize"
				button.pressed.connect(func() -> void: get_window().mode = Window.MODE_MINIMIZED)
			"□":
				maximize = button
				button.tooltip_text = "Maximize / restore"
				button.pressed.connect(toggle_maximized)
			"×":
				button.tooltip_text = "Close player"
				button.pressed.connect(func() -> void: close_requested.emit())
	grip = Button.new()
	grip.text = "◢"
	grip.tooltip_text = "Drag to resize"
	grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.position = Vector2(-28, -28)
	grip.size = Vector2(28, 28)
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			DisplayServer.window_start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, get_window().get_window_id()))
	add_child(grip)

func _usable_rect() -> Rect2i:
	return DisplayServer.screen_get_usable_rect(get_window().current_screen)

func is_maximized() -> bool:
	var window := get_window()
	return window.mode == Window.MODE_MAXIMIZED or (window.borderless and Rect2i(window.position, window.size) == _usable_rect())

func toggle_maximized() -> void:
	var window := get_window()
	if not window.borderless:
		window.mode = Window.MODE_WINDOWED if is_maximized() else Window.MODE_MAXIMIZED
		return
	# Windows may report a borderless maximize as WINDOWED. Use the usable
	# desktop rectangle, which also keeps the taskbar and restore size intact.
	if is_maximized():
		window.mode = Window.MODE_WINDOWED
		window.size = _restore_rect.size
		window.position = _restore_rect.position
	else:
		_restore_rect = Rect2i(window.position, window.size)
		window.mode = Window.MODE_WINDOWED
		var area: Rect2i = _usable_rect()
		if area.has_area():
			window.position = area.position
			window.size = area.size

func _process(_delta: float) -> void:
	grip.visible = get_window().mode == Window.MODE_WINDOWED and not is_maximized()
	maximize.text = "❐" if is_maximized() else "□"
