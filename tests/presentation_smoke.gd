extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 print("PASS: " if ok else "FAIL: ", message)
 if not ok: failures += 1
func frames(count: int = 4) -> void:
 for i in range(count): await RenderingServer.frame_post_draw
func run() -> void:
 await process_frame
 var skins: Node = root.get_node("SkinManager")
 var analyzer: Node = root.get_node("AudioAnalyzer")
 var original: String = skins.current_path
 analyzer.set_process(false)
 root.size = Vector2i(2048, 1280)
 var main: Control = load("res://scenes/Main.tscn").instantiate()
 main.save_layout_enabled = false
 root.add_child(main)
 await frames()
 main.set_borderless_windowed(true, false)
 check(root.borderless and main._window_chrome.visible, "Borderless window shows drag rail and native controls")
 var rectangle := Rect2i(root.position, root.size)
 main.set_visualizer_fullscreen(true)
 check(not main._window_chrome.visible, "Fullscreen hides window controls")
 main.set_visualizer_fullscreen(false)
 await frames()
 check(root.borderless and main._window_chrome.visible and root.size == rectangle.size, "Fullscreen returns to borderless window size")
 main.set_borderless_windowed(false, false)
 check(not root.borderless and not main._window_chrome.visible, "Native borders restore")
 main.set_borderless_windowed(true, false)
 main._status.text = "Midnight Rendezvous\nNocturne · Celestial Nights"
 for title in ["01   Midnight Rendezvous       04:26", "02   Velvet Skyline                 03:58", "03   Neon Confessions            04:12", "04   Eclipse Tonight                03:49", "05   After the Rain                  04:33"]: main._playlist._list.add_item(title)
 for skin in ["nocturne", "redline", "aurora", "gt-velocity", "blacksite", "orbital-eva", "sentinel", "xeno-pod"]:
  check(skins.load_skin("res://skins/" + skin + ".json", false) == OK, "Approved skin loads: " + skin)
  await frames(8)
  for id in ["deck", "playlist", "equalizer"]:
   var panel: Control = main._layout.panels[id]
   check(panel.visible and panel.get_global_rect().end.x <= main.size.x + 1 and panel.get_global_rect().end.y <= main.size.y + 1, "Panel fits " + skin + ": " + id)
  var preview: Image = root.get_texture().get_image()
  preview.convert(Image.FORMAT_RGB8)
  preview.linear_to_srgb()
  preview.save_png("res://.godot/" + skin + "-implemented-2k.png")
  var deck_rect: Rect2 = main._layout.panels.deck.get_global_rect()
  check(not deck_rect.intersects(main._layout.panels.playlist.get_global_rect()) and not deck_rect.intersects(main._layout.panels.equalizer.get_global_rect()), "Deck does not overlap lower panels: " + skin)
  check(main._transport.volume_slider.get_global_rect().end.y < deck_rect.end.y, "Volume stays inside deck: " + skin)
  main._layout.detach_panel("equalizer")
  await frames(2)
  main._layout.dock_panel("equalizer", 1)
  await frames(2)
  check(main._layout.panels.equalizer.get_parent() == main._layout._stage, "Detached EQ returns to illustrated layout")
 for viewport_size in [Vector2i(1000, 800), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
  root.size = viewport_size
  for skin in ["nocturne", "redline", "aurora", "gt-velocity", "blacksite", "orbital-eva", "sentinel", "xeno-pod"]:
   skins.load_skin("res://skins/" + skin + ".json", false)
   await frames(6)
   var deck: Rect2 = main._layout.panels.deck.get_global_rect()
   var playlist: Rect2 = main._layout.panels.playlist.get_global_rect()
   var eq: Rect2 = main._layout.panels.equalizer.get_global_rect()
   check(not deck.intersects(playlist) and not deck.intersects(eq) and not playlist.intersects(eq), "No overlap at " + str(viewport_size) + ": " + skin)
   check(deck.end.x <= main.size.x and eq.end.x <= main.size.x and eq.end.y <= main.size.y, "Panels fit resized player: " + skin)
   if viewport_size.x == 3840:
    var capture: Image = root.get_texture().get_image()
    capture.convert(Image.FORMAT_RGB8)
    capture.linear_to_srgb()
    capture.save_png("res://.godot/" + skin + "-implemented-4k.png")
 root.mode = Window.MODE_WINDOWED
 root.size = Vector2i(2048, 1280)
 await create_timer(0.3).timeout
 print("Before maximize: ", root.mode, " / ", root.borderless)
 await frames()
 main._window_chrome.toggle_maximized()
 await create_timer(0.3).timeout
 await frames()
 print("After maximize: ", root.mode, " / ", root.size)
 check(main._window_chrome.is_maximized() and Rect2i(root.position, root.size) == DisplayServer.screen_get_usable_rect(root.current_screen), "Borderless maximize fills the desktop usable area")
 main._window_chrome.toggle_maximized()
 await create_timer(0.3).timeout
 await frames()
 print("After restore: ", root.mode, " / ", root.size)
 check(not main._window_chrome.is_maximized() and root.borderless and root.size == Vector2i(2048,1280), "Custom restore retains borderless mode and original size")
 main._library_button.pressed.emit()
 await frames()
 check(main._layout.windows.has("library") and main._layout.windows.library.visible, "Illustrated layout retains library access")
 main._layout.layout_path = "res://.godot/presentation-layout.cfg"
 main._layout.persistence_enabled = true
 main._layout.save_layout()
 var saved := ConfigFile.new()
 check(saved.load("res://.godot/presentation-layout-illustrated.cfg") == OK and saved.has_section_key("windows", "library"), "Illustrated windows persist separately from legacy split layout")
 main._layout.persistence_enabled = false
 main._layout.dock_panel("library", 4)
 main.set_visualizer_enabled(true, false)
 await frames()
 check(main._layout.windows.has("visualizer"), "VIS opens a floating visualizer in illustrated skin")
 main._layout.windows.visualizer.close_requested.emit()
 await frames()
 check(not main.visualizer_enabled and not main._layout.windows.has("visualizer"), "Closing the visualizer hides it without reopening a window")
 main.set_visualizer_enabled(true, false)
 var host: Control = main._visualizer_host
 host.set_mode(host.Mode.ASCII_RAIN)
 await frames()
 host._container.stretch = false
 host._viewport.size = Vector2i(2560,1440)
 var rain: Control = host._active_visualizer
 rain.set_process(false)
 rain._material.set_shader_parameter(&"columns", 320.0)
 rain._material.set_shader_parameter(&"aspect", 2560.0/1440.0)
 rain._material.set_shader_parameter(&"signal_active", true)
 for energy in [0.02, 0.9]:
  rain._material.set_shader_parameter(&"energy", energy)
  rain._material.set_shader_parameter(&"rain_time", 2.3)
  analyzer.spectrum.fill(0.0)
  analyzer.spectrum[5] = energy
  analyzer.spectrum_updated.emit()
  await frames()
  var image: Image = host._viewport.get_texture().get_image()
  var highest: float = 0
  for y in range(0, image.get_height(), 3):
   for x in range(0, image.get_width(), 3): highest = maxf(highest, image.get_pixel(x,y).g)
  check(highest > 0.05 and highest < 0.85, "Quiet/loud narrow-band audio remains visible without HDR clipping: " + str(energy))
  check_face_detail(image)
  image.convert(Image.FORMAT_RGB8)
  image.linear_to_srgb()
  image.save_png("res://.godot/ascii-clarity-" + str(energy) + "-2k.png")
 rain._material.set_shader_parameter(&"signal_active", false)
 await frames()
 var silent: Image = host._viewport.get_texture().get_image()
 var lit := 0
 for y in range(silent.get_height()):
  for x in range(silent.get_width()):
   var c: Color = silent.get_pixel(x,y)
   if c.r > 0 or c.g > 0 or c.b > 0: lit += 1
 check(lit == 0, "Silence clears every 2K RGB pixel")
 skins.load_skin(original, false)
 main.queue_free()
 await process_frame
 print("Failures: ", failures)
 quit(0 if failures == 0 else 1)

func check_face_detail(image: Image) -> void:
 var portrait: Image = load("res://assets/portraits/brow-mask.png").get_image()
 portrait.convert(Image.FORMAT_RGB8)
 var grid := Vector2i(320, 120)
 var total: float = 0
 var sx: float = 0
 var sy: float = 0
 var sxx: float = 0
 var syy: float = 0
 var sxy: float = 0
 var coverage: int = 0
 for y in range(grid.y):
  for x in range(grid.x):
   var uv := (Vector2(x,y) + Vector2.ONE * 0.5) / Vector2(grid)
   var face_uv := (uv - Vector2.ONE * 0.5) * Vector2((2560.0/1440.0)/(float(portrait.get_width())/portrait.get_height()),1) * 0.62 + Vector2(0.5,0.53)
   if face_uv.x <= 0 or face_uv.x >= 1 or face_uv.y <= 0 or face_uv.y >= 1: continue
   var face: Color = portrait.get_pixel(int(face_uv.x * portrait.get_width()), int(face_uv.y * portrait.get_height()))
   var target: float = face.r * 0.2126 + face.g * 0.7152 + face.b * 0.0722
   if target < 0.1: continue
   var brightness: float = 0
   for py in range(y * 12, y * 12 + 12):
    for px in range(x * 8, x * 8 + 8): brightness += image.get_pixel(px,py).g / 96.0
   if brightness > 0.005: coverage += 1
   total += 1
   sx += target
   sy += brightness
   sxx += target * target
   syy += brightness * brightness
   sxy += target * brightness
 var correlation: float = (total * sxy - sx * sy) / maxf(0.00001, sqrt((total * sxx - sx*sx) * (total * syy - sy*sy)))
 print("Face detail correlation: ", correlation, "; illuminated coverage: ", coverage / total)
 check(correlation > 0.72 and coverage / total > 0.9, "Glyph brightness preserves facial features and dense coverage")
