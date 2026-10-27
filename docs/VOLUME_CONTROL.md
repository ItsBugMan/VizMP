# File volume and mute — Godot 4.7.2 / Windows

The Main Deck transport now includes **File volume**, a horizontal 0–100%
slider, a **Mute** checkbox and a percentage label. Hover over the slider or
percentage to see its dB level. Keyboard slider adjustments work too.

## Integration

The project registers one settings owner, before audio playback starts:

```ini
[autoload]
AudioOutput="*res://scripts/audio/AudioOutput.gd"
```

Keep the existing autoloads; the registration is already in `project.godot`.
`Main.gd` already constructs `TransportBar.gd`, which builds these themed
controls automatically. No `.tscn` edits or editor signal connections are
required. The controls move with Main Deck when it is detached or redocked.

```text
Main Deck
  TransportBar (VBoxContainer)
    Previous / Play / Pause / Next
    Track position slider
    Elapsed / duration
    File volume
    HBoxContainer
      Mute (CheckBox)
      Volume (HSlider, expanding, 0–100, step 1)
      Percentage (Label)
    Desktop volume note (visible only during live capture)
```

The slider changes linear amplitude, converted to Godot's logarithmic dB bus
gain. For example, 50% means approximately −6.02 dB; 25% means −12.04 dB.
Percentage is amplitude, not a claim about perceived loudness. The startup
fallback converts existing bus dB back to linear gain with `db_to_linear()`.
Do not also enable the slider's exponential mapping: this implementation
already performs the explicit conversion.

```gdscript
# Core behavior; AudioOutput.gd also handles validation and saving.
var bus: int = AudioServer.get_bus_index(&"Master")
var gain: float = clampf(percent / 100.0, 0.0, 1.0)
var decibels: float = linear_to_db(gain) if gain > 0.0 else -80.0
AudioServer.set_bus_volume_db(bus, decibels)
AudioServer.set_bus_mute(bus, muted or gain <= 0.0)
```

0% uses a finite floor and an effective bus mute for exact silence; it never
passes `linear_to_db(0)` / negative infinity to AudioServer. The explicit Mute
state is independent of the slider. Moving a muted slider changes the saved
level while keeping it muted. Unmuting restores that level; at 0%, raise the
slider to restore sound. 100% is unity gain, with no added amplification.

`AudioOutput.changed` updates the controls using `set_value_no_signal()` and
`set_pressed_no_signal()` to avoid UI feedback loops. Volume state and UI
updates are event-driven, with no additional frame polling or PCM processing.

## Saved preferences

`user://settings.cfg` contains:

```ini
[audio]
volume_linear=0.5
muted=false
```

Existing settings in other sections are preserved. Audio changes immediately;
a single 200 ms timer coalesces slider movement into a disk save. Saving uses
a temporary file and rename. Normal shutdown or updater restart flushes any
pending change, and startup restores preferences before the Main Deck is
created. A forced process termination during the debounce window can lose the
last adjustment. Invalid numeric values are rejected and the gain is clamped
to 0–1. The default is the configured Master bus gain and mute state.

## File output and desktop capture

File playback (MP3 / OGG / WAV / FLAC) uses Master, so the same control works
with every decoder. Volume does not modify file bytes, equalizer bands or
stream playback position. Visualizer analysis remains on its existing buses.

WASAPI capture continues to feed `DesktopAnalysis`, whose output is sent to
`DesktopSilentSink`. The volume owner never changes either bus, the generator
or captured PCM. Live desktop mode disables the file slider and mute checkbox,
labels them as saved file volume and displays **Desktop volume: use Windows.**
Use Windows or the source application's controls to change what you hear.
Returning to file mode restores access to the saved controls.

The screensaver shares the global Master preferences. Its existing playlist
volume is an additional player-level trim: it combines with Master gain and
does not replace the saved volume or mute preference. Desktop screensaver
capture uses the same independent analysis route.

## Verification

```powershell
& '<Godot-4.7.2-console.exe>' --headless --path '<VizMP-project>' --script res://tests/volume_smoke.gd
```

The focused test uses a dedicated `.godot/` settings file, restores the user's
runtime state and never writes to their preferences. It checks dB conversion,
zero volume, mute independence, automatic saving, fresh-instance restoration,
shutdown flushing, transport UI synchronization and source-mode behavior.
It sends real decoded stereo FLAC through the desktop analysis bus and
confirms Master zero/mute leaves its FFT level and captured PCM unchanged.
This validates routing without requiring the physical WASAPI helper/device.

References: [AudioServer](https://docs.godotengine.org/en/latest/classes/class_audioserver.html)
and [audio buses](https://docs.godotengine.org/en/latest/tutorials/audio/audio_buses.html).
The local Godot 4.7.2 runtime is the compatibility check for this integration.
