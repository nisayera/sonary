# Feature parity checklist

What Sonary aims to cover, written in our own words. Sonary is its own app: Vorssaint's name, icon
and branding stay out of it (see its `TRADEMARKS.md`), reused GPL code keeps its headers and is
listed in `NOTICE`.

Legend: `[x]` done · `[~]` partly done, the gap is named · `[ ]` open.
Status checked against the code on `main` at version 0.10.0.

## Audio
- [ ] Per-app volume mixer (boost above 100 %, favourites, no audio driver)
- [ ] Per-app output routing
- [~] Output device switching — switching and volume are there; no shortcut, no automatic volume drop when headphones are unplugged
- [~] Microphone — preferred input and the ⌃⌥M mute shortcut are there; no input level meter, no on-screen indicator
- [ ] Stop Music.app from launching itself on the media keys

## System monitoring
- [~] CPU, GPU, memory, temperatures, battery, history graphs — all there; no list of energy-heavy apps
- [ ] Fan control (manual speed, temperature curves, live RPM)
- [~] Configurable menu bar readouts — CPU, memory, network, battery, temperature; no fan speed, no battery time
- [~] Network — live traffic is there; no session totals, no local IP, no speed test
- [x] Alerts for sustained CPU load, temperature, memory pressure, low disk space and low battery

## Windows and Dock
- [~] Window switcher — every window, with search and raise on ⌃⌥Tab; no live previews, no filters
- [~] Window layouts — halves, quarters, thirds, maximize, centre on ⌃⌥ shortcuts; no screen edges, no modifier-drag, no moving between displays, no restore
- [ ] Dock window previews across Spaces
- [ ] Dock icon click actions
- [ ] Green button fills the screen without a new Space
- [ ] Fixed Space order
- [ ] Quit apps when their last window closes
- [~] ⌘Q protection — press twice to quit; no ⌘W, no hold mode, no per-app rules

## Keyboard and mouse
- [~] Text snippets with variables — {date}, {time}, {clipboard}, searchable in the command bar; they land in the clipboard instead of being typed
- [x] Smooth scrolling, adjustable
- [x] Pointer acceleration off, restored when the module stops or after a crash
- [x] Linear scrolling with a fixed number of lines per notch
- [ ] Focus follows mouse
- [x] Mouse scroll direction independent of the trackpad
- [ ] Horizontal scrolling while holding a key
- [x] Back and forward on the side buttons
- [~] Actions for extra buttons — a fixed list of actions and any keyboard shortcut; no side wheels, no button-drag gestures
- [ ] Three-finger trackpad press as middle click
- [x] Per-app exclusions for the mouse features
- [x] Double-click filter for worn buttons
- [ ] Keyboard debounce
- [x] Super Key from Caps Lock or a right modifier, with a tap action and per-app exceptions
- [ ] Central shortcut manager

## Clipboard, files and links
- [~] Clipboard history — text, with search and pinning; no images, no files, no rich preview
- [ ] Auto-clear the clipboard after a delay, on sleep or on lock
- [~] Paste as plain text on ⌘⌥⇧V — it replaces the clipboard with the plain text instead of leaving it untouched
- [x] Drag shelf for files
- [~] Finder helpers — copy path, open Terminal, new text file; no ⌘X cut-and-paste, no F2 rename, no paste image as PNG
- [x] Strip tracking parameters from copied links
- [ ] DMG installer helper

## Everyday tools
- [~] Notch island — music, calendar, timer, downloads, accessory batteries, scroll gestures, simulated on displays without a notch; no notifications, lyrics, equalizer, camera or files
- [ ] AI agent tracking in the island
- [~] Command bar — apps, snippets and Sonary's tools; no files, clipboard, menu commands, calculator, units, emoji or scripts
- [x] Quick toggles: dark mode, desktop icons, empty Trash, eject disks, lock screen
- [x] Quit-apps list
- [~] Radial menu on ⌃⌥R with a free choice of actions; no profiles, no submenus
- [~] Scratchpad; no tabs, no Markdown preview or export
- [ ] Cleaning mode (input lock, black screen)

## Capture
- [ ] Unified capture selector with magnifier
- [~] Screenshots through the system tool; no scrolling capture, annotation, redaction, backgrounds, pinning or sharing
- [ ] Screen recording
- [ ] Camera preview mirror
- [~] Offline text recognition; no QR codes
- [~] Colour picker; copies HEX only, no RGB, HSL or SwiftUI formats
- [ ] Media tools (video compression, image conversion, watermarks, GIF)

## App management
- [~] Update checker — Homebrew formulae and casks; no App Store, no Sparkle feeds of other apps
- [~] Cleaner for caches, logs and Xcode build data; no schedule
- [ ] Messaging-app download cleanup with retention rules
- [x] Uninstaller with a review of what is left behind
- [x] Homebrew manager
- [x] Port manager with stop

## Energy and display
- [~] Keep awake with a timer or until turned off; no closed-lid, app, power or display conditions
- [~] Per-display brightness through the system's own control, with dimming where it offers none; no DDC for external monitors
- [ ] XDR extra brightness
- [ ] Bluetooth off during sleep
