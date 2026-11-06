# Architecture

How Sonary is put together, what it promises and what it deliberately leaves out.

## Goal

Sonary is a native, open-source menu bar app for macOS 26: a toolbox of Mac utilities in which every feature is a module that can be switched on or off on its own. Its feature set follows the free app Vorssaint (GPL-3.0); see [Relationship to Vorssaint](#relationship-to-vorssaint).

## Ground rules

- **Platform:** macOS 26 Tahoe and Apple Silicon only (`ARCHS = arm64`). No `#available` fallbacks, no Intel build.
- **Language:** Swift 6 language mode with strict concurrency, SwiftUI first, AppKit only where SwiftUI has no answer (panels, event taps, Accessibility).
- **Quality:** no compiler warnings (CI builds with warnings as errors), no force unwraps in production code.
- **Off means off:** a disabled module runs no timers, holds no event taps and asks for no permissions.
- **Testable core:** decisions live in pure functions and value types with Swift Testing tests; hardware and system calls sit behind protocols or in thin wrappers.
- **Languages:** every user-facing string in English and German, in String Catalogs.
- **Privacy:** no account, no analytics. The network is used only for Sonary's own update check and, on request, the app update checker, Homebrew and the speed test.
- **License:** GPL-3.0-or-later. Reused code keeps its original headers and is listed in [NOTICE](../NOTICE).

## Layout

```
App/            @main, MenuBarExtra panel, settings window, onboarding, Sparkle updates
Packages/
  SonaryCore/   SonaryModule, ModuleRegistry, PermissionBroker, ShortcutStore, HotKey, LaunchAtLogin
  SonaryUI/     tokens, appearance, GlassCard, settings components, icon tab bar, motion
  Monitor/ Mouse/ Keyboard/ Notch/ Clipboard/ Apps/ Windows/ Display/ Sound/ Tools/
SonaryTests/    tests for the app target
```

The Xcode project is generated from `project.yml` with XcodeGen. Every module is a local Swift package that depends only on `SonaryCore` and `SonaryUI`, never on another module. Where two modules work together (the Super Key opening the command bar, the command bar pasting from the clipboard history) the app target wires them up in `AppModel`.

## Core

### Modules

```swift
@MainActor protocol SonaryModule: AnyObject {
    var id: String { get }
    var title: LocalizedStringResource { get }
    var symbol: String { get }
    var requiredPermissions: [SonaryPermission] { get }
    func start() async throws
    func stop() async
    func makeSettingsView() -> AnyView
    func makePopoverView() -> AnyView?   // optional tab in the menu bar panel
}
```

`ModuleRegistry` keeps which modules are on (`module.<id>.enabled` in UserDefaults) and starts and stops them. Calls for the same module are serialized, so a quick on-off-on cannot interleave. Before `start()` the registry asks the `PermissionGate` for the module's permissions. If a permission is missing or `start()` throws, the module is switched off, the reason is stored in `failures` and shown in the settings, and the rest of the app keeps running.

### Permissions

`PermissionBroker` checks and requests permissions through a `PermissionChecking` implementation, so tests can replace it. Modules declare what they need in `requiredPermissions`; features inside a module that need more (the calendar widget, Finder automation, screen recording for previews) ask when that feature is first used. The full list is in [PERMISSIONS.md](PERMISSIONS.md).

### Shortcuts

`ShortcutStore` is the one place for keyboard shortcuts. A module describes its shortcuts once (identifier, title, group, default combination) and binds an action while it runs. The store keeps the user's changes, registers the combinations through Carbon hot keys (`HotKey`, no permission needed) and refuses clashes. The Shortcuts page in the settings lists every shortcut, including those of modules that are off.

### Appearance

`SonaryAppearance` (glass, frosted, solid) sets how see-through floating surfaces are. It reaches views through the environment; `panelBackground(in:)` and `GlassCard` apply it. Reduce Transparency always wins over the user's choice.

## User interface

- **Menu bar panel** (`PopoverView`): a `MenuBarExtra` in window style with a header, icon tabs (an overview with every module's switch, plus one tab per running module that offers a panel), the content and a footer with settings, update check and quit.
- **Settings window** (`SettingsView`): a sidebar with General, Shortcuts, Updates and About, then one page per module. Each page is a header with the module's switch and a stack of cards.
- **Onboarding**: shown on first launch; it collects the permissions the modules need and can be opened again from the settings.
- **Design**: Liquid Glass (`.glassEffect()`, `GlassEffectContainer`) only for floating elements such as the panel, the notch and HUDs; settings use system materials. 8-point grid (`Spacing`), SF Symbols, springs under 0.5 s (`SonaryMotion`), an opacity fade when Reduce Motion is on, VoiceOver labels, light and dark mode.

## Modules in short

| Module | Main pieces |
| --- | --- |
| Monitor | `MetricsSampler` actor samples once a second into a ring buffer (~5 min); sources behind `MetricsSources`; SMC for temperatures and fans; alerts through UserNotifications |
| Mouse | `CGEventTap` on its own thread; scroll math, smoothing, button mapping and click filter as pure functions; pointer acceleration restored on stop and after a crash |
| Keyboard | Event tap for the Super Key and key debounce; `SuperKeyEngine` decides |
| Notch | Borderless `NSPanel` at the top of the screen; notch size from `safeAreaInsets`, simulated without a notch; music through distributed notifications and AppleScript (no MediaRemote) |
| Clipboard | Polls the pasteboard, skips password entries, stores history and image files; Finder helpers through AppleScript |
| Apps | Cleaner, uninstaller and folder tidying move files to the Trash; ports through `lsof`; Homebrew and Sparkle feeds for updates |
| Windows | Accessibility API for moving windows, ScreenCaptureKit for previews, an event tap for ⌘Q/⌘W protection |
| Display | DisplayServices for brightness, overlay windows for software dimming and XDR headroom |
| Sound | Core Audio for devices, volume and the apps that are playing; power assertions for keep awake |
| Tools | Command bar, capture (system `screencapture` or Sonary's selector, ScreenCaptureKit for recording), Vision for text recognition, annotation editor, radial menu, scratchpad, snippets |

Some features rely on undocumented system interfaces, loaded at runtime with `dlsym`: brightness (DisplayServices), pointer acceleration (IOHID) and Bluetooth power. They are the most likely to break with a macOS update and fail quietly when the symbol is missing.

## Distribution

GitHub releases with a DMG and a ZIP, updates through Sparkle 2 with an EdDSA-signed appcast, built and published by GitHub Actions. Builds are signed with a stable self-signed certificate so macOS keeps the granted permissions across updates; they are not notarized yet (that needs an Apple Developer account). The app is not sandboxed and uses the Hardened Runtime. Details in [RELEASING.md](RELEASING.md).

## Not planned

- Loading plug-ins at runtime, cloud sync, accounts
- Intel Macs and macOS versions before 26
- Fan control (fans are read, not driven)
- A video editor for recordings
- Reading other apps' notifications or tracking AI agents in the notch: macOS offers no public interface for either

## Relationship to Vorssaint

Sonary rebuilds features of Vorssaint under its own name, icon and colors. Code taken from Vorssaint keeps its original copyright and license headers and is listed in [NOTICE](../NOTICE) with its source path and commit. The layout of the menu and the settings (icon tabs, sidebar, cards) follows Vorssaint by the project owner's decision. Vorssaint's name, logo and branding are not used; its name appears only as a factual source credit in `NOTICE` and the docs, never in the app's interface or in promotional text.

## Known risks

- Undocumented sensor and display interfaces (Monitor, Display, Mouse).
- Music control depends on the players' AppleScript support.
- Several permission dialogs from macOS can make the first start feel noisy.
