<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.png">
    <img src="assets/banner.png" alt="Sonary — your Mac's menu bar toolbox" width="100%">
  </picture>
</p>

<p align="center">
  <b>A whole drawer of Mac utilities behind one menu bar icon.</b><br>
  Free, open source, modular. Turn on only what you need.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#modules">Modules</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#release-history">Releases</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <a href="https://github.com/nisayera/sonary/releases"><img src="https://img.shields.io/github/v/release/nisayera/sonary?include_prereleases&label=release&color=FF8A3D" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe-FF4FA3" alt="macOS 26">
  <img src="https://img.shields.io/badge/Apple%20Silicon-only-555" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/status-early%20development-orange" alt="Status">
</p>

> [!NOTE]
> **Sonary is in early development.** All ten modules below are released and usable, but expect rough edges.
> What is done and what is still missing is tracked in the [feature checklist](docs/FEATURES.md).

---

Sonary is a native menu bar app for macOS 26. Every feature is a **module** you can switch on or off: a disabled module doesn't load, doesn't run in the background and doesn't ask for permissions. No account, no telemetry, no paywall.

## Why Sonary

- **Modular.** One app, many tools. Enable just the ones you use.
- **Native.** Swift 6 and SwiftUI, designed for Liquid Glass on macOS 26.
- **Private.** Everything runs locally. Sonary reaches the network only for its own update check and, when you ask for them, the app update checker, Homebrew and the speed test.
- **Free.** GPL-3.0-or-later. No subscription, no "Pro" tier.
- **Bilingual.** English and German interface.

## Modules

| Module | What it does |
| --- | --- |
| 📊 **Monitor** | CPU, GPU, memory, network, disk, battery, temperatures and fans in the menu bar, with history, the busiest apps, alerts and a speed test |
| 🖱 **Mouse** | Linear or smooth scrolling, acceleration off, button and gesture mapping, double-click filter, three-finger middle click, per-app exceptions |
| ⌨️ **Keyboard** | Super Key: hold one key for ⌃⌥⇧⌘, tap it for an action; key debounce; per-app exceptions |
| 🏝 **Notch** | An island at the notch with music, calendar, timer, downloads, accessory batteries, a file shelf and the camera (simulated on displays without a notch) |
| 📋 **Clipboard** | Clipboard history with text, images and files, auto-clear, plain-text paste, clean links, a file shelf and Finder helpers |
| 🧹 **Apps** | Cleaner, uninstaller with leftovers, quit and force quit, port manager, Homebrew and app updates, disk image installer |
| 🪟 **Windows** | Layouts on shortcuts and screen edges, window switcher, Dock previews and click actions, ⌘Q/⌘W protection, fixed Space order |
| ☀️ **Display** | Per-display brightness with shortcuts, dimming where macOS offers no control, extra brightness on XDR panels, Bluetooth off during sleep |
| 🔊 **Sound** | Output and input switcher, volume, microphone mute and level meter, apps that are playing, keep awake |
| 🧰 **Tools** | Command bar, screenshots with editor and scrolling capture, screen recording, text from screen, color picker, radial menu, scratchpad, snippets |

The full list, including what is only partly done, is in [docs/FEATURES.md](docs/FEATURES.md). Which permission each module asks for is in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## Install

Download the latest `Sonary-<version>.dmg` from [Releases](https://github.com/nisayera/sonary/releases) and drag Sonary into Applications.

Sonary is **not notarized yet**, so macOS blocks the first launch: right-click Sonary, choose **Open**, then **Open** again (or run `xattr -dr com.apple.quarantine /Applications/Sonary.app`). After that, Sonary checks for new versions by itself and updates in one click via [Sparkle](https://sparkle-project.org).

A Homebrew cask is planned.

### Requirements

- Mac with Apple Silicon
- macOS 26 Tahoe or newer

## Build from source

```sh
git clone https://github.com/nisayera/sonary.git
cd sonary
brew install xcodegen
xcodegen generate
open Sonary.xcodeproj
```

Requires Xcode 26. The Xcode project is generated from `project.yml` and is not checked in. See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and conventions, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the app is put together.

## Release history

Every merge to `main` with a new version number is released automatically (see [docs/RELEASING.md](docs/RELEASING.md)).

- **0.2** — Foundation (app shell, menu bar extra, module system, settings, onboarding, launch at login, localization, in-app updates) and the System Monitor
- **0.3** — Mouse
- **0.4** — Notch / Dynamic Island
- **0.5 – 0.9** — Clipboard & Files, App Management, Windows, Sound, Tools
- **0.10** — Super Key, notch gestures, window switcher, brightness, quick toggles, radial menu
- **0.12** — clipboard images and auto-clear, busiest apps and fans, horizontal scroll, key debounce, scheduled cleaning, scratchpad tabs, cleaning mode
- **0.13** — adjustable transparency, edge snapping, focus follows mouse, switcher previews, menu commands and clipboard history in the command bar, pinned screenshots, camera preview, Markdown preview, media-key guard, keep-awake conditions, app update checker, clipboard image to Finder
- **0.14** — screen recording, image conversion and video shrinking, speed test, Bluetooth off during sleep, disk image installer
- **0.15** — central shortcut manager: every shortcut on one page, recordable and resettable
- **0.16** — fill the screen without a new Space, GIFs from videos, a file shelf in the notch, Sonary's own capture selector
- **0.17** — fixed Space order, three-finger middle click, extra brightness on XDR panels
- **0.19** — Dock actions and previews, switcher filters, hold to quit, typed snippets, Finder cut and rename, microphone meter, notch camera, extra radial rings, modifier-drag, files and scripts in the command bar
- **0.20** — screenshot editor: arrows, boxes, highlights, text, redaction and backgrounds
- **0.21** — scrolling screenshots, stitched automatically
- **0.22** — the sound panel shows which apps are playing

### Next

- Per-app volume and output routing (needs an audio process tap)
- Brightness for external monitors over DDC
- Notarized builds and a Homebrew cask
- **1.0** once the [feature checklist](docs/FEATURES.md) is done

## Privacy

Sonary works offline. It collects no analytics and has no account. Permissions such as Accessibility or Screen Recording are requested only when you enable a module that needs them.

## License

Sonary is licensed under the [GNU GPL v3.0 or later](LICENSE). Code adapted from other open-source projects is credited in [NOTICE](NOTICE).

<p align="center"><img src="assets/icon.png" width="64" alt="Sonary icon"><br><sub>Made with ♥ for the Mac.</sub></p>
