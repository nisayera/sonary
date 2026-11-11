# Releases and updates

## Versions

Every feature release raises the minor version (0.21 → 0.22), fixes raise the patch version (0.22.0 → 0.22.1). 1.0 comes when the [feature checklist](FEATURES.md) is done.

Tags are named `v0.22.0`. The build number follows from the version, `major*10000 + minor*100 + patch` (0.22.0 → 2200), so it always grows. `scripts/release_tools.py` computes it and refuses minor or patch numbers above 99.

## Making a release

1. Set the version: `python3 scripts/release_tools.py set-version 0.23.0`. It writes `MARKETING_VERSION` and the matching `CURRENT_PROJECT_VERSION` (`2300`) into `project.yml`; never edit the build number by hand.
2. Add an entry for the version at the top of [CHANGELOG.md](../CHANGELOG.md) (see below).
3. Open a pull request. CI runs the tests and `release_tools.py check-project`, which fails when the build number does not follow from the version or the changelog entry is missing.
4. Merge it into `main`. CI runs again on `main`; only when it passes does the `Release` workflow start. It sees that this version has no release yet, builds the app (macOS 26, arm64), signs it with the stable certificate, creates `Sonary-<version>.zip` and `.dmg`, signs the ZIP for Sparkle (EdDSA) and publishes both together with `appcast.xml` as a GitHub release tagged `v<version>`.

A merge without a new version does not release anything, and a merge whose CI fails or is cancelled releases nothing either. Pushing a `v*` tag by hand, or starting the workflow by hand, still works, but only for a commit whose CI run passed.

## Release notes

Every release says what changed, taken from [CHANGELOG.md](../CHANGELOG.md). The file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), the way Vorssaint's releases do:

```markdown
## [0.23.0] - 2026-12-01

### Summary
One or two sentences on what this release is about.

### Added
- A new thing, said from the point of view of someone using Sonary. Where to find it: Settings → Clipboard.

### Changed
- Something that works differently now.

### Fixed
- A bug that is gone.
```

Use the sections that apply (`Added`, `Changed`, `Fixed`, `Removed`, `Security`). Write for the people who use Sonary, not about the code. The entry needs a date and at least one `- ` line, or the release stops.

`release_tools.py notes` turns the entry into the GitHub release body (the entry, then how to install) and into HTML for the notes Sparkle shows before an update. `python3 scripts/release_tools.py notes --tag v0.23.0 --out /tmp/notes.md` shows the result locally.

## In-app updates

The app reads `https://github.com/nisayera/sonary/releases/latest/download/appcast.xml` (Sparkle 2, automatic checks on). "Check for Updates…" installs a new version in one click.

## Secrets

The release workflow stops if any of these repository secrets (Settings → Secrets and variables → Actions) is missing:

| Secret | What it is |
| --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | Base64 Ed25519 seed that signs the update archive. The matching public key is `SUPublicEDKey` in `project.yml`. Never commit it. |
| `SIGNING_CERT_P12` | The self-signed code-signing certificate with its private key, as a base64 `.p12` |
| `SIGNING_CERT_PASSWORD` | The password of that `.p12` |
| `SIGNING_CERT_SHA1` | The certificate's SHA-1 fingerprint, used to pick it for `codesign` |

`release_tools.py public-key` prints the public key for the seed in `SPARKLE_ED_PRIVATE_KEY`, to check that the two still match.

## Signing and Gatekeeper

Builds are signed with a fixed self-signed certificate. A fixed identity lets macOS keep the permissions you granted (Accessibility, Screen Recording, …) across updates; ad-hoc signatures change with every build, so macOS would treat each update as a new app.

`scripts/sign_app.sh` signs from the inside out, as Apple and Sparkle recommend instead of `codesign --deep`: Sparkle's `Installer.xpc`, `Downloader.xpc`, `Updater.app` and `Autoupdate`, then `Sparkle.framework`, then the app, each with its own identifier and entitlements and the hardened runtime. The DMG is signed with the same certificate. CI runs the script with an ad-hoc identity on every pull request, so a broken script is noticed before a release depends on it.

The app keeps the `com.apple.security.cs.disable-library-validation` entitlement for now. A self-signed certificate has no Team ID, and library validation under the hardened runtime only loads frameworks signed by Apple or by the same team, so without the entitlement macOS would refuse to load the embedded Sparkle.framework and Sonary would not start.

The app is not notarized, so the first launch is blocked by Gatekeeper. Since macOS 15 the old right-click → **Open** no longer gets past it: open Sonary once, click **Done**, then **System Settings → Privacy & Security → Open Anyway** (Datenschutz & Sicherheit → Trotzdem öffnen) and confirm. Updates through Sparkle install without that step. With an Apple Developer ID certificate (99 $/year) signing and notarization move into the workflow, the first launch opens normally, and the `disable-library-validation` entitlement can go.

## Reproducible builds

Sparkle is pinned to one exact version in `project.yml` (`exactVersion`), and the Python packages the release tools use are pinned in `scripts/requirements.txt`. Raise them on purpose, in a pull request of their own, so CI tests the new version before a release ships it.
