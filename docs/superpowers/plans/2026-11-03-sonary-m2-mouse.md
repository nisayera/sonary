# Sonary M2 (Maus & Tastatur) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Modul „Maus" (`id = "mouse"`), das Scrollen (linear, weich, Richtung), Zeigerbeschleunigung, Zusatztasten-Belegung, Click-Filter und Ausnahmen pro App bietet. Release 0.3.0.

**Architecture:** Neues Swift-Package `Mouse`. Alle Entscheidungen (Scroll-Rechnung, Weichzeichnen, Tasten-Mapping, Click-Filter, App-Ausnahmen) sind reine Funktionen/Werttypen und werden auf CI getestet. Die dünne Hardware-Schicht (CGEventTap auf eigenem Thread, Display-Link, IOHID-Beschleunigung) steht hinter Protokollen und wird manuell auf dem Mac geprüft.

**Tech Stack:** Swift 6 (strict concurrency), CoreGraphics `CGEventTap`, `NSScreen.displayLink`, IOKit HID, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-03-sonary-design.md` (Abschnitte M2 und 7)

## Global Constraints

- macOS 26, nur Apple Silicon (`ARCHS = arm64`), Swift 6 strict concurrency, null Warnungen, keine Force-Unwraps im Produktivcode.
- Lizenz GPL-3.0-or-later; aus Vorssaint übernommener Code behält Header und bekommt einen `NOTICE`-Eintrag (Pfad, Commit). Der Name „Vorssaint" erscheint nicht in UI oder Texten.
- Berechtigung `.accessibility` wird erst beim Aktivieren des Moduls angefragt; `stop()` räumt vollständig auf (Tap entfernt, Beschleunigung zurückgesetzt).
- UI-Texte Englisch + Deutsch im Paket-String-Catalog (`Sources/Mouse/Resources/Localizable.xcstrings`, `Text(..., bundle: .module)`).
- Datenquellen/Hardware hinter Protokollen, Tests mit Swift Testing; Build- und Testbefehle laufen auf CI (macOS 26).
- Versionsschema: `MARKETING_VERSION` 0.3.0, `CURRENT_PROJECT_VERSION` 300.
- **Scope-Entscheidung:** Super Key und Snippets aus der Spec-Zeile M2 wandern nach M8 (Tools), weil sie Tastatur-Ereignisse und eigene UI brauchen. Alles andere aus M2 ist enthalten.

## Review Focus

1. Trackpad- und Magic-Mouse-Ereignisse (Phase/Momentum gesetzt) bleiben unverändert, auch bei Richtung umkehren.
2. Das System deaktiviert den Event-Tap (Timeout/Nutzer-Eingabe): der Tap wird wieder eingeschaltet, nie dauerhaft tot.
3. App stürzt ab oder wird beendet, während die Beschleunigung aus ist: beim nächsten Start (und bei `stop()`) wird der gespeicherte Originalwert wiederhergestellt.
4. Bedienungshilfen werden entzogen oder fehlen: `start()` wirft, Modul wird deaktiviert, andere Module laufen weiter.
5. Vorderste App nicht ermittelbar (`nil`) oder Bundle-ID ohne Regel: es gelten die globalen Einstellungen.

---

### Task 1: Paket `Mouse`, Einstellungen und Modul-Hülle

**Files:**
- Create: `Packages/Mouse/Package.swift`, `Packages/Mouse/Sources/Mouse/MouseSettings.swift`, `Packages/Mouse/Sources/Mouse/MouseModule.swift`, `Packages/Mouse/Tests/MouseTests/MouseSettingsTests.swift`
- Modify: `project.yml` (Paket + Dependency), `App/AppModel.swift`

**Interfaces:**
- Produces: `public struct MouseSettings: Codable, Equatable, Sendable` mit `linearScroll: Bool`, `scrollLinesPerStep: Int` (Standard 3), `smoothScroll: Bool`, `smoothness: Double` (0…1, Standard 0.5), `reverseScroll: Bool`, `disableAcceleration: Bool`, `buttonMappings: [ButtonMapping]`, `clickFilterMilliseconds: Int` (0 = aus), `appOverrides: [String: AppOverride]` (Schlüssel Bundle-ID); `public struct AppOverride: Codable, Equatable, Sendable` mit optionalen Feldern `linearScroll`, `smoothScroll`, `reverseScroll`, `disabled: Bool`.
- Produces: `public struct MouseSettingsStore` mit `init(defaults: UserDefaults)`, `func load() -> MouseSettings`, `func save(_:)` (JSON unter Key `mouse.settings`; kaputte Daten → Standardwerte).
- Produces: `@MainActor @Observable public final class MouseModule: SonaryModule` (`id "mouse"`, `symbol "computermouse"`, `requiredPermissions [.accessibility]`, `public var settings: MouseSettings { didSet }` speichert).

- [ ] **Step 1: Write the failing test** — `MouseSettingsTests`: `roundTripsThroughStore` (speichern/laden gleich), `corruptDataFallsBackToDefaults` (Müll unter `mouse.settings` → `MouseSettings()`), `defaultsAreSafe` (alle Schalter aus, `scrollLinesPerStep == 3`, `clickFilterMilliseconds == 0`).
- [ ] **Step 2: Run to verify fail** — `cd Packages/Mouse && swift test` auf CI. Expected: FAIL, Typen nicht definiert.
- [ ] **Step 3: Implement** Paket (Struktur wie `Packages/Monitor/Package.swift`, `defaultLocalization: "en"`, Ressourcen `.process("Resources")`, Abhängigkeiten SonaryCore/SonaryUI), die Typen oben, und `MouseModule` mit leeren `start()/stop()`; `ButtonMapping` kommt in Task 4, bis dahin als leerer Platzhalter-Typ `public struct ButtonMapping: Codable, Equatable, Sendable {}` anlegen und in Task 4 ersetzen.
- [ ] **Step 4: Wire** `MouseModule` in `AppModel` (Property `mouse`, in `ModuleRegistry(modules: [monitor, mouse])`) und `project.yml` (Paket `Mouse`, Dependency im Target `Sonary`, `SonaryTests` bekommt `Mouse`).
- [ ] **Step 5: Run to verify pass** — `swift test` im Paket und `xcodebuild test`. Expected: PASS.
- [ ] **Step 6: Commit** — `feat(mouse): package, settings store and module shell`

### Task 2: Scroll-Rechnung (linear, Richtung, Trackpad-Erkennung)

**Files:**
- Create: `Packages/Mouse/Sources/Mouse/ScrollMath.swift`, `Packages/Mouse/Tests/MouseTests/ScrollMathTests.swift`

**Interfaces:**
- Produces: `public struct ScrollSample: Equatable, Sendable { var deltaY: Double; var deltaX: Double; var isContinuous: Bool; var scrollPhase: Int; var momentumPhase: Int }`
- Produces: `public func isWheelEvent(_ s: ScrollSample) -> Bool` (wahr nur für Rad-Ereignisse: `!isContinuous && scrollPhase == 0 && momentumPhase == 0`)
- Produces: `public func linearized(_ s: ScrollSample, linesPerStep: Int) -> ScrollSample` (jeder Rastenschritt wird zu ±`linesPerStep`, Betrag unabhängig von Rad-Beschleunigung, Vorzeichen bleibt; Trackpad unverändert)
- Produces: `public func reversed(_ s: ScrollSample) -> ScrollSample` (nur Rad-Ereignisse werden invertiert)

- [ ] **Step 1: Write the failing test** — `ScrollMathTests`: `wheelDetection` (Rad: true; `isContinuous`, `scrollPhase=4`, `momentumPhase=2`: false), `linearStepIsConstant` (Delta 1 und Delta 7 → beide ±3 bei `linesPerStep: 3`), `linearKeepsSign` (−2 → −3), `trackpadUnchangedByLinear`, `reverseFlipsWheelOnly` (Rad: Vorzeichen beider Achsen kippt; Trackpad gleich), `zeroDeltaStaysZero`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** die drei Funktionen als reine Funktionen (Delta 0 bleibt 0).
- [ ] **Step 4: Run to verify pass** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(mouse): pure scroll math`

### Task 3: Weiches Scrollen (Interpolator)

**Files:**
- Create: `Packages/Mouse/Sources/Mouse/SmoothScroller.swift`, `Packages/Mouse/Tests/MouseTests/SmoothScrollerTests.swift`

**Interfaces:**
- Produces: `public struct SmoothScroller: Sendable` mit `init(smoothness: Double)`, `mutating func add(deltaY: Double, deltaX: Double)` (Impuls, summiert), `mutating func step(dt: Double) -> (dy: Double, dx: Double)` (exponentielles Abklingen, Zeitkonstante aus `smoothness`, 0 → sofort alles), `var isIdle: Bool`.
- Contract: Die Summe aller `step`-Ausgaben konvergiert gegen die Summe aller Impulse (nichts geht verloren, nichts wird doppelt gescrollt); `step` ist unabhängig von der Framerate (gleiche Summe bei dt = 1/60 und 1/120 bis auf Rundung).

- [ ] **Step 1: Write the failing test** — `SmoothScrollerTests`: `totalEqualsImpulse` (Impuls 30, viele Schritte → Summe ≈ 30 innerhalb 0,01, danach `isIdle`), `frameRateIndependent` (60 vs. 120 Hz Summe nach 0,3 s gleich innerhalb 1 %), `zeroSmoothnessIsImmediate` (ein Schritt liefert den ganzen Impuls), `impulsesAccumulate` (zwei Impulse = Summe), `idleWhenEmpty`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** — Restbetrag `remaining`, pro Schritt Anteil `1 - exp(-dt / tau)` ausgeben, `tau = smoothness * 0.25` s; Restwerte unter 0,01 komplett ausgeben und `isIdle` setzen.
- [ ] **Step 4: Run to verify pass** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(mouse): smooth scroll interpolator`

### Task 4: Tasten-Mapping, Click-Filter und App-Ausnahmen

**Files:**
- Create: `Packages/Mouse/Sources/Mouse/ButtonMapping.swift`, `ClickFilter.swift`, `AppRules.swift`, `Tests/MouseTests/ButtonMappingTests.swift`, `ClickFilterTests.swift`, `AppRulesTests.swift`
- Modify: `MouseSettings.swift` (Platzhalter `ButtonMapping` entfernen)

**Interfaces:**
- Produces: `public enum ButtonAction: Codable, Equatable, Sendable { case none, back, forward, missionControl, appExpose, showDesktop, launchpad, keyboardShortcut(keyCode: UInt16, modifiers: UInt64) }`
- Produces: `public struct ButtonMapping: Codable, Equatable, Sendable { var button: Int; var action: ButtonAction }` und `public func action(forButton button: Int, in mappings: [ButtonMapping]) -> ButtonAction?` (Tasten 0–2 = links/rechts/mitte sind nie belegbar → `nil`; unbelegt → `nil`)
- Produces: `public struct ClickFilter: Sendable` mit `init(milliseconds: Int)`, `mutating func shouldDrop(button: Int, timestampNanoseconds: UInt64) -> Bool` (Mouse-Down innerhalb des Fensters nach vorherigem Down derselben Taste wird verworfen; 0 = nie verwerfen; Zeitrückgang verwirft nicht)
- Produces: `public func effectiveSettings(_ base: MouseSettings, bundleID: String?) -> MouseSettings` (Override-Felder ersetzen globale; `disabled == true` schaltet linear, smooth, reverse, Mappings und Click-Filter aus; `nil`/unbekannt → `base`)

- [ ] **Step 1: Write the failing test** — Mapping: `buttonsZeroToTwoNeverMapped`, `unmappedButtonReturnsNil`, `mappedButtonReturnsAction`; ClickFilter: `dropsSecondClickInsideWindow` (50 ms Fenster, Down bei 0 und 30 ms → zweites verworfen), `keepsClickAfterWindow`, `zeroDisablesFilter`, `differentButtonsIndependent`, `clockGoingBackwardsDoesNotDrop`; AppRules: `nilBundleUsesBase`, `unknownBundleUsesBase`, `overrideReplacesField`, `disabledTurnsEverythingOff`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** die Typen/Funktionen mit exakten Signaturen oben.
- [ ] **Step 4: Run to verify pass** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(mouse): button mapping, click filter and per-app rules`

### Task 5: Zeigerbeschleunigung mit sicherer Wiederherstellung

**Files:**
- Create: `Packages/Mouse/Sources/Mouse/PointerAcceleration.swift`, `Packages/Mouse/Tests/MouseTests/PointerAccelerationTests.swift`

**Interfaces:**
- Produces: `public protocol AccelerationControlling: Sendable { func read() -> Double?; func write(_ value: Double) -> Bool }`
- Produces: `public struct IOHIDAccelerationControl: AccelerationControlling` (echte Implementierung über `NXOpenEventStatus()` und `IOHIDGetAccelerationWithKey`/`IOHIDSetAccelerationWithKey` mit `kIOHIDMouseAccelerationType`; Wert `-1` = aus)
- Produces: `public final class AccelerationGuard: @unchecked Sendable` mit `init(control: any AccelerationControlling, defaults: UserDefaults)`, `func disable() -> Bool` (liest Originalwert, speichert ihn unter `mouse.accel.original`, schreibt `-1`; bei bereits gespeichertem Original wird das nicht überschrieben), `func restore()` (schreibt gespeichertes Original zurück und löscht den Eintrag), `func recoverIfNeeded()` (ruft `restore()` auf, wenn ein gespeichertes Original existiert).

- [ ] **Step 1: Write the failing test** — mit `FakeControl` (merkt Wert): `disableStoresOriginalAndWritesOff`, `restoreWritesOriginalBack`, `secondDisableKeepsFirstOriginal` (kein Überschreiben mit −1), `recoverIfNeededRestoresAfterCrash` (neuer Guard auf denselben Defaults), `restoreWithoutDisableDoesNothing`, `unreadableOriginalDoesNotWriteAndReturnsFalse`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** Protokoll, Guard und die echte IOHID-Implementierung (nur Aufruf, keine Tests dafür).
- [ ] **Step 4: Run to verify pass** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(mouse): pointer acceleration guard with crash recovery`

### Task 6: Event-Tap und Modul-Verdrahtung

**Files:**
- Create: `Packages/Mouse/Sources/Mouse/EventTapController.swift`, `Packages/Mouse/Sources/Mouse/EventProcessor.swift`, `Packages/Mouse/Tests/MouseTests/EventProcessorTests.swift`
- Modify: `MouseModule.swift`

**Interfaces:**
- Consumes: Funktionen aus Tasks 2–5.
- Produces: `public struct EventProcessor: Sendable` mit `init(settings: MouseSettings)`, `mutating func process(_ event: MouseEventInput, bundleID: String?) -> EventDecision`; `public enum MouseEventInput: Sendable { case scroll(ScrollSample), buttonDown(button: Int, timestampNanoseconds: UInt64) }`; `public enum EventDecision: Equatable, Sendable { case passThrough, replaceScroll(ScrollSample), swallow, perform(ButtonAction), injectSmooth(ScrollSample) }`. Reihenfolge für Scroll: Ausnahmen → nur Rad-Ereignisse → linear → Richtung → bei `smoothScroll` `injectSmooth` (Originalereignis wird verschluckt), sonst `replaceScroll`.
- Produces: `final class EventTapController` mit `start(handler:) throws` (Tap auf eigenem Thread, `CGEventTapCreate` `.defaultTap`, wirft `MouseError.tapUnavailable` wenn `nil`), `stop()`; bei `tapDisabledByTimeout`/`tapDisabledByUserInput` wird `CGEvent.tapEnable(tap:enable:true)` aufgerufen; Display-Link für `SmoothScroller` über `NSScreen.main?.displayLink(target:selector:)` solange nicht idle.
- `MouseModule.start()`: Berechtigung über Registry, `AccelerationGuard.recoverIfNeeded()`, bei `disableAcceleration` `disable()`, Tap starten; `stop()`: Tap stoppen, `restore()`.

- [ ] **Step 1: Write the failing test** — `EventProcessorTests`: `trackpadScrollPassesThrough`, `wheelIsLinearized`, `wheelIsReversed`, `reverseThenLinearKeepsSizeAndFlipsSign`, `smoothScrollSwallowsAndInjects`, `disabledAppPassesEverythingThrough`, `nilBundlePassesWithGlobalSettings`, `mappedButtonPerformsAction`, `unmappedButtonPassesThrough`, `fastSecondClickIsSwallowed`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** `EventProcessor` (rein, nutzt die Funktionen aus Tasks 2–4), dann `EventTapController` und `MouseModule`-Start/Stop. Der Controller übersetzt `CGEvent` ↔ `MouseEventInput`/`EventDecision` (Felder `scrollWheelEventPointDeltaAxis1/2`, `scrollWheelEventIsContinuous`, `scrollWheelEventScrollPhase`, `scrollWheelEventMomentumPhase`, `mouseEventButtonNumber`) und führt `perform` über synthetische Tasten-Ereignisse aus.
- [ ] **Step 4: Run to verify pass** — `swift test` und `xcodebuild build` mit `-warnings-as-errors`. Expected: PASS, null Warnungen.
- [ ] **Step 5: Commit** — `feat(mouse): event processor, event tap and module lifecycle`

### Task 7: Einstellungs-UI und Texte

**Files:**
- Create: `Packages/Mouse/Sources/Mouse/MouseSettingsView.swift`, `Packages/Mouse/Sources/Mouse/Resources/Localizable.xcstrings`, `Packages/Mouse/Tests/MouseTests/MouseLocalizationTests.swift`
- Modify: `MouseModule.makeSettingsView()`

**Interfaces:**
- Consumes: `MouseModule.settings`.
- Produces: `MouseSettingsView` mit Abschnitten Scrollen (linear, Zeilen pro Schritt, weich + Glätte, Richtung), Zeiger (Beschleunigung aus), Tasten (Zusatztaste → Aktion), Click-Filter (Millisekunden), Ausnahmen (App wählen über `NSOpenPanel` auf `/Applications`, Bundle-ID aus `Bundle(url:)`, pro App deaktivieren/überschreiben). Alle Texte in EN + DE.

- [ ] **Step 1: Write the failing test** — `MouseLocalizationTests` (wie `MonitorLocalizationTests`: Katalog-JSON über `#filePath` lesen): jeder Schlüssel hat `de`-Übersetzung.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL (Katalog fehlt).
- [ ] **Step 3: Implement** Katalog und View.
- [ ] **Step 4: Run to verify pass** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(mouse): settings view and EN/DE strings`

### Task 8: Verdrahtung, Doku, Version 0.3.0

**Files:**
- Modify: `App/SettingsView.swift` (Eintrag für das Modul, falls nicht automatisch), `docs/PERMISSIONS.md`, `README.md`, `project.yml` (`MARKETING_VERSION "0.3.0"`, `CURRENT_PROJECT_VERSION 300`), `.github/workflows/ci.yml` (Mouse-Paket in die Test-Schleife)
- Test: `SonaryTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test** — `mouseToggleEnablesAndPersists` (wie `monitorToggleEnablesAndPersists`, mit `FakeChecker`-Berechtigung granted; `startUpdater: false`).
- [ ] **Step 2: Run to verify fail** — `xcodebuild test`. Expected: FAIL.
- [ ] **Step 3: Implement** Verdrahtung, PERMISSIONS-Eintrag (Bedienungshilfen: wofür, was passiert bei Entzug), README-Funktionsliste, Version, CI-Schleife.
- [ ] **Step 4: Run to verify pass** — CI komplett grün. Expected: PASS.
- [ ] **Step 5: Commit** — `feat: wire mouse module, docs, version 0.3.0`

### Manuelle Prüfung auf dem Mac (nicht in CI)

Linear-Scrolling fühlt sich gleichmäßig an; Smooth Scrolling ruckelfrei; Trackpad unverändert; Beschleunigung aus und beim Beenden wieder an; Seitentasten lösen Zurück/Vor aus; Ausnahme-App verhält sich wie ohne Modul; Bedienungshilfen entziehen → Modul meldet Fehler, Mauszeiger bleibt normal.
