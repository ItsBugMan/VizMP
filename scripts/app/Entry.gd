extends Node
## Dispatch before constructing UI/visualizers. Preview never loads Main.
func _ready() -> void:
	_dispatch.call_deferred()

func _dispatch() -> void:
	match ScreensaverManager.launch_mode:
		ScreensaverManager.LaunchMode.PREVIEW:
			print("VizMP: HWND preview embedding is unavailable; exiting preview safely.")
			ScreensaverManager.request_exit()
		ScreensaverManager.LaunchMode.INVALID:
			push_warning("VizMP: Invalid screensaver arguments.")
			ScreensaverManager.request_exit(2)
		ScreensaverManager.LaunchMode.SAVER:
			get_tree().change_scene_to_file("res://scenes/Screensaver.tscn")
		ScreensaverManager.LaunchMode.CONFIG:
			var window: Window = get_tree().root
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			# A standalone /c process uses one OS window, with its modal inside.
			# The normal app keeps native subwindows for detachable panels.
			window.gui_embed_subwindows = true
			window.size = Vector2i(680, 680)
			window.current_screen = DisplayServer.get_primary_screen()
			var area: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
			window.position = area.position + (area.size - window.size) / 2
			window.title = "VizMP Screensaver Settings"
			ScreensaverManager.show_configuration(true)
		_:
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
