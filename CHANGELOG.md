# Changelog

All notable changes to Sonary are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Every entry becomes the text of its
[GitHub release](https://github.com/nisayera/sonary/releases) and the notes Sonary shows before
an update; see [docs/RELEASING.md](docs/RELEASING.md#release-notes).

## [0.83.5] - 2026-11-11

### Summary
A release about reliability, privacy and safer updates. Sonary no longer freezes when Music, Spotify or Finder stop answering, keeps the clipboard history out of its preferences file, finds updates for more of your apps and is only released after all tests have passed. Release pages and update notes now say what changed.

### Changed
- The clipboard history is stored in its own file in `~/Library/Application Support/Sonary/Clipboard`, readable only by you and left out of Time Machine backups, instead of in Sonary's preferences file. Your existing history moves there on the first launch, and it is no longer part of exported settings files.
- The clipboard history is saved in the background, so copying stays quick with a long history.
- The process list, fan speeds and USB devices in the monitor tab are only read while the tab is open, instead of every five seconds all the time.
- Media keys, the notch's player buttons, the quick actions and the Finder helpers talk to Music, Spotify and Finder in the background with a time limit. When Finder does not answer, the clipboard tab says so.
- Release pages and the notes before an update list what changed in the version, taken from this changelog, together with up-to-date installation steps.

### Fixed
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

[0.83.5]: https://github.com/nisayera/sonary/releases/tag/v0.83.5
