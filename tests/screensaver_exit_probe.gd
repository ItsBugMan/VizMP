extends SceneTree
## Check the real _input -> SceneTree.quit path in an isolated process.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var manager: Node = root.get_node("ScreensaverManager")
	manager.begin_session(false)
	manager._clock = 0.6
	manager.exit_requested.connect(func() -> void: print("PASS: Screensaver input requested immediate shutdown"))
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	manager._input(key)
	# If shutdown failed, a later frame fails the probe instead of hanging.
	await process_frame
	push_error("Screensaver input failed to quit the scene tree.")
	quit(1)
