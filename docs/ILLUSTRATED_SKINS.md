# Illustrated skins and clarity update

## Implemented and approved

All eight redesigned skins were approved by the user in two preview rounds
before implementation. They use original character art, separate ornamental
frame textures, and live Godot controls. Their artwork is integrated into the
main composition instead of being repeated as a tiny panel header.

- Nocturne: dark chrome, violet phosphor, gothic character and rose ornaments.
- Redline: silver/carbon frames, amber highlights, racing character on the right.
- Aurora: ivory, champagne gold and teal, fantasy character on the left.
- GT Velocity: midnight-blue supercar, silver/carbon details and amber readout.
- Blacksite: fictional sci-fi armory, worn gunmetal, olive and brass details.
- Orbital EVA: white astronaut helmet, titanium, gold foil and pale-cyan readout.
- Sentinel: cobalt/titanium robot head, cyan optics and industrial frames.
- Xeno Pod: iridescent biomechanical shell, violet sheen and orange light seams.

The legacy six color themes retain their split layout. The obsolete vector illustrations, prototype frame atlases and generator have
been removed. Migration aliases resolve old player and screensaver selections
to the redesigned counterparts, without retaining the old artwork.
The collection now contains eight illustrated designs and six classic themes.

## Window and panel behavior

F10 toggles borderless windowed mode, also available in Player / visualizer
settings. The preference is saved in `user://visualizer.cfg`. Drag the top rail,
double-click it to maximize/restore, use its window buttons, or resize from the
bottom-right corner. Borderless maximize uses the monitor's usable area and
preserves the taskbar. F11/Esc restores the preceding size, window mode and
visualizer visibility. Hidden visualizers still suspend their GPU work.

Illustrated skins use a fixed responsive composition. VIS opens the visualizer
in its own window; closing it disables the viewport. Library remains accessible
from the deck. Each deck/EQ/playlist panel can detach and return to its themed
position. Floating geometry is stored separately in `layout-illustrated.cfg`,
so it does not overwrite the legacy split layout. Switching back to a legacy
skin redocks a visualizer that was opened automatically by the illustrated layout.

## ASCII rendering

The static 16-character atlas is ordered by approximate density. Portrait
luminance sampled at each cell's center controls glyph choice and brightness.
Three staggered streams per column retain detail while highlights fall through
the portrait. Background rain is dimmer than the facial detail. Frequency
energy modulates illumination without removing entire regions when a track has
little energy in a particular band. Raw activity gates output to exact black;
smoothed energy controls the active brightness envelope. Phosphor output is
bounded below 1.0, with no white HDR spikes or static image underneath the glyphs.

Quality adjusts cell density with viewport height, with a minimum four-pixel
cell width and a 720-column cap. Rendering remains one full-screen pass plus a
one-shot glyph atlas. No per-character nodes are created during playback.

## Asset fidelity

Character source images are 1024×1536; object illustrations and ornamental
panel images are 1536×1024.
The generated source illustrations are not native 4K images. Godot renders live
text and controls at the display resolution, with nine-slice panel draws that
preserve corner proportions. Actual player captures were inspected at 2048×1280
and rendered/tested at 3840×2160. See `SKIN_DESIGN_PROMPTS.json` and `SKIN_PRODUCTION_PROMPTS.json` for the
generation briefs. Tool: OpenAI image_gen. The production assets are under `assets/skins/`.

## Validation on Godot 4.7.2 / Forward+ / RTX 3070

- `tests/presentation_smoke.gd`: actual GPU pixels; approved skins; overlap and
  bounds checks at 1000×800, 2560×1440 and 3840×2160; native border toggles;
  fullscreen restoration; maximize/restore; floating windows; persistence;
  visualizer-close lifecycle; exact silence at 2560×1440.
- Quiet and loud narrow-band fixtures preserve approximately 0.84 correlation
  between portrait luminance and rendered character-cell brightness. More than
  92% of facial cells are illuminated in the quiet fixture, and 95% in the loud
  fixture. These are synthetic regression fixtures, not audio quality scores.
- `tests/ui_smoke.gd`: real playback, EQ, skin changes, docking, persistence,
  custom atlas validation and resource cleanup.
- `tests/expansion_smoke.gd`: existing visualizers, silence, fullscreen, hidden
  viewport suspension and bounded lightning geometry.
- ASCII viewport-only median GPU cost measured at 1920×1080: approximately
  0.42 ms in the expansion fixture. This excludes presentation and the rest of
  the application and is not a frame-rate guarantee.

Run these rendering tests without `--headless`; `--audio-driver Dummy` keeps
their synthetic playback independent of the Windows speaker configuration.

## Screenshots

Actual rendered captures with synthetic sample track labels, not concept mockups:

- [Nocturne](images/nocturne-player.png)
- [Redline](images/redline-player.png)
- [Aurora](images/aurora-player.png)
- [GT Velocity](images/gt-velocity-player.png)
- [Blacksite](images/blacksite-player.png)
- [Orbital EVA](images/orbital-eva-player.png)
- [Sentinel](images/sentinel-player.png)
- [Xeno Pod](images/xeno-pod-player.png)

## Distribution

The 1.2.0 installer and portable ZIP include the new assets. Both the packed
built-in skins and external JSON copies are validated with their artwork.
The Windows release workflow builds the installer, portable archive, and SHA-256
checksums from the tagged commit. Public downloads are on the GitHub release page.
