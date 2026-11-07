# Feature parity checklist

Everything Vorssaint does, and how far Sonary has got with it, written in our own words. Sonary is
its own app: Vorssaint's name, icon and branding stay out of it (see its `TRADEMARKS.md`), reused
GPL code keeps its headers and is listed in `NOTICE`.

The list follows Vorssaint's feature catalog (84 features in eight groups) and the options inside
them, as of vorssaint-utils commit `1cdbd59` (2026-10-29). Status checked on 2026-11-07 against Sonary's `main`
with the open pull requests #32 to #41 merged.

Legend: `[x]` done · `[~]` partly done, the gap is named · `[ ]` open · `[-]` not planned, with the reason.

At a glance, 113 entries: 95 done, 8 partly done, 4 open, 6 not planned.

## Windows and Dock
- [x] Window switcher — every window, word-by-word search, a filter per app and per display, live previews (optional, so it works without Screen Recording), a large-icon mode with one icon per app, raise on ⌃⌥Tab or by taking over ⌘Tab
- [x] Window layouts — halves, quarters, thirds, maximize, centre, fill the screen, next display and put back, on ⌃⌥ shortcuts
- [x] Layout by dragging — to a screen edge, and with ⌃⌘ to move or resize from anywhere in the window; sixths; apps excluded from layouts
- [~] Dock previews — window previews across Spaces when the pointer rests on an icon, click to raise, close or minimize from the preview, apps that pause previews; missing: moving or snapping a window from the preview
- [x] Dock icon clicks — cycle the app's windows, minimize them all, show them all or hide the app, only for the app in front
- [x] Maximize — a layout fills the screen, menu bar strip included, without a new Space (⌃⌥B), and the green window button can do the same, with apps that keep the macOS behaviour
- [x] Fixed Space order — stops macOS rearranging Spaces, through the Dock's own preference, and puts the previous setting back when it is turned off
- [x] Quit apps when their last window closes, with apps that never quit
- [x] ⌘Q and ⌘W protection — press twice, hold, or add an extra modifier, per-app rules, a bar while holding
- [x] Focus follows mouse, with a short delay so passing over a window does not steal focus

## Mouse and keyboard
- [x] Smooth scrolling, adjustable
- [x] Linear scrolling with a fixed number of lines per notch
- [x] Pointer acceleration off, restored when the module stops or after a crash
- [x] Scroll direction independent of the trackpad, vertical and horizontal each on their own
- [x] Horizontal scrolling while holding a key you choose
- [~] Zoom with the scroll wheel while holding a key (sends ⌘= and ⌘-); missing: pinch zoom
- [x] Back and forward on the side buttons
- [x] Actions for extra buttons — a fixed list (Mission Control, App Exposé, show desktop, Launchpad) and any recorded keyboard shortcut, a sideways wheel, push gestures while a button is held
- [x] Three-finger trackpad press as middle click
- [x] Per-app exclusions for the mouse features
- [x] Double-click filter for worn buttons
- [x] Keyboard debounce
- [x] Super Key from Caps Lock or a right modifier, with a tap action and per-app exceptions
- [x] Text snippets with {date}, {time}, {clipboard} and custom formats such as {date:yyyy-MM-dd}, searchable in the command bar, typed where the cursor is or put on the clipboard, and expanded from a short trigger as you type it
- [x] Central shortcut manager — every Sonary shortcut on one page, recordable, resettable, clashes refused; the window switcher can take over ⌘Tab

## Clipboard, files and links
- [x] Clipboard history — text, images and files, search, pinning, thumbnails, also in the command bar, a quick panel on its own shortcut with a preview of the whole entry and pasting by number
- [x] Auto-clear after a delay, on sleep or on lock
- [x] Paste as plain text on ⌘⌥⇧V, putting the original clipboard back afterwards
- [x] Shelf — files, text and links dropped on the panel or the notch, shared from it, and a shelf that appears next to the pointer while files are dragged
- [x] Finder cut and paste — buttons in the panel, and ⌘X and ⌘V in Finder itself
- [x] Finder rename — a button in the panel, and F2 in Finder
- [x] Save the clipboard image into the front Finder folder as a PNG
- [x] Copy path, open Terminal here, new text file
- [x] Clean links — tracking parameters stripped from copied links, or from a link pasted into the panel by hand
- [x] Disk image installer — a mounted image with one app offers to copy it into /Applications, ejects itself and can move the downloaded image to the Trash

## Sound
- [~] Per-app volume mixer — the panel shows which apps are playing; missing: per-app volume, boosting quiet apps past 100 %, pinning and ordering apps. Needs a Core Audio process tap
- [ ] Per-app output — music on the speakers while a call uses the headset (same process tap)
- [x] Output switching with ⌃⌥O and a volume drop when headphones are unplugged
- [x] Device priority — ordered lists of outputs and inputs; one that connects is switched to, a device picked by hand stays until then
- [x] Microphone — choose the input, set its level, mute on ⌃⌥M, a level meter, a dot on screen while it is live
- [x] Keep Music.app from launching on the media keys

## Energy and display
- [x] Keep awake — for 15 minutes, 1 or 2 hours, until a time you pick or until turned off, while an app runs, while plugged in, while a display is attached, with the lid closed; an optional pointer nudge for apps that watch for idle, and a cup in the menu bar while active
- [~] Per-display brightness — the system's control, software dimming where there is none, shortcuts in 16, 32 or 64 steps, dimming below a display's minimum; missing: DDC for external monitors (needs a monitor to test the private I²C calls against)
- [~] XDR extra brightness — asks panels with headroom above white to open it; needs trying on a real XDR display
- [x] Bluetooth off during sleep, switched back on at wake only if Sonary switched it off
- [x] Wallpaper — a gallery of the system's pictures and your own folders, set on every display or one

## Everyday tools
- [x] Command bar — apps, open windows, snippets, scripts, files through Spotlight, Sonary's tools, clipboard history, the front app's menu commands, calculator, units, emoji
- [x] Quick panel — a floating palette of favourite tools next to the pointer, on a shortcut
- [x] Quick toggles — dark mode, desktop icons, empty Trash, eject disks, lock screen
- [x] Quit apps — every open app with Quit and Force Quit, quit all or all but the front app, with apps kept running
- [x] Radial menu on ⌃⌥R with a free choice of Sonary's actions, apps, files and keyboard shortcuts, and extra rings
- [x] Scratchpad with tabs, Markdown preview and export, in a floating window of its own and in the notch
- [x] Cleaning mode — every screen goes black until Escape or a click, system keys (brightness, media, Mission Control) are blocked too, or a small badge over a visible screen instead

## Capture and create
- [x] One capture selector — dimmed screen, magnifier, live pixel size, switching between screenshot, text, colour and recording with 1 to 4
- [x] Screenshots — area through the system tool or Sonary's selector (window through the system tool), the whole screen with a click, pinning, scrolling capture, the Share menu
- [x] Screenshot editor — arrows, boxes, highlights, text, redaction that destroys the pixels, crop, watermark, export on a background
- [x] Screen recording to MP4 through ScreenCaptureKit, of the whole display or a region, with the Mac's sound and the microphone
- [-] Recording editor (trim, cut, automatic zoom, blur) — out of scope, see ARCHITECTURE.md
- [-] Expiring share links for captures and recordings — needs a server, and Sonary stays offline
- [x] Camera preview mirror, a floating round window
- [x] Offline text recognition, including QR codes and barcodes
- [x] Colour picker with HEX, RGB, HSL and SwiftUI formats
- [x] Media tools — image conversion (PNG, JPEG, HEIC, TIFF) with downscaling and a watermark, video shrinking, GIFs from videos, text from image files, trimming a video and removing its sound

## App management
- [x] App updates — Homebrew formulae and casks, App Store apps through mas, apps in /Applications with a Sparkle feed, and Update all for what Sonary can update itself
- [x] Cleaner for caches, logs and Xcode build data, weekly or monthly on a schedule
- [x] Messenger downloads — folder tidying with a retention rule per folder, finished downloads sorted into a folder of their own, repeated downloads to the Trash
- [x] Uninstaller with a review of what is left behind
- [x] Homebrew — outdated formulae and casks, upgrade one or all, search, install and remove
- [x] Port manager with stop
- [x] Kill process — Quit and Force Quit for apps, and a list of all processes by CPU with search

## Dynamic Island (notch)
- [x] Island at the notch, simulated on displays without one
- [x] Music — title, artist, play, pause, skip for Music and Spotify
- [x] Calendar — today's events, and a month to browse with the events of any day
- [x] Timer
- [x] Downloads from a folder you choose
- [x] Accessory batteries, with a notice once one falls to 20 %
- [x] File shelf in the island
- [x] Camera in the island
- [x] Scroll gestures to open, close and change tracks
- [x] Choosing what the island shows — widgets on and off and in your order, volume and brightness controls, the scratchpad's note
- [-] Notifications from other apps — macOS offers no public way to read them
- [-] Lyrics — needs a licensed lyrics service
- [-] Up next — neither Music nor Spotify shares its queue with other apps
- [ ] Live equalizer — needs the same audio tap as the mixer
- [-] AI agent activity (Claude, Codex, Copilot: limits, tokens, live work) — Vorssaint reads each tool's local logs and signs in to their accounts; out of scope for now, see ARCHITECTURE.md
- [ ] Watch — turn part of a window into a live activity that alerts when it changes
- [ ] Companion — a small animated character in the island

## System monitor
- [x] CPU, GPU, memory and history graphs
- [x] Temperatures — CPU, GPU and battery on their own
- [x] Battery and power — level, charging, time left, health, cycle count, power draw
- [x] Disk — space used, read and write activity
- [x] Network — live traffic, session totals, local address, speed test on demand
- [x] The busiest apps
- [x] Per-core CPU view
- [x] Detail view for one metric: a click opens its five minutes with a scale
- [x] Connected USB devices
- [~] Fans — speed read and shown; manual speed and curves are not planned (see ARCHITECTURE.md; Vorssaint's are in beta)
- [x] Menu bar readouts — CPU, memory, network, disk, battery with time left, temperature, fan speed, as text or bars, together or each as its own menu bar item
- [x] Alerts for sustained CPU load, temperature, memory pressure, low disk space and low battery

## The app itself
- [~] Feature switches — ten modules on and off, each with its own options, and starter bundles; Vorssaint switches each of its 84 features separately
- [x] Permissions page — what each permission is for, what uses it, whether it is granted, a way into System Settings
- [x] Settings window with a sidebar and search
- [x] Settings search — finds pages and single options by their text
- [x] Menu panel with icon tabs, laid out the way the original is
- [x] Reordering and hiding the panel's tabs
- [x] A shortcut that opens the menu panel
- [x] Adjustable surface: Liquid Glass, frosted or solid; Reduce Transparency always wins
- [x] Onboarding window that explains permissions, open at login
- [x] One-click updates through Sparkle, with a signed appcast
- [x] What's new after an update: a line in the panel with a link to the release notes
- [x] Settings export and import, to move to another Mac
- [x] Removing all of Sonary's data from inside the app
- [~] Languages — English and German; Vorssaint has about fifteen, and a language picker inside the app
