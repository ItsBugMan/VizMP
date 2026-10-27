extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
 print("PASS: " if ok else "FAIL: ", label)
 if not ok: failures += 1
func run() -> void:
 await process_frame
 var skins: Node = root.get_node("SkinManager")
 var original: String = skins.current_path
 check(skins.BUILTINS.size() == 14, "Eight illustrated skins plus six classic themes")
 var illustrated: int = 0
 for path in skins.BUILTINS:
  check(skins.load_skin(path, false) == OK, "Manifest and referenced assets load: " + path.get_file())
  if skins.chrome.has("layout"):
   illustrated += 1
   check(skins.artwork != null and skins.illustrated_panel != null, "Illustrated skin has separate hero and panel artwork")
   check(skins.artwork.get_width() >= 1024 and skins.artwork.get_height() >= 1024, "Illustration source meets the documented resolution")
   var img: Image = skins.artwork.get_image()
   print("Alpha at illustration corner: ", img.get_pixel(0,0).a)
 check(illustrated == 8, "Every approved design is implemented")
 for old_path in skins.REPLACEMENTS:
  check(skins.load_skin(old_path, false) == OK and skins.current_path == skins.REPLACEMENTS[old_path], "Old player/screensaver selection migrates: " + old_path.get_file())
  check(not FileAccess.file_exists(old_path), "Obsolete prototype manifest removed")
 for stem in ["y2k-chrome", "neon-ronin", "v12-redline", "arsenal-titanium", "velvet-muse", "orbital-eva", "sentinel-head", "xeno-pod"]:
  check(not FileAccess.file_exists("res://skins/" + stem + "-art.svg"), "Old vector illustration removed: " + stem)
 skins.load_skin(original, false)
 print("Failures: ", failures)
 quit(0 if failures == 0 else 1)
