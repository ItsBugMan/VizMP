extends SceneTree
## Used to check actual Godot handling of raw Windows slash arguments.
func _initialize() -> void:
	_report.call_deferred()

func _report() -> void:
	var manager: Node = root.get_node("ScreensaverManager")
	print("SCREENSAVER_MODE=", manager.launch_mode, "; HWND=", manager.parent_handle)
	quit()
