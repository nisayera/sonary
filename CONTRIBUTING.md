# Contributing to Sonary

Thanks for helping! Sonary is in early development, so please open an issue before a larger pull request.

## Setup

- macOS 26 Tahoe, Apple Silicon, Xcode 26
- Clone, generate the Xcode project from `project.yml` and open it:

  ```sh
  git clone https://github.com/nisayera/sonary.git && cd sonary
  brew install xcodegen && xcodegen generate
  open Sonary.xcodeproj
  ```

`Sonary.xcodeproj` is generated and ignored by git. Change `project.yml`, not the project.

## Project layout

```
App/                  the app target: @main, menu bar panel, settings window, onboarding, updates
Packages/
  SonaryCore/         module protocol, module registry, permissions, shortcuts, launch at login
  SonaryUI/           design system: tokens, cards, settings rows, icon tabs, appearance
  Monitor/ Mouse/ …   one Swift package per module, each with its own tests and string catalog
SonaryTests/          tests for the app target
scripts/              release helpers (version numbers, Sparkle appcast)
docs/                 architecture, feature checklist, permissions, releasing
assets/               README images and design sources
```

How the pieces fit together is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Running the tests

Each package has its own tests, written with Swift Testing:

```sh
swift test --package-path Packages/Mouse
```

The app target's tests run through Xcode (`⌘U`) or `xcodebuild … test`. CI runs every package with warnings treated as errors, builds the app and runs the app tests for every pull request and every merge to `main`; see `.github/workflows/ci.yml`.

The app tests include snapshot tests that render the panel and the settings pages in light and dark mode. CI pushes the pictures to the `ci-snapshots` branch, which is the quickest way to look at a UI change without a Mac at hand.

## Guidelines

- Swift 6 with strict concurrency, SwiftUI first, AppKit only where needed. No compiler warnings, no force unwraps in production code.
- Each feature lives in a module and is fully off when the module is off: no timers, no event taps, no permission prompts.
- Keep decisions in pure functions or value types and test them; keep the system calls around them thin.
- Every user-facing string goes into the package's String Catalog, in English and German. Each package has a test that fails when a German translation is missing.
- New settings fields get a default value; new fields in structs that live in a list are Optional (see "Settings" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).
- Event taps run on the main run loop. Read what you need from the event in the C callback, pass only Sendable values into `MainActor.assumeIsolated`, re-enable the tap on `tapDisabledByTimeout`, and mark events Sonary posts itself through `.eventSourceUserData` so its own taps let them pass.
- Every new permission goes into [docs/PERMISSIONS.md](docs/PERMISSIONS.md), every new feature into [docs/FEATURES.md](docs/FEATURES.md).
- Keep pull requests small and focused, describe what and why, and add screenshots for UI changes.

## Interface

Every part of the interface is built from the components in `SonaryUI`, so no tab and no page lays
out its own cards:

- **A tab of the menu panel** is a list of `PanelDisclosure` sections. A section holds a `PanelGroup`
  of rows (`PanelRow`, `PanelToggleRow`, `PanelSliderRow`, `PanelButtonRow`) and, where something
  needs saying, a `PanelNote` under it. Long lists show six rows and a `PanelMoreButton`. The panel
  never shows a scroll bar.
- **A settings page** is a `SettingsPage` with a `SettingsPageHeader` and `SettingsCard`s. A card's
  children are its rows (`SettingsRow`, `SettingsToggleRow`); the card adds the insets and the
  hairlines between them, so do not add `Divider()` or padding of your own. Pickers, sliders and
  fields on the right of a row take `.settingsControl()` so they line up.
- **Icons** are `IconBadge`s everywhere: accent while the thing is on, grey while it is off.

The CI run renders the panel and the settings in both appearances and pushes the pictures to the
`ci-snapshots` branch; look at them before merging a change to the interface.

## Adding a module

1. Create `Packages/<Name>` with a library target, a test target and `Resources/Localizable.xcstrings`.
2. Implement `SonaryModule` (see `Packages/SonaryCore/Sources/SonaryCore/SonaryModule.swift`).
3. Add the package to `project.yml` (under `packages` and both targets) and register the module in `App/AppModel.swift`.
4. Add a one-line summary to `App/ModuleInfo.swift`.

CI picks up new packages automatically.

## Reusing code

Sonary is GPL-3.0-or-later. Code from other projects must use a compatible license. Keep the original copyright headers and add an entry to [NOTICE](NOTICE).

## Reporting bugs

Use the bug report template and include your macOS version and Sonary version.
