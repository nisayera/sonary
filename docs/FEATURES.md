# Feature parity checklist

What Sonary aims to cover, written in our own words. Sonary is its own app: Vorssaint's name, icon
and branding stay out of it (see its `TRADEMARKS.md`), reused GPL code keeps its headers and is
listed in `NOTICE`.

Legend: `[x]` done · `[~]` partly done, the gap is named · `[ ]` open.
Status checked against the code at version 0.11.0.

## Audio
- [ ] Per-app volume mixer (boost above 100 %, favourites, no audio driver)
- [ ] Per-app output routing
- [x] Output device switching, with a ⌃⌥O shortcut and an automatic volume drop when headphones are unplugged
- [~] Microphone — preferred input and the ⌃⌥M mute shortcut are there; no input level meter, no on-screen indicator
- [ ] Stop Music.app from launching itself on the media keys

## System monitoring
- [x] CPU, GPU, memory, temperatures, battery, history graphs and the busiest apps
- [ ] Fan control (manual speed, temperature curves, live RPM)
- [~] Configurable menu bar readouts — CPU, memory, network, battery, temperature, and battery time in the panel; no fan speed
- [~] Network — live traffic, totals for this session and the local address; no speed test
- [x] Alerts for sustained CPU load, temperature, memory pressure, low disk space and low battery

## Windows and Dock
- [~] Window switcher — every window, with search and raise on ⌃⌥Tab; no live previews, no filters
- [~] Window layouts — halves, quarters, thirds, maximize, centre, move to the next display and put back, on ⌃⌥ shortcuts; no screen edges, no modifier-drag
- [ ] Dock window previews across Spaces
- [ ] Dock icon click actions
- [ ] Green button fills the screen without a new Space
- [ ] Fixed Space order
- [ ] Quit apps when their last window closes
- [~] ⌘Q and ⌘W protection — press twice, with per-app rules; no hold mode

## Keyboard and mouse
- [~] Text snippets with variables — {date}, {time}, {clipboard}, searchable in the command bar; they land in the clipboard instead of being typed
- [x] Smooth scrolling, adjustable
- [x] Pointer acceleration off, restored when the module stops or after a crash
- [x] Linear scrolling with a fixed number of lines per notch
- [ ] Focus follows mouse
- [x] Mouse scroll direction independent of the trackpad
- [x] Horizontal scrolling while holding a key you choose
- [x] Back and forward on the side buttons
- [~] Actions for extra buttons — a fixed list of actions and any keyboard shortcut; no side wheels, no button-drag gestures
- [ ] Three-finger trackpad press as middle click
- [x] Per-app exclusions for the mouse features
- [x] Double-click filter for worn buttons
- [x] Keyboard debounce
- [x] Super Key from Caps Lock or a right modifier, with a tap action and per-app exceptions
- [ ] Central shortcut manager

## Clipboard, files and links
- [x] Clipboard history — text, images and files, with search, pinning and thumbnails
- [x] Auto-clear after a delay, on sleep or on lock
- [x] Paste as plain text on ⌘⌥⇧V, putting the original clipboard back afterwards
- [x] Drag shelf for files
- [~] Finder helpers — copy path, open Terminal, new text file; no ⌘X cut-and-paste, no F2 rename, no paste image as PNG
- [x] Strip tracking parameters from copied links
- [ ] DMG installer helper

## Everyday tools
- [~] Notch island — music, calendar, timer, downloads, accessory batteries, scroll gestures, simulated on displays without a notch; no notifications, lyrics, equalizer, camera or files
- [ ] AI agent tracking in the island
- [~] Command bar — apps, snippets, Sonary's tools, a calculator, unit conversion and emoji; no files, clipboard, menu commands or scripts
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
- [x] Offline text recognition, including QR codes and barcodes
- [x] Colour picker with HEX, RGB, HSL and SwiftUI formats
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
