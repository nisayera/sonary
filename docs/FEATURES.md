# Feature parity checklist

Everything Vorssaint does, and how far Sonary has got with it, written in our own words. Sonary is
its own app: Vorssaint's name, icon and branding stay out of it (see its `TRADEMARKS.md`), reused
GPL code keeps its headers and is listed in `NOTICE`.

The list follows Vorssaint's feature catalog (84 features in eight groups), as of vorssaint-utils
commit `63b2fee` (2026-11-10). Status checked on 2026-11-10 against Sonary 0.80.0.

The first part goes feature by feature. The second part, [Option by option](#option-by-option), goes
through every preference Vorssaint stores and lists the ones Sonary has no counterpart for, down to
single switches inside a feature that is otherwise done.

Legend: `[x]` done · `[~]` partly done, the gap is named · `[ ]` open · `[-]` not planned, with the reason.

At a glance, 113 entries: 96 done, 7 partly done, 4 open, 6 not planned.
Below that, 120 groups of single options Vorssaint has and Sonary does not.

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
- [x] Keep awake (its own module and panel tab) — for 15 minutes, 1 or 2 hours, until a time you pick or until turned off, while an app runs, while plugged in, while a display is attached, with the lid closed; an optional pointer nudge for apps that watch for idle, and a cup in the menu bar while active
- [x] Per-display brightness — the system's control, DDC/CI for regular external monitors (from Vorssaint, private I²C calls via CoreDisplay), software dimming where neither reaches, shortcuts in 16, 32 or 64 steps, dimming below a display's minimum
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
- [~] Feature switches — eleven modules on and off, each with its own options, and starter bundles; Vorssaint switches each of its 84 features separately
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

## Option by option

What Vorssaint lets you set and Sonary does not, taken from Vorssaint's preference keys (about 950 of
them; state it only keeps for itself, such as window positions and migration markers, is left out).
A feature marked done above can still appear here: the feature works, this option of it is missing.
Nothing in this part is counted in the totals at the top.

### The app itself
- [ ] Language picker inside the app (Sonary follows the system language), and the other thirteen languages
- [ ] Light, dark or system appearance for Sonary alone
- [ ] Liquid Glass for the island set apart from the panels (Sonary has one choice for both)
- [ ] Another symbol for the menu bar icon, and hiding the icon while readouts show
- [ ] Beta update channel
- [ ] Release notes shown before an update is downloaded, and a What's New window afterwards (Sonary shows one line in the panel)
- [ ] A read-only settings file that sets chosen preferences at launch, for managing several Macs
- [ ] Reordering the sections inside a panel tab, and the single tools and toggles in them (Sonary reorders and hides whole tabs)
- [ ] Choosing which single controls appear in the panel (Vorssaint has a switch for each of about twenty)

### Keep awake
- [ ] Default duration for the panel's switch
- [ ] Stop below a battery level
- [ ] Start when Sonary launches, and carry a running session over a restart
- [ ] Right-click on the menu bar icon toggles it
- [ ] Keep the Mac awake but let the display sleep
- [ ] Several apps as a condition (Sonary takes one), and "all conditions" instead of "any"
- [ ] Pause while the screen is locked
- [ ] A keyboard shortcut
- [ ] The colour and symbol of the menu bar icon while active, and a countdown next to it
- [ ] How often the pointer is nudged (Sonary: fixed)
- [ ] Dim the built-in display to zero while the lid is closed

### Mouse and keyboard
- [ ] Scroll speed: hold a key to multiply the wheel's distance
- [ ] Smooth scrolling tuned in three parts — step, response, coast (Sonary has one smoothness slider)
- [ ] Pinch zoom on the wheel
- [ ] Hold a button and drag to switch Spaces
- [ ] Middle click from a light three- or four-finger tap (Sonary: the physical press only)
- [ ] Focus follows mouse: the delay, raising the window or not, waiting until the pointer stops, apps it leaves alone (Sonary: a fixed 0.35 s, always raises)
- [ ] Super Key: which modifiers it holds (Sonary: always all four), Caps Lock as its tap action
- [ ] Key debounce with a window per key

### Window switcher
- [ ] A second shortcut for the windows of the app in front, and a third for all windows
- [ ] One entry per app with its windows merged
- [ ] Where minimized and hidden windows go in the list, and whether full-screen windows and apps without windows appear
- [ ] Rules per app
- [ ] Only the current Space, only the display under the pointer
- [ ] Which display the switcher opens on, the most items per row, the size of the previews
- [ ] A delay before it appears, instant selection without animation, ignoring the pointer for selection
- [ ] The row of shortcut hints, pinning the search field

### Dock
- [ ] Previews: open delay, background opacity, thumbnail size, only the current Space, order by creation, the close button quitting the app, keeping an auto-hidden Dock visible
- [ ] Moving or snapping a window from its preview

### Window layouts
- [ ] Two thirds (left, centre, right), the centre half, thirds and quarters stacked top to bottom, quarters side by side
- [ ] Maximize with a margin, in percent
- [ ] A gap between snapped windows, in points
- [ ] Space kept free for Stage Manager
- [ ] Pressing left or right again cycles half, two thirds, one third
- [ ] Previous display (Sonary has next display)
- [ ] Focus the window in a direction, move the pointer to another display
- [ ] Screen edges: which zones are active and what each one does
- [ ] Dragging a snapped window away gives it its old size back
- [ ] Hiding single layouts from the grid

### Quit and close protection
- [ ] Different behaviour for ⌘Q and ⌘W (Sonary uses one for both)
- [ ] How long to hold, how fast to press twice, which extra modifier
- [ ] All apps except a list, instead of only a list
- [ ] Turning the hint on screen off
- [ ] Menu bar apps that may quit when their last window closes

### Clipboard, shelf and Finder
- [ ] History kept for a number of days
- [ ] Leaving out text that looks like a password or a key (Sonary skips what apps mark as concealed)
- [ ] The latest copy shown next to the menu bar icon
- [ ] Cards or list in the history window, source app icons, the window remembering its place and size
- [ ] Clear when the display sleeps
- [ ] Clean links: your own parameters, parameters for one site, switching built-in ones off
- [ ] Shelf: a shortcut, shake to open, a drop zone, where it docks, opening from the screen edge, closing or emptying after a drop, adding the Finder selection, apps that never open it, items kept across restarts
- [ ] A hint on screen for Finder cut and paste; another key for rename
- [ ] Disk images: install into the user's Applications folder, reveal the app afterwards or not

### Sound
- [ ] Mixer options (with the mixer itself): hide silent apps, hide chosen apps, order, Finder in the list
- [ ] Volume in finer steps on the volume keys
- [ ] Output switching limited to chosen devices
- [ ] The volume after unplugging as a percentage (Sonary: a quarter, on or off)
- [ ] A badge on the menu bar icon while the microphone is muted; the mute surviving a restart
- [ ] Media keys opening another player in place of Music
- [ ] Volume of the speakers built into a monitor, over DDC, also on the volume keys

### Display
- [ ] The Mac's own brightness keys acting on the display under the pointer (Sonary has shortcuts of its own)
- [ ] A brightness overlay on screen while it changes
- [ ] Keyboard backlight: shortcuts, a slider, a quick toggle
- [ ] Software dimming forced for a monitor that has DDC
- [ ] Switching a display off
- [ ] Wallpaper: filters, hiding single pictures

### Everyday tools
- [ ] Quick toggles: keyboard light, hidden files, display off, screen saver, quit all apps, microphone mute
- [ ] Disks that Eject all leaves alone
- [ ] Command bar: compact mode, learning from what you pick, switching kinds of result off, your own names for results, pinned and hidden results, web links, a shortcut per result, emoji skin tone, folders to search and names to ignore, uninstalling and ending processes from the bar
- [ ] Scratchpad: notes that expire, closing on a click outside, opacity, text size
- [ ] Snippets: a menu of all snippets on a shortcut, a sound when one expands
- [ ] Radial menu: at the pointer or mid-screen, on a mouse button, hold or toggle
- [ ] Shortcuts for the camera mirror, quit all apps and quit all but the front one
- [ ] Colour picker: HEX without the #

### Capture and create
- [ ] Shortcuts for the whole screen, for the last region again, and for the recent captures; a list of recent captures
- [ ] Freezing the screen while selecting, hiding Sonary's own windows, the pointer in the picture, a delay
- [ ] Where screenshots are saved, in which subfolder, under which name pattern and numbering
- [ ] What happens after a capture: copy, save, editor, add to the shelf; a floating preview for a few seconds
- [ ] Selector: the last region shown again, windows highlighted, magnifier zoom
- [ ] Editor: blur with levels and styles, spotlight, arrow styles, stickers, shadows, tool order and tool shortcuts, saved backgrounds and watermarks
- [ ] Scrolling capture that scrolls by itself, on its own shortcut
- [ ] Recording: countdown, quality, save folder
- [ ] Text recognition: joining lines, QR codes on or off
- [ ] Media tools: video quality, size limit, frame rate, codec and target file size; GIF frame rate, width, loops and target size; images with quality, metadata removal, exact sizes, a logo as watermark, a rename pattern, a subfolder, saved profiles

### App management
- [ ] Cleaner: daily schedule at a time you pick, a notice when done, old screenshots by age
- [ ] Messenger downloads: categories, a notice, files to leave alone, how the sorted folder is laid out, what happens to duplicates, undo
- [ ] Uninstaller: offering leftovers when an app is dragged to the Trash, select all
- [ ] Processes: related ones grouped, sorted by memory, name or PID
- [ ] Homebrew: dependencies grouped, the log of the last operation
- [ ] App updates: checked daily or weekly with a notice, an online catalog for apps without a feed, rules per app

### Dynamic Island
- [ ] Size and shape: preset sizes, custom width and height, the silhouette, an outline, a translucent background, haptics
- [ ] Which display it lives on, a shortcut that opens it
- [ ] Full screen: hidden, or shown on hover; hidden until hover everywhere
- [ ] Close delay, returning to a home tab, which tab is home
- [ ] Replacing the system's overlays for volume, brightness, keyboard light, input source, microphone, battery and track changes
- [ ] Music: other players and browsers, covers from the browser, volume in the island, a preferred player
- [ ] Timer: stopwatch and pomodoro with their lengths, a sound, hiding the countdown
- [ ] Calendar: countdown to the next event, time left in the current one, week numbers, calendars to leave out
- [ ] Low battery: thresholds, an early warning, tinting the island
- [ ] Clipboard, capture controls, the quick panel and the command bar inside the island; keep awake as an activity
- [ ] Over the lock screen, with lock sounds
- [ ] Shown or hidden in screenshots and recordings

### System monitor
- [ ] Menu bar: GPU, single temperatures, accessory batteries and connected devices as readouts; the order of readouts; bar colours and their thresholds; compact or classic labels; memory and disk shown in other ways; upload first
- [ ] Memory counted as used or as app memory
- [ ] Network speed in bits
- [ ] Network use per app
- [ ] Disk: S.M.A.R.T. state
- [ ] Power: charger details, accessory batteries in the power section
- [ ] Uptime
- [ ] Alerts: your own thresholds and how often an alert may repeat; battery temperature
- [ ] The scale of the graphs

