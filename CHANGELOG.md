# Changelog

All notable changes to Sonary are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Every entry becomes the text of its
[GitHub release](https://github.com/nisayera/sonary/releases) and the notes Sonary shows before
an update; see [docs/RELEASING.md](docs/RELEASING.md#release-notes).

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

[0.83.6]: https://github.com/nisayera/sonary/releases/tag/v0.83.6
