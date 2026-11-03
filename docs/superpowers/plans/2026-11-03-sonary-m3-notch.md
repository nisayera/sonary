# Sonary M3 (Notch / Dynamic Island) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Modul „Notch" (`id = "notch"`): eine Insel am Notch (auf Displays ohne Notch simuliert), die beim Überfahren aufklappt und Musik, Kalender, Timer, Downloads und Zubehör-Akkus zeigt. Release 0.4.0.

**Architecture:** Neues Paket `Notch`. Geometrie, Auf-/Zuklapp-Zustand, Musik-Info-Parser, Timer, Download-Auswahl und Akku-Parser sind reine Funktionen/Werttypen mit Tests. Fenster (`NSPanel`), verteilte Benachrichtigungen, AppleScript-Steuerung, EventKit, Ordnerüberwachung und IOKit sind dünne Hüllen.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSPanel`, `DistributedNotificationCenter`, `NSAppleScript`, EventKit, `DispatchSource` (Ordner), IOKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-03-sonary-design.md` (M3, Abschnitt 6)

## Global Constraints
- Wie M2 (macOS 26, arm64, Swift 6 strict, null Warnungen, keine Force-Unwraps, EN/DE-Strings im Paket-Katalog, Tests mit Swift Testing, CI baut).
- Modul selbst braucht keine Berechtigung. Kalender fragt beim Einschalten des Kalender-Widgets (EventKit Full Access), Musik-Steuerung löst den Automation-Dialog beim ersten Klick aus, Downloads den Ordner-Dialog.
- Info.plist: `NSAppleEventsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSDownloadsFolderUsageDescription`; Entitlement `com.apple.security.automation.apple-events`.
- Version 0.4.0 / Build 400.
- MediaRemote wird nicht benutzt (für Fremd-Apps eingeschränkt).

## Review Focus
1. Display ohne Notch (Mac mini): simulierte Insel mittig oben, Höhe = Menüleiste.
2. Bildschirm wechselt/angeschlossen/abgezogen: Insel springt auf den richtigen Bildschirm.
3. Musik-App nicht installiert oder beendet: keine Steuerbefehle starten die App ungefragt; Widget zeigt „Nichts wird abgespielt".
4. Kalender-Zugriff abgelehnt: Widget zeigt Hinweis statt Fehler.
5. Partielle Downloads (`.download`, `.crdownload`, `.part`) und versteckte Dateien erscheinen nicht.

---

### Task 1: Paket, Geometrie, Zustand
- Create `Packages/Notch` (wie Mouse), `NotchGeometry.swift`, `NotchState.swift`, Tests.
- `public struct NotchGeometry` mit `static func notchSize(screenFrame: CGRect, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?, menuBarHeight: CGFloat) -> CGSize` (echter Notch: Breite = Bildschirm − linke − rechte Hilfsfläche, Höhe = safeAreaTop; sonst simuliert 190 × Menüleistenhöhe, mindestens 24) und `static func panelFrame(size: CGSize, screenFrame: CGRect) -> CGRect` (oben mittig, pixelgenau gerundet).
- `public enum NotchPresentation { case collapsed, expanded }`, `public struct NotchState` mit `mutating func hoverChanged(_ inside: Bool)`, `mutating func clicked()`, `var presentation`; Klick heftet an (bleibt offen trotz Verlassen), zweiter Klick löst.
- Tests: `realNotchUsesAuxiliaryAreas`, `noNotchIsSimulated`, `simulatedHeightHasMinimum`, `panelFrameIsTopCentered`, `hoverExpandsAndCollapses`, `clickPinsOpen`, `secondClickUnpins`.

### Task 2: Musik
- `NowPlaying.swift`: `public struct NowPlaying: Equatable, Sendable { title, artist, album, isPlaying, player: MusicPlayer }`, `public enum MusicPlayer: String { case music, spotify }` mit Bundle-ID und Benachrichtigungsname; `public func parseNowPlaying(_ info: [String: Any], player:) -> NowPlaying?` („Player State" Playing/Paused/Stopped; Stopped → nil).
- `NowPlayingCenter` (@MainActor @Observable): beobachtet `com.apple.Music.playerInfo` und `com.spotify.client.PlaybackStateChanged`; Steuerung `playPause/next/previous` per AppleScript nur, wenn die App läuft.
- Tests: `parsesMusicPlaying`, `parsesSpotifyPaused`, `stoppedIsNil`, `missingTitleIsNil`.

### Task 3: Timer, Downloads, Zubehör-Akku
- `CountdownTimer` (rein): `start(duration:at:)`, `remaining(at:)` (nie negativ), `isFinished(at:)`, `cancel()`. Tests: `remainingCountsDown`, `neverNegative`, `cancelClears`.
- `public func recentDownloads(_ entries: [DownloadEntry], limit: Int) -> [DownloadEntry]` (neueste zuerst, ohne versteckte und partielle Dateien). Tests: `newestFirst`, `skipsPartialAndHidden`, `respectsLimit`.
- `public func parseAccessoryBatteries(_ services: [[String: Any]]) -> [AccessoryBattery]` (Schlüssel `Product`, `BatteryPercent`, Werte 0…100, ohne Prozent übersprungen, nach Name sortiert, doppelte Namen einmal). Tests: `parsesProducts`, `skipsWithoutPercent`, `clampsPercent`, `deduplicates`.

### Task 4: Fenster, Ansichten, Einstellungen, Verdrahtung
- `NotchPanel`/`NotchWindowController` (Level statusBar+1, `.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle`, transparent, nicht aktivierend), folgt `NSApplication.didChangeScreenParametersNotification`.
- `NotchView`: zugeklappt schwarze Form in Notch-Größe (mit kleinem Musik-Indikator), aufgeklappt Tabs (`IconTabBar`) für aktive Widgets; Federanimation, Reduce Motion → Fade.
- `NotchSettings` (Codable, Store wie Mouse) mit Widget-Schaltern (Musik, Kalender, Timer, Downloads, Akkus; alle an außer Kalender) und `showOnScreensWithoutNotch` (an). Tests: `settingsRoundTrip`, `defaultsAsDocumented`.
- `NotchSettingsView` (Karten), Strings EN/DE + Lokalisierungstest, `AppModel` registriert `NotchModule`, Info.plist-Schlüssel und Entitlement in `project.yml`, `ModuleInfo`-Text, Version 0.4.0, PERMISSIONS/README/CI.

### Manuelle Prüfung
Insel erscheint mittig oben (Mac mini: simuliert), klappt beim Überfahren auf, Musik aus Music/Spotify mit Steuerung, Kalender nach Erlaubnis, Timer klingelt, Downloads lassen sich öffnen, AirPods/Maus-Akku sichtbar.
