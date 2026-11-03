# Releases und Updates

## Versionen
Jeder Meilenstein bekommt eine Version: M0 = 0.1, M1 = 0.2, ... M8 = 0.9. Wenn der Hauptplan fertig ist, erscheint 1.0.
Tags heißen `v0.2.0`, `v0.3.0`, ... Die Build-Nummer ergibt sich aus dem Tag (`major*10000 + minor*100 + patch`) und wächst immer.

## Release erstellen
1. `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` in `project.yml` setzen (z. B. `0.4.0` und `400`).
2. Den Branch nach `main` mergen.
3. Der Workflow `Release` sieht, dass es für diese Version noch kein Release gibt, baut die App (macOS 26, arm64), erzeugt `Sonary-<Version>.zip` und `.dmg`, signiert das ZIP mit Sparkle (EdDSA) und veröffentlicht alles inklusive `appcast.xml` als GitHub-Release mit Tag `v<Version>`.

Ein Merge ohne neue Version löst kein Release aus. Ein Tag `v*` von Hand oder ein im Web veröffentlichtes Release funktionieren weiterhin.

## Auto-Update
Die App fragt `https://github.com/nisayera/sonary/releases/latest/download/appcast.xml` ab (Sparkle 2, automatische Prüfung an). Ein Klick auf "Nach Updates suchen" installiert die neue Version.

## Einmalig: Signaturschlüssel
- Der öffentliche Schlüssel steht in `project.yml` (`SUPublicEDKey`).
- Der private Schlüssel gehört als GitHub-Secret `SPARKLE_ED_PRIVATE_KEY` ins Repo (Settings, Secrets and variables, Actions). Er darf nie committet werden.
- Ohne das Secret bricht der Release-Workflow ab.

## Hinweis zu Gatekeeper
Solange es kein Apple-Developer-Konto gibt, ist die App nur ad-hoc signiert und nicht notarisiert. Beim ersten Start: Rechtsklick auf Sonary, Öffnen. Updates über Sparkle laufen danach ohne diese Hürde. Mit einem Developer-ID-Zertifikat (99 $/Jahr) kommen Signierung und Notarisierung in den Workflow, und der Entitlement `disable-library-validation` entfällt.
