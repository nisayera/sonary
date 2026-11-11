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
  <img src="https://img.shields.io/badge/status-beta-orange" alt="Status">
</p>

> [!NOTE]
> **Sonary is in beta.** All eleven modules below are released and usable. Some of it has only been
> built against CI and still needs trying on real hardware (brightness of external monitors, XDR
> extra brightness). What is done and what is missing is tracked in the [feature checklist](docs/FEATURES.md).

---

Sonary is a native menu bar app for macOS 26. Every feature is a **module** you can switch on or off: a disabled module doesn't load, doesn't run in the background and doesn't ask for permissions. No account, no telemetry, no paywall.

## Why Sonary

- **Modular.** One app, many tools. Enable just the ones you use.
- **One look.** Every tab of the menu panel and every settings page is built from the same few parts, so nothing sits somewhere else from one page to the next.
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
| 🏝 **Notch** | Vorssaint's Dynamic Island, taken over whole: music with queue and live equalizer, calendar, timer, downloads, accessory batteries, file shelf, gestures, sizes and shapes (also on displays without a notch) |
| 📋 **Clipboard** | Clipboard history with text, images and files, auto-clear, plain-text paste, clean links, a file shelf and Finder helpers |
| 🧹 **Apps** | Cleaner, uninstaller with leftovers, quit and force quit, port manager, Homebrew and app updates, disk image installer |
| 🪟 **Windows** | Layouts on shortcuts and screen edges, window switcher, Dock previews and click actions, ⌘Q/⌘W protection, fixed Space order |
| ☀️ **Display** | Per-display brightness with shortcuts, external monitors over DDC/CI, dimming where neither reaches, extra brightness on XDR panels, wallpaper, Bluetooth off during sleep |
| 🔊 **Sound** | Output and input switcher, device priority, volume, microphone mute and level meter, apps that are playing |
| ☕️ **Keep awake** | For a while, until a time, or while an app runs, the Mac is plugged in or a display is attached; also with the lid closed |
| 🧰 **Tools** | Command bar, screenshots with editor and scrolling capture, screen recording, text from screen, color picker, radial menu, scratchpad, snippets |

The full list, including what is only partly done, is in [docs/FEATURES.md](docs/FEATURES.md). Which permission each module asks for is in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## How it looks

The menu bar icon opens a panel with one tab per running module. Every tab is a list of sections
that open in place; nothing scrolls sideways and nothing is cut off. The settings window has a
sidebar with search, and one page per module: a header with the switch, then cards of rows.

Accent colour, how see-through the surfaces are, which tabs the panel shows and in what order are
all yours to set under **Settings → General**.

## Install

Download the latest `Sonary-<version>.dmg` from [Releases](https://github.com/nisayera/sonary/releases) and drag Sonary into Applications.

Sonary is **not notarized yet**, so macOS blocks the first launch. Since macOS 15, right-click → **Open** no longer gets past this; instead:

1. Open Sonary. When macOS says it cannot verify the app, click **Done**.
2. Open **System Settings → Privacy & Security** (Datenschutz & Sicherheit) and scroll down to the note about Sonary.
3. Click **Open Anyway** (Trotzdem öffnen), confirm with your password or Touch ID, then click **Open Anyway** once more.

From the Terminal, `xattr -dr com.apple.quarantine /Applications/Sonary.app` does the same. After that, Sonary checks for new versions by itself and updates in one click via [Sparkle](https://sparkle-project.org). What changed in each version is in [CHANGELOG.md](CHANGELOG.md) and on its [release page](https://github.com/nisayera/sonary/releases).

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

Every merge to `main` with a new version number is released automatically once its tests pass (see [docs/RELEASING.md](docs/RELEASING.md)). What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

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
- **0.23 – 0.43** — the rest of the checklist: Dock previews across Spaces, ⌘Tab takeover, wallpaper, device priority, messenger downloads, Homebrew search and install, App Store updates, process list, quick panel, snippet triggers, annotation export, menu bar readouts as separate items, settings search, export and import, accent colours
- **0.44** — the menu panel folds instead of scrolling, keep awake as its own module, brightness for external monitors over DDC/CI
- **0.80** — one interface: every panel tab and every settings page built from the same parts; a round of fixes (edge snapping no longer fires on any drag, key debounce no longer eats key repeat, the cleaner leaves Sonary's own data alone, long Homebrew upgrades no longer hang)
- **0.83.6** — the Dynamic Island, mouse, keyboard, clipboard, apps, windows, display, sound, keep awake and tools run on Vorssaint's code, each behind its Sonary module; Sonary's own modules return one at a time. Also: no more freezes when Music, Spotify or Finder hang, the clipboard history in its own private file, a more accurate app update checker, releases only after green tests and release pages that list the changes ([CHANGELOG.md](CHANGELOG.md))
- **0.90** — Vorssaint's pages and panel sections in Sonary's look, the system monitor with fan control and menu bar readouts on Vorssaint's code, light or dark appearance and a choice of menu bar icon

### Before 1.0

- Making the island Sonary's own: its settings in Sonary's layout, its strings in Sonary's catalogs
- Per-app volume and output routing (needs an audio process tap)
- Trying the hardware paths on real devices: DDC brightness, XDR extra brightness
- Notarized builds and a Homebrew cask
- The options still missing compared with Vorssaint, listed [option by option](docs/FEATURES.md#option-by-option)

## Privacy

Sonary works offline. It collects no analytics and has no account. Permissions such as Accessibility or Screen Recording are requested only when you enable a module that needs them.

## License

Sonary is licensed under the [GNU GPL v3.0 or later](LICENSE). Code adapted from other open-source projects is credited in [NOTICE](NOTICE).

<p align="center"><img src="assets/icon.png" width="64" alt="Sonary icon"><br><sub>Made with ♥ for the Mac.</sub></p>
