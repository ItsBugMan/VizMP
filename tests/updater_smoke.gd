extends SceneTree
var failures: int = 0
func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await process_frame
	var updater: Node = root.get_node("AutoUpdater")
	var installed_version: String = updater.local_version
	check(updater.version_parts(installed_version).size() == 3, "Bundled version configuration")
	for row in [["v1.10.0", "1.9.9", true], ["v2.0.0", "1.99.99", true], ["v1.0.0", "1.0.0", false], ["0.9.0", "1.0.0", false], ["v1.1.0-beta", "1.0.0", false], ["v01.2.3", "1.0.0", false], ["bad", "1.0.0", false]]:
		check(updater.is_newer(row[0], row[1]) == row[2], "Version ordering " + row[0])
	var digest := "sha256:" + "a".repeat(64)
	updater.local_version = "1.0.0"
	var asset := {"name": "VizMP_Windows_x64_v1.1.0.zip", "digest": digest, "size": 100, "browser_download_url": updater.RELEASES + "/download/v1.1.0/VizMP_Windows_x64_v1.1.0.zip"}
	var release := {"tag_name": "v1.1.0", "draft": false, "prerelease": false, "assets": [asset]}
	updater._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release).to_utf8_buffer())
	check(updater.state == updater.State.AVAILABLE, "Expected ZIP with GitHub digest accepted")
	asset.digest = ""
	updater._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release).to_utf8_buffer())
	check(updater.state == updater.State.IDLE, "Digest-less release rejected")
	asset.digest = digest
	asset.browser_download_url = "https://untrusted.example/update.zip"
	updater._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release).to_utf8_buffer())
	check(updater.state == updater.State.IDLE, "Unexpected download origin rejected")
	updater._checked(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
	check(updater.status.contains("No public release"), "No release is handled gracefully")
	updater.local_version = installed_version
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	await process_frame
	check(main._updates != null and main._update_status.text == updater.status, "Settings update dialog and status integration")
	main.queue_free()
	await process_frame
	print("Updater failures: ", failures)
	quit(failures)
