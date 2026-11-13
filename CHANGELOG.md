# Changelog

All notable changes to Sonary are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Every entry becomes the text of its
[GitHub release](https://github.com/nisayera/sonary/releases) and the notes Sonary shows before
an update; see [docs/RELEASING.md](docs/RELEASING.md#release-notes).

## [0.94.0] - 2026-11-14

### Summary
The island takes the shape of boring.notch: wide and flat around the camera, opening on the player and the calendar.

### Changed
- The open island is 640 points wide and only as tall as the top row and one row of content, with square shoulders that grow out of the camera instead of a floating capsule. The capsule stays available in the island's settings.
- The island always opens on its home with the player and the calendar, also while music plays. The music page with lyrics and the queue is a click on the title away.
- The round buttons around the open island are gone while the new home is on; the top row holds Home, Shelf, the charge and Settings.
- A click on the cover brings the playing app to the front.

## [0.93.0] - 2026-11-13

### Summary
The open island gets a new home in the layout of boring.notch, and holding ⌘ shows the front app's keyboard shortcuts.

### Added
- Island: the home page shows the player on the left, with the cover over a glow of itself, the playing app's icon, title, artist, timeline and transport, and the week with the day's events on the right. The top row has tabs for Home and Shelf, the charge and a button to Settings.
- Island settings: "Home with player and calendar" switches between the new home and the earlier one with levels and shortcuts.
- Tools: a shortcut sheet. Hold ⌘ alone for a moment and every keyboard shortcut in the front app's menus appears, menu by menu; a click runs one. It can also open on a shortcut of its own. Off by default.

### Changed
- With the new home on, volume and brightness readings show in the island's top row while you press their keys, since the home no longer has sliders for them.

## [0.92.0] - 2026-11-11

### Summary
The menu bar panel is sorted by what things are about, not by module: Home, System, Network, Disks, Energy, Utilities, Control and Quick actions.

### Changed
- The panel's tabs are now Home (the overview), System (CPU, GPU, memory, connected devices, fans, brightness, sound and keep awake), Network (traffic, speed test, ports and a button to the network settings), Disks (storage and SMART), Energy (power and battery), Utilities, Control (mouse, keyboard and windows) and Quick actions. A tab shows while one of its modules is on.
- Settings › General › Menu panel orders and hides these tabs.
- Utilities are sorted into three groups: Capture, Apps & clean-up, and Tools.

### Added
- Settings › General: a colour well next to the accent swatches, for any accent colour of your own.
- A star in a function's settings puts its panel rows under Quick actions, above the quick toggles.

### Fixed
- The island no longer announces Vorssaint's updates. Sonary only looks for its own.
- A panel tab with a single section no longer shows its name twice.
- A module's settings page no longer slides out of the window when it has many panes: the panes are picked from a row that scrolls sideways.

## [0.91.0] - 2026-11-11

### Summary
Vorssaint's code is brought up to its 3.4.4 release. That carries the edge snapping option that came from this project, restoring a window's earlier size when you drag it away by its title bar, in its released form, along with Vorssaint's latest fixes.

### Changed
- The code taken over from Vorssaint is now that of Vorssaint 3.4.4.
- Edge snapping: a snapped window goes back to its earlier size only once you really drag it; a click on the title bar leaves it snapped. The option is in Windows, under Layouts, and starts off.

### Fixed
- Super Key no longer crashes when it reapplies the keyboard mapping at startup.
- Mic mute remembers each channel's level across updates and reconnects.
- Switching a monitor to software dimming cancels brightness commands still on their way to it.
- Volume keys for monitor speakers respect whether the feature is on.
- Copy as GIF checks again for a cancel before it touches the clipboard.

## [0.90.0] - 2026-11-11

### Summary
Vorssaint's features now look like Sonary, and the system monitor joins them. The pages and panel sections taken over in 0.83.6 are drawn with Sonary's cards, rows, icon badges and accent colour, and the monitor runs on Vorssaint's code as well, with fan control, your own alert thresholds and far more menu bar readouts. As before, none of this has been tried on a Mac inside Sonary yet, so please report what breaks.

### Added
- The system monitor is Vorssaint's: readouts in the menu bar for CPU, GPU, memory, network, disk, battery, temperatures, fans and accessories, together or each as its own item, with their order, colours and thresholds; memory, network and disk shown the way you choose; S.M.A.R.T. state, uptime and network use per app; alerts with your own thresholds.
- Fan control, with fixed speeds and curves (beta in Vorssaint, untested here).
- The monitor tab of the menu panel has Vorssaint's system, network, disk, power and fan sections, each folding on its own.
- Light or dark appearance for Sonary alone, and a choice of symbols for the menu bar icon, in General.
- A page in Tools for choosing which controls the panel's tool sections show.

### Changed
- Every settings page taken over from Vorssaint uses Sonary's cards, rows and icon badges, and Sonary's accent colour throughout, in the panel as well.
- The menu bar shows Sonary's icon and, next to it, the monitor's readouts as items of their own. A click on a readout opens the panel.
- Sonary's own monitor module is no longer used; its menu bar settings and alert choices are not carried over.
- Special editors (fan curve, radial menu, window layout editor, mascot) keep Vorssaint's layout for now and take only Sonary's colours.

### Fixed
- The 0.83.6 release could not be built: the optimizer did not finish on Vorssaint's code. That code is now compiled without optimization, and every pull request builds the release configuration.

## [0.83.7] - 2026-11-11

### Summary
An urgent fix: 0.83.6 started copies of itself without end. If you installed 0.83.6, quit every copy (Activity Monitor, or `killall -9 Sonary` in Terminal) before you open this version.

### Fixed
- **Sonary started copies of itself without end** as soon as the mouse or keyboard module was on: Vorssaint's code runs its own program again to put the pointer acceleration and the Super Key mapping back, and Sonary came up as a whole new app each time instead of doing that clean-up. These runs now clean up and exit, and Sonary refuses to start next to a running copy.
- A change to the pointer acceleration left behind by a crash is put back when the mouse module starts.

## [0.83.6] - 2026-11-11

### Summary
The biggest change since Sonary began: everything but the system monitor now runs on Vorssaint's code, taken over as it is, each group behind its Sonary module. On top of that come safer releases, release notes from this changelog, and the right permissions for microphone, camera and calendar. None of the taken-over features has been tried on a Mac inside Sonary yet, so expect rough edges and please report them.

### Added
- The Dynamic Island is Vorssaint's: music with queue and live equalizer, calendar, timer, downloads, accessory batteries, file shelf, gestures, sizes and shapes, also on displays without a notch.
- Mouse, keyboard, clipboard, apps, windows, display, sound, keep awake and tools run on Vorssaint's features, with all of their options. A module's switch installs its group of features; a module that is off loads nothing.
- Each of these modules shows Vorssaint's settings pages under Sonary's page header, and the shortcuts page lists every shortcut of the features that are on.
- The menu panel has Vorssaint's sections for the mixer, brightness, keep awake and the tools.

### Changed
- Settings of the replaced Sonary modules are not carried over; only whether a module was on is kept. Sonary's own modules stay in the source and are to return one at a time.
- Mouse, keyboard, clipboard, apps and windows have no panel tab of their own for now; the clipboard and window layouts are reached from the tools tab.
- The taken-over pages and panel sections still look like Vorssaint's, and its menu bar readouts and panel layout options have no effect in Sonary's panel.
- The clipboard history is stored in its own file in `~/Library/Application Support/Sonary/Clipboard`, readable only by you and left out of Time Machine backups, instead of in Sonary's preferences file. Your existing history moves there on the first launch, and it is no longer part of exported settings files.
- The clipboard history is saved in the background, so copying stays quick with a long history.
- The process list, fan speeds and USB devices in the monitor tab are only read while the tab is open, instead of every five seconds all the time.
- Media keys, the notch's player buttons, the quick actions and the Finder helpers talk to Music, Spotify and Finder in the background with a time limit. When Finder does not answer, the clipboard tab says so.
- Release pages and the notes before an update list what changed in the version, taken from this changelog, together with up-to-date installation steps.

### Fixed
- The microphone, the camera preview and the calendar could be refused by macOS in released builds whatever you allowed, because the app lacked the matching entitlements.
- A command sent to Music, Spotify or Finder while an earlier one hangs is dropped instead of running late.
- The panel and the notch no longer freeze for up to two minutes when Music, Spotify or Finder hang.
- App updates finds new versions for apps whose update feed lists version numbers as separate entries, Sonary's own feed included; before, many apps were never reported as out of date.
- App updates compares build numbers with build numbers and versions with versions, so it no longer reports updates that do not exist. Beta releases in a feed are left out.
- The installation guide describes the first launch on macOS 15 and later: **System Settings → Privacy & Security → Open Anyway**. Right-click → Open no longer works there.
- VoiceOver reads a name for the remaining icon-only buttons: removing a ring, undoing the last mark and resetting a shortcut.

### Security
- A release is only built after the tests passed for exactly that commit; before, every merge was released at once, even when the tests failed.
- Sparkle and the release tools are pinned to exact versions, so every release ships what was tested.
- The app and its embedded Sparkle components are signed one by one from the inside out instead of with `codesign --deep`, and the disk image is signed too.
- CI jobs only get write access where they need it.
- A second merge no longer cancels the tests of the first, which would have skipped its release.

[0.91.0]: https://github.com/nisayera/sonary/releases/tag/v0.91.0
[0.90.0]: https://github.com/nisayera/sonary/releases/tag/v0.90.0
[0.83.7]: https://github.com/nisayera/sonary/releases/tag/v0.83.7
[0.83.6]: https://github.com/nisayera/sonary/releases/tag/v0.83.6
