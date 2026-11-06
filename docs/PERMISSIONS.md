# Permissions

Sonary asks for a permission only when you turn on the module or the feature that needs it. Modules you leave off never ask for anything.

"Module" in the table means the permission is checked when the module starts; without it the module does not start and shows why in its settings page. Every other permission is asked for by macOS the first time you use the feature.

| Module | Feature | Permission | What for |
| --- | --- | --- | --- |
| Monitor | — | none | Reads CPU, memory, network, disk, battery, sensors and fans through system interfaces |
| Monitor | Alerts | Notifications | Warns about sustained load, heat, memory pressure, low disk space and low battery |
| Mouse | Module | Accessibility | Watches and changes mouse events: scrolling, extra buttons, click filter, gestures |
| Keyboard | Module | Accessibility | Reads and changes key presses while the Super Key is held, and for key debounce |
| Notch | — | none | The island itself needs nothing |
| Notch | Music | Automation (Music, Spotify) | Play, pause and skip |
| Notch | Calendar | Calendars (full access) | Today's events |
| Notch | Downloads | Downloads folder | The newest files |
| Notch | Camera | Camera | The camera preview in the island |
| Clipboard | — | none | Reads the clipboard to keep the history; entries marked as passwords or transient are skipped |
| Clipboard | Paste as plain text | Accessibility | Presses ⌘V for you |
| Clipboard | Finder helpers | Automation (Finder, System Events) | Copy path, open Terminal, new file, cut and paste, rename |
| Apps | — | none | Cleaning and uninstalling only move files to the Trash; ports through `lsof`, updates through Homebrew and the apps' update feeds |
| Windows | Module | Accessibility | Moves and raises windows, protects ⌘Q and ⌘W, reads the Dock |
| Windows | Switcher and Dock previews | Screen Recording | Pictures of the windows |
| Display | — | none | Brightness through the system's own control; a dimming layer where there is none |
| Sound | — | none | Switches audio devices through Core Audio; keep awake through a power assertion |
| Sound | Media-key guard | Accessibility | Catches the media keys so they go to a player that is already running |
| Sound | Microphone level | Microphone | The level meter in the sound panel |
| Tools | Screenshots, text from screen, recording | Screen Recording | Captures the screen through `screencapture` or ScreenCaptureKit |
| Tools | Typed snippets, menu commands, scrolling capture | Accessibility | Types text, reads the front app's menus, scrolls for you |
| Tools | Quick toggles | Automation (System Events, Finder) | Dark mode, desktop icons, empty Trash, eject disks |
| Tools | Camera preview | Camera | The floating camera window |

## Changes Sonary makes to the system

- **Pointer acceleration** (Mouse) is changed only while the module runs. The original value is restored when you turn the option or the module off, when Sonary quits, and on the next launch after a crash.
- **Fixed Space order** (Windows) changes the Dock's own preference, the same one as "Automatically rearrange Spaces based on most recent use" in System Settings, and restarts the Dock. It is a system setting, so it stays when Sonary is off; switch it back in Sonary or in System Settings.
- **Bluetooth off during sleep** (Display) switches Bluetooth back on at wake, and only if Sonary was the one that switched it off.
