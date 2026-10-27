# VizMP

**Give your music something to look at.**

VizMP is a Windows music player and live audio visualizer with a love for neon,
particle galaxies and glowing CRTs. Play your own music, react to the sound
already playing on your desktop, or let a visualizer take over the screen.

**[Download for Windows](https://github.com/ItsBugMan/VizMP/releases/latest)**
 · [View releases](https://github.com/ItsBugMan/VizMP/releases)
 · [Report an issue](https://github.com/ItsBugMan/VizMP/issues)

![VizMP's Fractal Tunnel visualizer: a twisting neon tunnel with colorful light trails](docs/images/fractal-tunnel.png)

## Pick your view

Switch between five visualizers, each with its own way of responding to your audio:

- **Radial Spectrum** — a circular spectrum that puts the shape of your music front and center.
- **Particle Galaxy** — a swirling 3D galaxy of particles with audio-driven motion and bursts.
- **Fractal Tunnel** — fly through a twisting, colorful tunnel of repeating geometry.
- **Spectrum City** — a neon skyline that rises and pulses with the music.
- **Vector CRT Scope** — watch left and right audio channels draw glowing X-Y patterns, with green or amber phosphor and lingering trails.

Choose **Low**, **Balanced** or **High** quality, toggle camera motion in supported
modes, and press **F11** when you want the visuals to fill the screen.

![Spectrum City: a grid of glowing cyan and magenta towers responding to audio](docs/images/spectrum-city.png)

*Actual VizMP captures using generated test audio and spectrum inputs.*

## Your music, your way

- **Play FLAC, MP3, OGG Vorbis and WAV.** Open files or drop them straight into the player, including native lossless FLAC playback.
- **Visualize desktop audio.** Enable **Live desktop audio** to react to music, browser audio or games playing through your default Windows output device.
- **Build a local library.** Add music folders, scan their subfolders, double-click a track to play it, or queue the whole library.
- **Keep playback within reach.** Previous, play, pause, next, elapsed time and a seek bar are built in.
- **See what's playing.** Track titles, artists, albums and embedded artwork appear where the file's metadata is supported.
- **Shape file playback.** A six-band equalizer lets you adjust the sound from bass to treble.

FLAC playback works throughout the player, library and screensaver. FLAC tags
and embedded artwork are not yet read, so those tracks display their filenames.

## Make it your listening space

Move the player, equalizer, visualizer, playlist and library into the arrangement
that suits you. Resize panels, swap their positions or detach them into separate
windows. VizMP remembers your layout.

Six included skins change the mood: **Classic Mint**, **Midnight Violet**,
**Amber Terminal**, **Cyberpunk**, **Brushed Metal** and **Retro Phosphor**.
Custom JSON and texture-atlas skins are supported too.

![VizMP's dockable player layout with transport controls, equalizer, Particle Galaxy, playlist and media library](docs/images/vizmp-player.png)

## Let it run as your screensaver

VizMP also includes a Windows screensaver. Choose your visualizer, quality and
skin, then use live desktop audio or a shuffled playlist from a music folder.

The installer offers optional screensaver registration. You can adjust its
preferences from **Settings / skin → Screensaver settings…** inside VizMP.
See the [screensaver guide](docs/WINDOWS_SCREENSAVER.md) for configuration and
current Windows preview limitations.

## Start listening

1. Open the **[latest release](https://github.com/ItsBugMan/VizMP/releases/latest)**.
2. Choose the **installer** for setup and shortcuts, or the **portable ZIP** to run from a folder. Extract the complete ZIP and keep its DLL and helper folders together.
3. Launch **VizMP.exe**. Choose **Open audio**, drop in a track, or start audio in another app and enable **Live desktop audio**.
4. Pick a visualizer, choose a skin and press **F11**.

**F11** toggles fullscreen. **Escape** or a left click returns from visualizer
fullscreen. Use **↗** on a panel to detach it, and **Settings / skin → Reset panel
layout** to return to the default arrangement.

**Windows x64 · DirectX 12-capable graphics · No separate Godot or .NET installation required.**
The current Windows build uses Godot 4.7.2 with Forward+ rendering. Lower the
quality preset if you need a lighter visualizer. Desktop capture follows your
Windows default output device; see the [audio guide](docs/DESKTOP_LOOPBACK.md)
if another app is routed to a different device.

Check for new versions from **Settings / skin → Check for updates…**. VizMP
asks before downloading and installing an update.

## Credits

Created by **[ItsBugMan](https://github.com/ItsBugMan)**, with development assistance from OpenAI Codex.

VizMP is built with the work of these projects and their contributors:

- **[Godot Engine](https://godotengine.org/)** — the application, audio engine and visual rendering.
- **[godot-xiph-audio](https://github.com/goatchurchprime/godot-xiph-audio)** by **Julian Todd / goatchurchprime** — native FLAC audio support.
- **[NAudio](https://github.com/naudio/NAudio)** by **Mark Heath and contributors** — the WASAPI audio library used by VizMP's desktop capture helper.
- **Xiph.Org codecs and godot-cpp** — codec and native extension dependencies; see the [Xiph third-party notices](addons/xiph_audio/THIRD_PARTY_NOTICES.md).
- **[.NET](https://github.com/dotnet/runtime)** — the runtime bundled with the Windows audio capture helper.
- **[Inno Setup](https://jrsoftware.org/)** — Windows installer packaging.

Third-party components retain their own licenses. The Windows downloads include
the Xiph extension notices and the capture helper's NAudio and .NET notices.

## For builders and curious listeners

Want to make your own skin, tune a visualizer or explore how the audio drives
it? The implementation guides live in [`docs/`](docs/):

- [Custom skins and panel layout](docs/MODULAR_UI_SKINS.md)
- [Library, artwork, transport and graphics](docs/FIDELITY_AND_LIBRARY.md)
- [Desktop audio capture](docs/DESKTOP_LOOPBACK.md)
- [FLAC extension setup](docs/FLAC_WINDOWS.md)
- [Particle Galaxy](docs/PARTICLE_GALAXY.md) · [Fractal Tunnel and Spectrum City](docs/TUNNEL_AND_CITY.md)
- [Vector CRT Scope and capture validation](docs/OSCILLOSCOPE.md)
- [Windows builds, installer and updates](docs/DISTRIBUTION_AND_UPDATES.md)
- [Audio architecture](docs/ARCHITECTURE.md)

To run from source, open `project.godot` in **Godot 4.7.2** and press **F5**.
File playback includes the Xiph extension in `addons/xiph_audio/`. Desktop
capture also requires building the included [Windows helper](docs/DESKTOP_LOOPBACK.md).

Found a bug or have a visualizer idea? **[Open an issue](https://github.com/ItsBugMan/VizMP/issues)**.
If VizMP earns a place on your desktop, a GitHub star helps others find it.
