extends AcceptDialog
## Lives in the normal desktop UI, never in a screensaver session.
var _status: Label
var _progress: ProgressBar
var _check: Button
var _download: Button
var _install: Button

func _ready() -> void:
	title = "VizMP updates"
	min_size = Vector2i(520, 250)
	var box := VBoxContainer.new()
	add_child(box)
	var version := Label.new()
	version.text = "Installed version: " + AutoUpdater.local_version
	box.add_child(version)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(480, 70)
	box.add_child(_status)
	_progress = ProgressBar.new()
	box.add_child(_progress)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_check = Button.new()
	_check.text = "Check for updates"
	_check.pressed.connect(AutoUpdater.check_for_updates)
	buttons.add_child(_check)
	_download = Button.new()
	_download.text = "Download update"
	_download.pressed.connect(AutoUpdater.download_update)
	buttons.add_child(_download)
	_install = Button.new()
	_install.text = "Restart and install"
	_install.pressed.connect(AutoUpdater.apply_update)
	buttons.add_child(_install)
	var releases := LinkButton.new()
	releases.text = "View GitHub releases"
	releases.pressed.connect(func() -> void: OS.shell_open(AutoUpdater.RELEASES))
	box.add_child(releases)
	AutoUpdater.status_changed.connect(func(_message: String) -> void: _refresh())
	AutoUpdater.state_changed.connect(_refresh)
	AutoUpdater.progress_changed.connect(func(downloaded: int, total: int) -> void:
		_progress.value = 100.0 * downloaded / maxi(total, 1))
	SkinManager.register_root(self)
	_refresh()

func _refresh() -> void:
	_status.text = AutoUpdater.status
	_check.disabled = AutoUpdater.state not in [AutoUpdater.State.IDLE, AutoUpdater.State.AVAILABLE, AutoUpdater.State.READY]
	_download.disabled = AutoUpdater.state != AutoUpdater.State.AVAILABLE
	_install.disabled = AutoUpdater.state != AutoUpdater.State.READY
	_progress.visible = AutoUpdater.state == AutoUpdater.State.DOWNLOADING

func _exit_tree() -> void:
	SkinManager.unregister_root(self)
