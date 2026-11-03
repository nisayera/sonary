# Sonary – Design-Spec

Stand: 2026-11-03 · Status: Entwurf zur Durchsicht

## 1. Ziel
Sonary ist eine native, quelloffene Mac-Menüleisten-App („Mac-Werkzeugkasten"), die rund 70 der etwa 90 Funktionen von Vorssaint nachbaut – in eigenem Namen, eigenem Design und mit dem Liquid-Glass-Look von macOS 26. Jede Funktion ist ein einzeln aktivierbares Modul.

## 2. Rahmenbedingungen
- Name: **Sonary**
- Sprache/UI: Swift 6 (strict concurrency), SwiftUI, AppKit nur wo nötig
- Plattform: **nur macOS 26 (Tahoe) und nur Apple Silicon**
- Lizenz: **GPL-3.0-or-later**. Code aus Vorssaint (GPL-3.0) darf übernommen werden; in jeder übernommenen Datei bleiben die **originalen Copyright- und Lizenz-Header erhalten** (GPL-Pflicht); zusätzlich dokumentiert `NOTICE` Herkunft (Pfad, Commit) jeder übernommenen Datei.
- Nicht übernommen: Name, Logo und Look von Vorssaint (separat per TRADEMARKS.md geschützt). Sonary hat eigenes Branding und Design. Der Name „Vorssaint" wird nicht in Werbung, Store-/Landingpage-Texten oder der App-UI verwendet, nur als sachliche Quellenangabe in `NOTICE`/`README`.
- Verteilung: GitHub-Release (DMG, signiert + notarisiert), Sparkle-Updates, Homebrew-Cask. Kein Bezahlmodell.
- Signierung/Notarisierung braucht ein **Apple Developer Program-Konto (99 $/Jahr)** (Developer-ID-Zertifikat). Für Entwicklung und Selbstbau aus dem Quellcode ist das nicht nötig.
- Sprachen der UI: Englisch + Deutsch.

## 3. Nicht-Ziele (YAGNI)
Plug-in-Nachladen zur Laufzeit, Cloud-Sync, Intel-Unterstützung, Fallback-Design für ältere macOS-Versionen, Fan Control, Recording-Editor (die Screen-Recording-Berechtigung wird trotzdem für Dock Preview in M6 und Screenshot/OCR/Color Picker in M8 gebraucht), Media-Kompression, Mitlesen von System-Benachrichtigungen in der Notch (keine offizielle API), AI-Agents-Tracking, Companion, Fixed Space Order, Extra Brightness.

## 4. Architektur
```
Sonary/
  App/            @main, MenuBarExtra, Settings-Szene
  Packages/
    SonaryCore/   SonaryModule-Protokoll, ModuleRegistry, PermissionBroker, Settings, Logger
    SonaryUI/     Design-System: Glass-Komponenten, Tokens, Animationen
    Monitor/ Mouse/ Notch/ ...   ein Swift-Package-Target pro Funktion
  Tests/  docs/  NOTICE  LICENSE
```
- **SonaryModule**: `id`, `title`, `icon`, `requiredPermissions`, `start()`, `stop()`, `settingsView`. Die `ModuleRegistry` startet nur aktivierte Module; Zustand in UserDefaults.
- **PermissionBroker**: Berechtigungen werden erst beim Aktivieren eines Moduls erklärt und angefragt. `stop()` räumt vollständig auf (z. B. Mausbeschleunigung zurücksetzen).
- **Autostart**: Schalter in den Einstellungen über `SMAppService.mainApp` (Login-Item).
- **Onboarding**: Beim ersten Start ein Fenster, das aus den Modulen die nötigen Berechtigungen sammelt (dedupliziert), erklärt und der Reihe nach über den PermissionBroker anfragt; jederzeit aus den Einstellungen erneut aufrufbar.
- **Fehlerisolation**: Ein fehlerhaftes Modul wird abgeschaltet; die App läuft weiter.
- **Concurrency**: UI auf `@MainActor`, Hardware- und Event-Zugriffe in eigenen Actors.
- **UI**: `MenuBarExtra` (Fenster-Stil) + Einstellungsszene mit Seitenleiste (ein Eintrag pro Modul).
- **Design**: `.glassEffect()` / `GlassEffectContainer` nur für schwebende Elemente (Notch, Panels, Popover); Listen/Einstellungen mit Systemmaterial. 8-pt-Raster, SF Symbols, Federanimationen < 500 ms, Reduce Motion → Opacity-Fade, Reduce Transparency respektiert, VoiceOver-Labels, Dark Mode.

## 5. Roadmap (je Meilenstein eigener Spec→Plan→Bau-Zyklus)
| # | Meilenstein | Inhalt |
|---|---|---|
| M0 | Fundament | Menüleisten-App, Modulsystem, Einstellungen, Design-System, CI, Autostart beim Login (`SMAppService`), Onboarding-Fenster für Berechtigungen, String Catalog (`.xcstrings`) EN + DE |
| M1 | Systemmonitor | CPU, GPU, RAM, Netzwerk, Disk, Akku, Verlauf, Menüleisten-Anzeige, Warnungen |
| M2 | Maus & Tastatur | Linear-/Smooth-Scrolling, Beschleunigung aus, Scrollrichtung, Seitentasten, Tasten-Mapping, Ausnahme-Apps, Click-Filter, Super Key, Snippets |
| M3 | Notch / Dynamic Island | Musik, Kalender, Timer, Downloads, Gesten, Zubehör-Akku |
| M4 | Zwischenablage & Dateien | Verlauf, Plain-Text-Paste, Shelf, Clean URL, Finder-Shortcuts |
| M5 | App-Verwaltung | Cleaner, Uninstaller, Homebrew, Port Manager, Kill Process, App-Updates |
| M6 | Fenster & Dock | Window Layout, Maximize, Dock Clicks, App-Switcher, Quit-Schutz (Dock Preview: Bildschirmaufnahme) |
| M7 | Sound & Display | Mixer pro App, Output-Switcher, Mikrofon-Mute, Keep Awake, Helligkeit |
| M8 | Tools | Command Bar, Quick Panel, Screenshot, OCR, Color Picker, Radial Menu, Scratchpad |

Reihenfolge M4–M8 ist änderbar. Zielumfang ≈ 70 von ≈ 90 Vorssaint-Funktionen.

## 6. Detaildesign M1–M3
### M1 Systemmonitor
- `MetricsSampler` (Actor) tastet 1×/s ab, liefert per `AsyncStream`, Ringpuffer ≈ 5 min Historie.
- Quellen: CPU `host_processor_info`, RAM `host_statistics64`, Netzwerk `getifaddrs`, Disk `URLResourceValues` + IOKit, Akku IOKit. GPU/Temperaturen: IOReport + HID-Sensoren (undokumentiert → Risiko; hier ist Code-Übernahme aus Vorssaint besonders sinnvoll).
- UI: Popover mit Glass-Karten und Swift-Charts-Graphen; konfigurierbares Menüleisten-Label; Warnungen via UserNotifications.
- Berechtigungen: keine.
### M2 Maus & Tastatur
- `CGEventTap` auf eigenem Thread (Bedienungshilfen/Eingabeüberwachung).
- Linear Scrolling: Deltas pro Rastenschritt normieren; Trackpads (Phase/Momentum) unberührt.
- Smooth Scrolling: interpolierte Scroll-Events über `CADisplayLink` (`NSScreen.displayLink(target:selector:)`, ab macOS 14; kein `CVDisplayLink`).
- Beschleunigung aus: IOHID; Originalwert wird gespeichert und bei Ausschalten, Beenden und nächstem Start nach Absturz wiederhergestellt.
- Ausnahmen pro App (Bundle-ID der vordersten App); Tasten-Mapping für Seiten-/Zusatztasten.
### M3 Notch
- Randloses `NSPanel` über der Menüleiste; Notch-Erkennung via `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea`, simulierte Notch auf Displays ohne.
- SwiftUI-Inhalt mit `.glassEffect()`; Auf-/Zuklappen per Federanimation (`matchedGeometryEffect`).
- Musik: ScriptingBridge (Music, Spotify) + verteilte Benachrichtigungen (MediaRemote ist ab macOS 15.4 für Fremd-Apps eingeschränkt).
- Kalender: EventKit. Timer: lokal. Downloads: FSEvents auf gewählten Ordner.

## 7. Qualität & Tests
- Null Compiler-Warnungen, strict concurrency sauber, keine Force-Unwraps im Produktivcode.
- Datenquellen hinter Protokollen, in Tests durch Fakes ersetzt (Swift Testing). Event-Tap-Logik (Linear-Berechnung, Mapping, Ausnahmen) als reine Funktionen testbar.
- Pro Meilenstein ein UI-Smoke-Test; Sensoren manuell auf dem Entwicklungs-Mac.
- Privacy Manifest, minimale Entitlements; Hardened Runtime; App ist nicht sandboxed (Direktvertrieb).

## 8. Offene Risiken
Undokumentierte Sensor-APIs (M1), Musik-Anbindung (M3), Berechtigungs-UX (mehrere TCC-Dialoge).
