# Contributing to Sonary

Thanks for helping! Sonary is in early development, so the best way to start is to open an issue before a larger PR.

## Setup
- macOS 26 Tahoe, Apple Silicon, Xcode 26
- `git clone https://github.com/nisayera/sonary.git && cd sonary && brew install xcodegen && xcodegen generate && open Sonary.xcodeproj` (the Xcode project is generated from `project.yml`)

## Guidelines
- Swift 6 with strict concurrency, SwiftUI first, AppKit only where needed.
- Each feature lives in its own module and must be fully disabled (no timers, no permissions) when switched off.
- Add every user-facing string to the String Catalog, in English and German.
- Keep PRs small and focused, describe what and why, and add screenshots for UI changes.
- Run the tests and make sure the build has no warnings.

## Reusing code
Sonary is GPL-3.0-or-later. Code from other projects must use a compatible license. Keep the original copyright headers and add an entry to `NOTICE`.

## Reporting bugs
Use the bug report template and include your macOS version and Sonary version.
