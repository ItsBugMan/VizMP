# Priority 3: modular UI and live skins

## Use the panels

Press **F5**. The four independent panels are Main Deck, Equalizer, Visualizer,
and Playlist. Resize the splitters between panels to change their proportions.

- **Rearrange:** drag a panel's title onto another panel to swap their slots.
  The title bar's slot selector also docks/swaps it into Upper left, Lower
  left, Upper right, or Lower right.
- **Detach:** press **↗**. The same live panel moves into a native, borderless
  Window; the content is reparented, not recreated.
- **Move a detached window:** drag its title text. Windows' native window
  moving/snapping behavior applies. Resize with its lower-right **◢** grip.
- **Redock:** press **↙**, choose a dock slot, or close the detached window
  through the operating system. Closing a panel window redocks its content.
- **Reset:** Main Deck -> **Settings / skin -> Reset panel layout**.

The docking tree has four slots. It does not create arbitrary nested dock
trees or implement magnetic attachment between detached windows. Drag/drop
inside the main window swaps fixed slots; use the explicit slot selector when
returning a detached window to a dock.

`user://layout.cfg` stores versioned slot assignments, split offsets, detached
window rectangles and states. Changes are checked every two seconds, written
only when state differs, and saved on normal main-window close. Restored
native rectangles are clamped to an available monitor's work area. Invalid
or missing configuration falls back to default positions.

Main Deck opens multiple files and switches file/desktop capture. Playlist
accepts MP3, OGG and WAV drops or multiple file selections, removes duplicates,
supports row activation/removal, and advances on file completion. Clearing
the playlist removes the queue without stopping the current track.

Equalizer provides the six native Godot EQ6 bands, ±12 dB, on file output.
Its effect precedes Master's analyzer, so file visualization reflects the EQ.
Controls are disabled during desktop mode: VizMP observes that Windows mix;
it does not equalize Spotify or other applications. Positive EQ boosts can
exceed file headroom; no limiter or normalization module is added here.

## Switch skins

Main Deck -> **Settings / skin** offers Classic Mint, Midnight Violet, and
Amber Terminal. All share one Theme across the main layout and detached
windows. A skin change preserves panel content, playback, EQ values and GPU
visualizer state. `user://skin.cfg` remembers the last successfully loaded
skin. Missing or invalid saved skins fall back to Classic Mint.

Choose **Load custom skin…** for a JSON manifest anywhere on disk. Manifests
are data-only; loading one does not execute scripts. Invalid manifests keep
the current Theme. Color schemes use StyleBoxFlat. Optional atlas regions
use StyleBoxTexture with nine-slice margins.

Example color scheme:

```json
{
  "version": 1,
  "name": "My Skin",
  "colors": {
    "background": "#10191c", "panel": "#17252a", "surface": "#22343b",
    "border": "#3b535a", "accent": "#75e5b7", "text": "#e0f0e9",
    "muted": "#8aaba4"
  }
}
```

To use an atlas, add these optional fields to that same object:

```json
"atlas": "atlas.png",
"margins": [4, 4, 4, 4],
"regions": {
  "panel": [0, 0, 32, 32],
  "button_normal": [32, 0, 32, 32],
  "button_hover": [64, 0, 32, 32],
  "button_pressed": [96, 0, 32, 32]
}
```

`atlas` resolves relative to the JSON file unless it is an absolute, `res://`,
or `user://` path. Regions are `[x, y, width, height]`; margins are
`[left, top, right, bottom]`. Each supplied region and its margins must fit
within the image. Omitted region types retain their color-based styles.
The manifest is limited to 256 KB and atlas dimensions to 8192 per side.
Imported project textures and external image files are both supported.
Traditional Winamp `.wsz` archives are not imported.

## Implementation and scene assembly

`scenes/Main.tscn` keeps the file player and VisualizerHost. Main.gd composes
the modular UI at runtime, moving the same VisualizerHost into its panel:

```text
Main (Control, shared Theme)
  Background (ColorRect)
  DockLayout (MarginContainer)
    HSplitContainer
      VSplitContainer (left column)
        DockSlot upper-left -> DockPanel Main Deck
        DockSlot lower-left -> DockPanel Equalizer
      VSplitContainer (right column)
        DockSlot upper-right -> DockPanel Visualizer
        DockSlot lower-right -> DockPanel Playlist
    detached Windows (when present) -> the same DockPanel instance
```

DockPanel uses a VBoxContainer with an HBoxContainer title bar and independent
content container. DockSlot accepts panel drag payloads. DockLayout owns the
slot ordering, native windows, settings persistence and reparenting. Detached
panels use the same spectrum texture/global uniforms; they do not create
another analyzer or audio session.

Godot Project Settings -> Display -> Window -> Subwindows -> Embed Subwindows
is **off**, serialized as `display/window/subwindows/embed_subwindows=false`.
This is required for actual OS windows rather than windows embedded in Main.

`SkinManager` is an autoload after VisualizerShaderManager. Register each root
Control or Window once; the manager holds weak references and applies each
new Theme only at skin-switch time. No per-control theme copying or per-frame
theme work runs. Unregister detached roots before freeing their windows.

```gdscript
SkinManager.register_root(my_root_control)
var result: Error = SkinManager.load_skin("user://skins/my-skin.json")
if result != OK:
    push_warning(SkinManager.last_error)
```

DockLayout can host other content in its panels:

```gdscript
var content: VBoxContainer = dock_layout.add_panel("playlist", "Playlist")
content.add_child(my_playlist_control)
dock_layout.dock_panel("playlist", 2)
dock_layout.detach_panel("playlist")
```

The four stable panel IDs are `deck`, `equalizer`, `visualizer`, `playlist`.
Call add_panel once for each ID. Extend the layout/version migration together
if adding more slots. Window reparenting exits/re-enters the tree without
rerunning `_ready`; EqualizerPanel explicitly handles that lifecycle so its
owned effect survives moves and is removed when the UI is destroyed.

Files are in `scripts/ui/`: DockLayout.gd, DockPanel.gd, DockHandle.gd,
DockSlot.gd, SkinManager.gd, EqualizerPanel.gd and PlaylistPanel.gd. Shipped
manifests are in `skins/`. Main.gd composes and wires them to existing audio
and visualizer services. Panel/skin customization does not require changes to
the particle shaders.

## Export and validation

When configuring a Godot export, add **`skins/*.json`** to the non-resource
include filter so the shipped manifests are included in the PCK. Include any
additional project-owned custom skin JSON files similarly. Imported atlas
textures should also be part of the exported project; external user skins
can stay outside the PCK. Windows loopback still requires the helper folder
beside the exported executable; see `DESKTOP_LOOPBACK.md`.

Run the native-window integration test using a real renderer:

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --path . --script res://tests/ui_smoke.gd
```

It checks panel swaps/drop routing, actual borderless OS windows, retained EQ
values and resources across moves, skin changes across roots, atlas
nine-slicing, invalid-skin fallback, saved-layout restoration, playlist WAV
activation, and particle viewport survival through window reparenting. Test
fixtures and the rendered preview live under `.godot/`; tests do not overwrite
the user's skin/layout preferences. The test opens and closes native windows.

Manual acceptance still includes dragging with the mouse, Windows snapping,
resize grips, multi-monitor DPI changes, and sustained detached playback.
These interaction/hardware cases are not established by programmatic tests.

References:
- https://docs.godotengine.org/en/stable/classes/class_splitcontainer.html
- https://docs.godotengine.org/en/stable/classes/class_styleboxtexture.html
- https://docs.godotengine.org/en/stable/classes/class_window.html
