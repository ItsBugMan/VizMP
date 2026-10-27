extends Node
## Public stable releases only. Downloads never install without a button press.
signal status_changed(message: String)
signal update_available(version: String)
signal progress_changed(downloaded: int, total: int)
signal state_changed
signal restarting

const API := "https://api.github.com/repos/ItsBugMan/VizMP/releases/latest"
const RELEASES := "https://github.com/ItsBugMan/VizMP/releases"
const UPDATE_DIR := "user://updates"
const MAX_DOWNLOAD := 536870912
enum State { IDLE, CHECKING, AVAILABLE, DOWNLOADING, STAGING, READY, HANDOFF }
var state: State = State.IDLE
var status: String = "Updates have not been checked."
var local_version: String = "0.0.0"
var remote_version: String = ""
var _asset: Dictionary = {}
var _api: HTTPRequest
var _download: HTTPRequest
var _worker_pid: int = -1
var _handoff_elapsed: float = 0.0
var _session_dir: String

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("res://version.cfg") == OK:
		local_version = str(config.get_value("application", "version", "0.0.0"))
	_api = HTTPRequest.new()
	_api.use_threads = true
	_api.timeout = 20.0
	_api.body_size_limit = 2097152
	add_child(_api)
	_api.request_completed.connect(_checked)
	_download = HTTPRequest.new()
	_download.use_threads = true
	_download.timeout = 600.0
	_download.body_size_limit = MAX_DOWNLOAD
	add_child(_download)
	_download.request_completed.connect(_downloaded)
	set_process(false)
	if OS.has_feature("template") and ScreensaverManager.launch_mode == ScreensaverManager.LaunchMode.APP:
		check_for_updates.call_deferred()

static func version_parts(value: String) -> PackedInt64Array:
	# Stable SemVer only: prereleases are deliberately outside this channel.
	var regex := RegEx.new()
	regex.compile("^v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
	var found := regex.search(value)
	if found == null:
		return PackedInt64Array()
	return PackedInt64Array([found.get_string(1).to_int(), found.get_string(2).to_int(), found.get_string(3).to_int()])

static func is_newer(remote: String, local: String) -> bool:
	var a := version_parts(remote)
	var b := version_parts(local)
	if a.size() != 3 or b.size() != 3:
		return false
	for i in range(3):
		if a[i] != b[i]:
			return a[i] > b[i]
	return false

func _set_state(next: State, message: String) -> void:
	state = next
	status = message
	status_changed.emit(message)
	state_changed.emit()

func check_for_updates() -> void:
	if state not in [State.IDLE, State.AVAILABLE, State.READY]:
		return
	_asset.clear()
	_set_state(State.CHECKING, "Checking GitHub releases…")
	var error := _api.request(API, PackedStringArray([
		"Accept: application/vnd.github+json", "User-Agent: VizMP/" + local_version,
		"X-GitHub-Api-Version: 2022-11-28"]))
	if error != OK:
		_fail("Could not start the update check: " + error_string(error))

func _checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("No public release is available yet." if code == 404 else "Update check failed (HTTP %d). Try again later." % code)
		return
	var release: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not release is Dictionary or not release.get("assets") is Array:
		_fail("GitHub returned invalid release metadata.")
		return
	if release.get("draft", true) or release.get("prerelease", true):
		_fail("No stable release is available.")
		return
	remote_version = str(release.get("tag_name", ""))
	if version_parts(remote_version).is_empty():
		_fail("Release tag must use vMAJOR.MINOR.PATCH.")
		return
	if not is_newer(remote_version, local_version):
		_set_state(State.IDLE, "VizMP %s is up to date." % local_version)
		return
	var expected := "VizMP_Windows_x64_v%s.zip" % remote_version.trim_prefix("v")
	for candidate: Variant in release.assets:
		if not candidate is Dictionary or candidate.get("name") != expected:
			continue
		var url := str(candidate.get("browser_download_url", ""))
		var digest := str(candidate.get("digest", ""))
		var digest_regex := RegEx.new()
		digest_regex.compile("^sha256:[0-9a-fA-F]{64}$")
		if not url.begins_with(RELEASES + "/download/" + remote_version + "/") or digest_regex.search(digest) == null:
			continue
		var size := int(candidate.get("size", 0))
		if size <= 0 or size > MAX_DOWNLOAD:
			continue
		_asset = candidate.duplicate()
		_set_state(State.AVAILABLE, "VizMP %s is available." % remote_version)
		update_available.emit(remote_version)
		return
	_fail("New release found, but its Windows ZIP or SHA-256 digest is missing.")

func download_update() -> void:
	if state != State.AVAILABLE:
		return
	if OS.get_name() != "Windows":
		_fail("Automatic installation is available on Windows.")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_DIR))
	_download.download_file = UPDATE_DIR + "/new_build.zip"
	_set_state(State.DOWNLOADING, "Downloading %s…" % remote_version)
	set_process(true)
	var error := _download.request(str(_asset.browser_download_url), PackedStringArray(["User-Agent: VizMP/" + local_version]))
	if error != OK:
		_fail("Could not start the download: " + error_string(error))

func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Download failed (HTTP %d). Check your connection and retry." % code)
		return
	_session_dir = ProjectSettings.globalize_path(UPDATE_DIR).path_join("session-" + str(Time.get_unix_time_from_system()).replace(".", "-") + "-" + str(OS.get_process_id()))
	if DirAccess.make_dir_recursive_absolute(_session_dir) != OK:
		_fail("Could not create update staging folder.")
		return
	var helper := FileAccess.open(_session_dir.path_join("UpdateHelper.ps1"), FileAccess.WRITE)
	if helper == null:
		_fail("Could not write the update helper.")
		return
	helper.store_string(FileAccess.get_file_as_string("res://scripts/packaging/UpdateHelper.ps1"))
	helper.close()
	var plan := {
		"zip": ProjectSettings.globalize_path(UPDATE_DIR + "/new_build.zip"),
		"sha256": str(_asset.digest).trim_prefix("sha256:"), "size": int(_asset.size),
		"version": remote_version.trim_prefix("v"), "install": OS.get_executable_path().get_base_dir(),
		"pid": OS.get_process_id(), "session": _session_dir,
	}
	var file := FileAccess.open(_session_dir.path_join("plan.json"), FileAccess.WRITE)
	if file == null:
		_fail("Could not write the update plan.")
		return
	file.store_string(JSON.stringify(plan))
	file.close()
	_set_state(State.STAGING, "Verifying checksum and staging update…")
	_worker_pid = _launch_powershell(_helper_command("Prepare"))
	if _worker_pid < 0:
		_fail("Could not start Windows PowerShell.")

static func _ps_literal(value: String) -> String:
	return "'" + value.replace("'", "''") + "'"

func _helper_command(action: String) -> String:
	return "& %s -Action %s -PlanPath %s" % [_ps_literal(_session_dir.path_join("UpdateHelper.ps1")), action, _ps_literal(_session_dir.path_join("plan.json"))]

static func _encoded(command: String) -> String:
	return Marshalls.raw_to_base64(command.to_utf16_buffer())

static func _launch_powershell(command: String) -> int:
	return OS.create_process("powershell.exe", PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-EncodedCommand", _encoded(command)]))

func apply_update() -> void:
	if state != State.READY:
		return
	if not OS.has_feature("template") or OS.get_executable_path().get_file().to_lower() != "vizmp.exe":
		status = "Install updates from an exported VizMP.exe; editor and screensaver sessions cannot be replaced."
		status_changed.emit(status)
		return
	var batch_path := ProjectSettings.globalize_path(UPDATE_DIR + "/apply_update.bat")
	var file := FileAccess.open(batch_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write update handoff.")
		return
	# No filesystem paths are interpolated into cmd syntax. PowerShell receives UTF-16 Base64.
	file.store_string("@echo off\r\ntimeout /t 2 /nobreak > nul\r\npowershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand " + _encoded(_helper_command("Apply")) + "\r\ndel \"%~f0\"\r\n")
	file.close()
	_set_state(State.HANDOFF, "Preparing restart; approve Windows elevation if requested…")
	_handoff_elapsed = 0.0
	_worker_pid = _launch_powershell("& " + _ps_literal(batch_path))
	set_process(true)
	if _worker_pid < 0:
		_fail("Could not launch update handoff.")

func _process(delta: float) -> void:
	if state == State.DOWNLOADING:
		progress_changed.emit(_download.get_downloaded_bytes(), int(_asset.size))
	elif state == State.STAGING or state == State.HANDOFF:
		var failure := _session_dir.path_join("failed.txt")
		if FileAccess.file_exists(failure):
			_fail(FileAccess.get_file_as_string(failure).left(1000))
			return
		if state == State.STAGING and not OS.is_process_running(_worker_pid):
			if FileAccess.file_exists(_session_dir.path_join("prepared.json")):
				_set_state(State.READY, "Update verified. Restart VizMP to install %s." % remote_version)
				set_process(false)
			else:
				_fail("Staging failed. Check user://updates for details.")
		elif state == State.HANDOFF:
			_handoff_elapsed += delta
			if FileAccess.file_exists(_session_dir.path_join("ready.txt")):
				restarting.emit()
				get_tree().quit()
			elif _handoff_elapsed > 120.0:
				_fail("Update handoff timed out; VizMP remains open. Check updates/failed.txt.")

func _fail(message: String) -> void:
	set_process(false)
	_set_state(State.IDLE, message)
