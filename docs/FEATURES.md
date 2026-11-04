# Feature parity checklist

What Sonary aims to cover, written in our own words. Sonary is its own app: Vorssaint's name, icon
and branding stay out of it (see its `TRADEMARKS.md`), reused GPL code keeps its headers and is
listed in `NOTICE`.

Legend: `[x]` done · `[~]` partly done, the gap is named · `[ ]` open.
Status checked against the code at version 0.20.0.

## Audio
- [ ] Per-app volume mixer (boost above 100 %, favourites, no audio driver)
- [ ] Per-app output routing
- [x] Output device switching, with a ⌃⌥O shortcut and an automatic volume drop when headphones are unplugged
- [x] Microphone — preferred input, the ⌃⌥M mute shortcut, a level meter in the panel and a dot on screen while it is live
- [x] Stop Music.app from launching itself on the media keys — Sonary passes the key to a player that is already running

## System monitoring
- [x] CPU, GPU, memory, temperatures, battery, history graphs and the busiest apps
- [~] Fan speeds are read and shown, in the panel and the menu bar; no manual speed, no curves
- [x] Configurable menu bar readouts — CPU, memory, network, battery, temperature and fan speed
- [x] Network — live traffic, totals for this session, the local address and a speed test on demand
- [x] Alerts for sustained CPU load, temperature, memory pressure, low disk space and low battery

## Windows and Dock
- [x] Window switcher — every window, with word-by-word search, a filter per app, live previews and raise on ⌃⌥Tab
- [x] Window layouts — halves, quarters, thirds, maximize, centre, fill the screen, move to the next display and put back, on ⌃⌥ shortcuts, by dragging to a screen edge, and by holding ⌃⌘ to move or resize from anywhere in the window
- [x] Dock window previews across Spaces, when the pointer rests on an icon
- [x] Dock icon click actions — cycle the app's windows, minimize them all or show them all
- [x] A layout that fills the screen, menu bar strip included, without a new Space (⌃⌥B)
- [x] Fixed Space order — stops macOS rearranging Spaces by most recent use, through the Dock's own preference
- [x] Quit apps when their last window closes
- [x] ⌘Q and ⌘W protection — press twice or hold the keys, with per-app rules and a bar while holding

## Keyboard and mouse
- [x] Text snippets with variables — {date}, {time}, {clipboard}, searchable in the command bar, typed where the cursor is or put on the clipboard
- [x] Smooth scrolling, adjustable
- [x] Pointer acceleration off, restored when the module stops or after a crash
- [x] Linear scrolling with a fixed number of lines per notch
- [x] Focus follows mouse, with a short delay so passing the pointer over a window does not steal focus
- [x] Mouse scroll direction independent of the trackpad
- [x] Horizontal scrolling while holding a key you choose
- [x] Back and forward on the side buttons
- [x] Actions for extra buttons — a fixed list of actions and any keyboard shortcut, a sideways wheel, and push gestures while a button is held
- [x] Three-finger trackpad press as middle click, read from the touches the click itself carries
- [x] Per-app exclusions for the mouse features
- [x] Double-click filter for worn buttons
- [x] Keyboard debounce
- [x] Super Key from Caps Lock or a right modifier, with a tap action and per-app exceptions
- [x] Central shortcut manager — every Sonary shortcut on one settings page, recordable, resettable, with clashes refused

## Clipboard, files and links
- [x] Clipboard history — text, images and files, with search, pinning and thumbnails
- [x] Auto-clear after a delay, on sleep or on lock
- [x] Paste as plain text on ⌘⌥⇧V, putting the original clipboard back afterwards
- [x] Drag shelf for files
- [x] Finder helpers — copy path, open Terminal, new text file, save the clipboard image as a PNG, cut and move files, rename the selection
- [x] Strip tracking parameters from copied links
- [x] DMG installer helper — a mounted image with one app offers to copy it into /Applications and eject itself

## Everyday tools
- [~] Notch island — music, calendar, timer, downloads, accessory batteries, a file shelf, the camera, scroll gestures, simulated on displays without a notch; no notifications, lyrics or equalizer
- [ ] AI agent tracking in the island (no public way to see another app's agent activity)
- [x] Command bar — apps, snippets, scripts, files through Spotlight, Sonary's tools, the clipboard history, the front app's menu commands, a calculator, unit conversion and emoji
- [x] Quick toggles: dark mode, desktop icons, empty Trash, eject disks, lock screen
- [x] Quit-apps list
- [x] Radial menu on ⌃⌥R with a free choice of actions and extra rings, each a wedge that opens its own ring
- [x] Scratchpad with tabs, Markdown export and a preview
- [x] Cleaning mode: every screen goes black until Escape or a click

## Capture
- [x] Sonary's own capture selector: dimmed screen, magnifier, live pixel size, feeding every capture tool
- [~] Screenshots through the system tool or Sonary's selector, with pinning, an editor for arrows, boxes, highlights, text and redaction that really destroys the pixels, and export on a background; no scrolling capture
- [x] Screen recording to an MP4, through ScreenCaptureKit
- [x] Camera preview mirror, a floating round window from the tools tab
- [x] Offline text recognition, including QR codes and barcodes
- [x] Colour picker with HEX, RGB, HSL and SwiftUI formats
- [x] Media tools — image conversion (PNG, JPEG, HEIC, TIFF) with downscaling and a text watermark, video shrinking and animated GIFs

## App management
- [~] Update checker — Homebrew formulae and casks, plus apps in /Applications that ship a Sparkle feed; the App Store has no public interface for this
- [x] Cleaner for caches, logs and Xcode build data, weekly or monthly on a schedule
- [x] Folder tidying with a retention rule per folder, for a messenger's downloads
- [x] Uninstaller with a review of what is left behind
- [x] Homebrew manager
- [x] Port manager with stop

## Energy and display
- [x] Keep awake with a timer, until turned off, while an app runs, while plugged in, while a display is attached and with the lid closed
- [~] Per-display brightness through the system's own control, with dimming where it offers none; no DDC for external monitors
- [~] XDR extra brightness — asks panels with headroom above white to open it; needs trying on a real XDR display
- [x] Bluetooth off during sleep, switched back on at wake and only if Sonary switched it off

## The app itself
- [x] Menu panel with icon tabs and a settings window with a sidebar, laid out the way the original is
- [x] Adjustable surface: Liquid Glass, frosted or solid, and Reduce Transparency always wins
- [x] One-click updates through Sparkle, with a signed appcast
