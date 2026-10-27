extends VBoxContainer
signal track_requested(path: String)
var paths: Array[String] = []
var current_index: int = -1
var _list: ItemList

func _ready() -> void:
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 70
	_list.item_activated.connect(_activate)
	add_child(_list)
	var controls := HFlowContainer.new()
	add_child(controls)
	for label in ["Play selected", "Remove", "Clear"]:
		var button := Button.new()
		button.text = label
		controls.add_child(button)
	controls.get_child(0).pressed.connect(func() -> void:
		var selection: PackedInt32Array = _list.get_selected_items()
		if not selection.is_empty():
			_activate(selection[0]))
	controls.get_child(1).pressed.connect(_remove_selected)
	controls.get_child(2).pressed.connect(func() -> void:
		paths.clear()
		current_index = -1
		_list.clear())

func add_paths(incoming: PackedStringArray) -> void:
	for path in incoming:
		if path in paths or not path.get_extension().to_lower() in ["mp3", "ogg", "wav"] or not FileAccess.file_exists(path):
			continue
		paths.append(path)
		_list.add_item(path.get_file())
		_list.set_item_tooltip(paths.size() - 1, path)

func mark_playing(path: String) -> void:
	current_index = paths.find(path)
	if current_index >= 0:
		_list.select(current_index)
		_list.ensure_current_is_visible()

func play_next() -> void:
	if current_index + 1 < paths.size():
		_activate(current_index + 1)

func _activate(index: int) -> void:
	if index >= 0 and index < paths.size():
		track_requested.emit(paths[index])

func _remove_selected() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	paths.remove_at(index)
	_list.remove_item(index)
	if index < current_index:
		current_index -= 1
	elif index == current_index:
		current_index = index - 1
