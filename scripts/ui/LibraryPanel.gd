extends VBoxContainer
const AUDIO_LOADER = preload("res://scripts/audio/AudioStreamLoader.gd")
signal track_requested(path: String)
signal queue_requested(paths: PackedStringArray)
var folders := PackedStringArray()
var _pending: Array[String] = []
var _visited: Dictionary = {}
var _paths: Dictionary = {}
var _tree: Tree
var _roots: ItemList
var _status: Label
var _dialog: FileDialog

func _ready() -> void:
	var row := HFlowContainer.new()
	add_child(row)
	for title in ["Add folder", "Remove folder", "Rescan", "Queue all"]:
		var button := Button.new()
		button.text = title
		row.add_child(button)
	row.get_child(0).pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.7))
	row.get_child(1).pressed.connect(_remove_folder)
	row.get_child(2).pressed.connect(scan)
	row.get_child(3).pressed.connect(func() -> void: queue_requested.emit(PackedStringArray(_paths.keys())))
	_roots = ItemList.new()
	_roots.custom_minimum_size.y = 48
	add_child(_roots)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.custom_minimum_size.y = 90
	_tree.item_activated.connect(func() -> void:
		var item := _tree.get_selected()
		if item != null and item.get_metadata(0) is String: track_requested.emit(item.get_metadata(0)))
	add_child(_tree)
	_status = Label.new()
	add_child(_status)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.dir_selected.connect(add_folder)
	add_child(_dialog)
	var config := ConfigFile.new()
	if config.load("user://library.cfg") == OK:
		folders = PackedStringArray(config.get_value("library", "folders", PackedStringArray()))
	_refresh_roots()
	scan()

func add_folder(path: String) -> void:
	path = path.simplify_path()
	if not DirAccess.dir_exists_absolute(path) or path in folders: return
	folders.append(path)
	_save()

func _remove_folder() -> void:
	var selected := _roots.get_selected_items()
	if selected.is_empty(): return
	folders.remove_at(selected[0])
	_save()

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("library", "folders", folders)
	config.save("user://library.cfg")
	_refresh_roots()
	scan()

func _refresh_roots() -> void:
	_roots.clear()
	for path in folders: _roots.add_item(path)

func scan() -> void:
	if _directory != null: _directory.list_dir_end()
	_directory = null
	_pending.assign(Array(folders))
	_visited.clear()
	_paths.clear()
	_tree.clear()
	_tree.create_item()
	set_process(true)

func _process(_delta: float) -> void:
	var deadline := Time.get_ticks_usec() + 2500
	# Keep an open directory across frames, avoiding a blocking recursive traversal.
	while Time.get_ticks_usec() < deadline:
		if _directory == null:
			if _pending.is_empty():
				_status.text = "%d tracks" % _paths.size()
				set_process(false)
				return
			_directory_path = _pending.pop_back()
			if _visited.has(_directory_path): continue
			_visited[_directory_path] = true
			_directory = DirAccess.open(_directory_path)
			if _directory == null: continue
			_directory.list_dir_begin()
		var file := _directory.get_next()
		if file.is_empty():
			_directory.list_dir_end()
			_directory = null
			continue
		var path := _directory_path.path_join(file)
		if _directory.is_link(file): continue
		if _directory.current_is_dir():
			if not file.begins_with("."): _pending.append(path)
		elif AUDIO_LOADER.supports(file) and not _paths.has(path):
			_paths[path] = true
			var item := _tree.create_item(_tree.get_root())
			item.set_text(0, file.get_basename())
			item.set_tooltip_text(0, path)
			item.set_metadata(0, path)
	_status.text = "Scanning · %d tracks" % _paths.size()

var _directory: DirAccess
var _directory_path := ""
