# Feature parity checklist

Everything Vorssaint does, and how far Sonary has got with it, written in our own words. Sonary is
its own app: Vorssaint's name, icon and branding stay out of it (see its `TRADEMARKS.md`), reused
GPL code keeps its headers and is listed in `NOTICE`.

The list follows Vorssaint's feature catalog (84 features in eight groups) and the options inside
them, as of vorssaint-utils commit `1cdbd59` (2026-10-29). Status checked against Sonary's `main`
on 2026-11-07, including the redesign from #26.

Legend: `[x]` done · `[~]` partly done, the gap is named · `[ ]` open · `[-]` not planned, with the reason.

At a glance, 113 entries: 45 done, 46 partly done, 17 open, 5 not planned.

## Windows and Dock
- [~] Window switcher — every window, word-by-word search, a filter per app, live previews (optional, so it works without Screen Recording), raise on ⌃⌥Tab; missing: a filter by display, a large-icon mode with one icon per app, taking over ⌘Tab
- [x] Window layouts — halves, quarters, thirds, maximize, centre, fill the screen, next display and put back, on ⌃⌥ shortcuts
- [~] Layout by dragging — to a screen edge, and with ⌃⌘ to move or resize from anywhere in the window; missing: sixths, apps excluded from layouts
- [~] Dock previews — window previews across Spaces when the pointer rests on an icon, click to raise; missing: close, move or snap a window from the preview, apps excluded from previews
- [~] Dock icon clicks — cycle the app's windows, minimize them all or show them all; missing: hide the app
- [~] Maximize — a layout fills the screen, menu bar strip included, without a new Space (⌃⌥B); missing: making the green window button do this, with apps that keep the macOS behaviour
- [~] Fixed Space order — stops macOS rearranging Spaces, through the Dock's own preference; missing: putting the previous setting back when it is turned off
- [x] Quit apps when their last window closes, with apps that never quit
- [~] ⌘Q and ⌘W protection — press twice or hold, per-app rules, a bar while holding; missing: requiring an extra modifier as a third way
- [x] Focus follows mouse, with a short delay so passing over a window does not steal focus

## Mouse and keyboard
- [x] Smooth scrolling, adjustable
- [x] Linear scrolling with a fixed number of lines per notch
- [x] Pointer acceleration off, restored when the module stops or after a crash
- [~] Scroll direction independent of the trackpad — vertical only; missing: reversing horizontal scrolling on its own
- [x] Horizontal scrolling while holding a key you choose
- [ ] Zoom with the scroll wheel while holding a key, and pinch zoom
- [x] Back and forward on the side buttons
- [x] Actions for extra buttons — a fixed list (Mission Control, App Exposé, show desktop, Launchpad) and any keyboard shortcut, a sideways wheel, push gestures while a button is held
- [x] Three-finger trackpad press as middle click
- [x] Per-app exclusions for the mouse features
- [x] Double-click filter for worn buttons
- [x] Keyboard debounce
- [x] Super Key from Caps Lock or a right modifier, with a tap action and per-app exceptions
- [~] Text snippets with {date}, {time} and {clipboard}, searchable in the command bar, typed where the cursor is or put on the clipboard; missing: expanding a short trigger as you type it, custom date formats
- [~] Central shortcut manager — every Sonary shortcut on one page, recordable, resettable, clashes refused; missing: taking over a macOS shortcut (for example ⌘Tab) while a feature is on

## Clipboard, files and links
- [~] Clipboard history — text, images and files, search, pinning, thumbnails, also in the command bar; missing: its own shortcut and quick panel, a preview of the whole entry, pasting an entry by shortcut
- [x] Auto-clear after a delay, on sleep or on lock
- [x] Paste as plain text on ⌘⌥⇧V, putting the original clipboard back afterwards
- [~] Shelf — files dropped on the panel or the notch; missing: a shelf that appears near the pointer while dragging, text and links on it, sharing from it
- [~] Finder cut and paste — buttons in the panel; missing: ⌘X and ⌘V working in Finder itself
- [~] Finder rename — a button in the panel; missing: F2 in Finder
- [x] Save the clipboard image into the front Finder folder as a PNG
- [x] Copy path, open Terminal here, new text file
- [~] Clean links — tracking parameters stripped from copied links; missing: cleaning a link by hand in the panel
- [~] Disk image installer — a mounted image with one app offers to copy it into /Applications and eject itself; missing: moving the downloaded image to the Trash afterwards

## Sound
- [~] Per-app volume mixer — the panel shows which apps are playing; missing: per-app volume, boosting quiet apps past 100 %, pinning and ordering apps. Needs a Core Audio process tap
- [ ] Per-app output — music on the speakers while a call uses the headset (same process tap)
- [x] Output switching with ⌃⌥O and a volume drop when headphones are unplugged
- [ ] Device priority — switch to your preferred output and input automatically when they appear
- [~] Microphone — choose the input, mute on ⌃⌥M, a level meter, a dot on screen while it is live; missing: setting the input level
- [x] Keep Music.app from launching on the media keys

## Energy and display
- [~] Keep awake — for 15 minutes, 1 or 2 hours or until turned off, while an app runs, while plugged in, while a display is attached, with the lid closed; missing: a free end time, nudging the pointer for apps that watch for idle, an icon in the menu bar while active
- [~] Per-display brightness — the system's control, software dimming where there is none, shortcuts; missing: DDC for external monitors, finer steps for the brightness keys, dimming below a monitor's minimum
- [~] XDR extra brightness — asks panels with headroom above white to open it; needs trying on a real XDR display
- [x] Bluetooth off during sleep, switched back on at wake only if Sonary switched it off
- [ ] Wallpaper — a gallery to browse and set desktop pictures

## Everyday tools
- [~] Command bar — apps, snippets, scripts, files through Spotlight, Sonary's tools, clipboard history, the front app's menu commands, calculator, units, emoji; missing: open windows
- [ ] Quick panel — a floating palette of favourite tools on a shortcut
- [x] Quick toggles — dark mode, desktop icons, empty Trash, eject disks, lock screen
- [~] Quit apps — every open app with Quit and Force Quit; missing: quit all, quit all but the front app, apps never quit that way
- [~] Radial menu on ⌃⌥R with a free choice of Sonary's actions and extra rings; missing: apps, files and keyboard shortcuts as wedges
- [~] Scratchpad with tabs, Markdown preview and export; missing: a floating window, the scratchpad in the notch
- [~] Cleaning mode — every screen goes black until Escape or a click; missing: blocking system keys (brightness, media, Mission Control) too, a small indicator instead of a black screen

## Capture and create
- [~] One capture selector — dimmed screen, magnifier, live pixel size, feeding the capture tools; missing: switching between screenshot, recording, text and colour inside the selector
- [~] Screenshots — area through the system tool or Sonary's selector (window through the system tool), pinning, scrolling capture; missing: whole screen in one step, the Share menu
- [~] Screenshot editor — arrows, boxes, highlights, text, redaction that destroys the pixels, export on a background; missing: crop, watermark
- [~] Screen recording to MP4 through ScreenCaptureKit; missing: system audio and microphone tracks
- [-] Recording editor (trim, cut, automatic zoom, blur) — out of scope, see ARCHITECTURE.md
- [-] Expiring share links for captures and recordings — needs a server, and Sonary stays offline
- [x] Camera preview mirror, a floating round window
- [x] Offline text recognition, including QR codes and barcodes
- [x] Colour picker with HEX, RGB, HSL and SwiftUI formats
- [~] Media tools — image conversion (PNG, JPEG, HEIC, TIFF) with downscaling and a watermark, video shrinking, GIFs from videos; missing: text from image files, simple video edits

## App management
- [~] App updates — Homebrew formulae and casks, plus apps in /Applications with a Sparkle feed; missing: App Store apps, updating all managed apps at once
- [x] Cleaner for caches, logs and Xcode build data, weekly or monthly on a schedule
- [~] Messenger downloads — folder tidying with a retention rule per folder; missing: sorting stable downloads into a folder of their own, spotting repeated downloads
- [x] Uninstaller with a review of what is left behind
- [~] Homebrew — outdated formulae and casks, upgrade one; missing: search, install and remove
- [x] Port manager with stop
- [~] Kill process — Quit and Force Quit for apps; missing: a list of all processes, including background ones

## Dynamic Island (notch)
- [x] Island at the notch, simulated on displays without one
- [x] Music — title, artist, play, pause, skip for Music and Spotify
- [~] Calendar — today's events; missing: browsing the month
- [x] Timer
- [x] Downloads from a folder you choose
- [~] Accessory batteries; missing: a warning once a battery falls to 20 %
- [x] File shelf in the island
- [x] Camera in the island
- [x] Scroll gestures to open, close and change tracks
- [~] Choosing what the island shows — widgets on and off; missing: their order, everyday controls (volume, brightness) in the island
- [-] Notifications from other apps — macOS offers no public way to read them
- [-] Lyrics — needs a licensed lyrics service
- [ ] Up next — the player's queue
- [ ] Live equalizer — needs the same audio tap as the mixer
- [-] AI agent activity (Claude, Codex, Copilot: limits, tokens, live work) — Vorssaint reads each tool's local logs and signs in to their accounts; out of scope for now, see ARCHITECTURE.md
- [ ] Watch — turn part of a window into a live activity that alerts when it changes
- [ ] Companion — a small animated character in the island

## System monitor
- [x] CPU, GPU, memory and history graphs
- [~] Temperatures — the hottest sensor; missing: CPU, GPU and battery shown on their own
- [~] Battery and power — level, charging, time left; missing: health, cycle count, power draw (read, not shown)
- [~] Disk — space used; missing: read and write activity
- [x] Network — live traffic, session totals, local address, speed test on demand
- [x] The busiest apps
- [ ] Per-core CPU view
- [ ] Detail view for one metric with a longer graph
- [ ] Connected USB devices
- [~] Fans — speed read and shown; manual speed and curves are not planned (see ARCHITECTURE.md; Vorssaint's are in beta)
- [~] Menu bar readouts — CPU, memory, network, battery, temperature, fan speed as text; missing: usage bars, battery time, each metric as its own menu bar item
- [x] Alerts for sustained CPU load, temperature, memory pressure, low disk space and low battery

## The app itself
- [~] Feature switches — ten modules on and off; Vorssaint switches each of its 84 features separately and offers starter bundles
- [x] Permissions page — what each permission is for, what uses it, whether it is granted, a way into System Settings
- [x] Settings window with a sidebar and search
- [~] Settings search — finds pages; missing: finding the single option inside a page
- [x] Menu panel with icon tabs, laid out the way the original is
- [ ] Reordering and hiding the panel's tabs
- [ ] A shortcut that opens the menu panel
- [x] Adjustable surface: Liquid Glass, frosted or solid; Reduce Transparency always wins
- [x] Onboarding window that explains permissions, open at login
- [x] One-click updates through Sparkle, with a signed appcast
- [ ] What's new after an update
- [ ] Settings export and import, to move to another Mac
- [ ] Removing all of Sonary's data from inside the app
- [~] Languages — English and German; Vorssaint has about fifteen, and a language picker inside the app
