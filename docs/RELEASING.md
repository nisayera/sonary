# Releases and updates

## Versions

Every feature release raises the minor version (0.21 → 0.22), fixes raise the patch version (0.22.0 → 0.22.1). 1.0 comes when the [feature checklist](FEATURES.md) is done.

Tags are named `v0.22.0`. The build number follows from the version, `major*10000 + minor*100 + patch` (0.22.0 → 2200), so it always grows. `scripts/release_tools.py` computes it and refuses minor or patch numbers above 99.

## Making a release

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (for example `0.23.0` and `2300`).
2. Merge the branch into `main`.
3. The `Release` workflow sees that this version has no release yet. It builds the app (macOS 26, arm64), signs it with the stable certificate, creates `Sonary-<version>.zip` and `.dmg`, signs the ZIP for Sparkle (EdDSA) and publishes both together with `appcast.xml` as a GitHub release tagged `v<version>`.

A merge without a new version does not release anything. Pushing a `v*` tag by hand, or publishing a release in the web UI, still works.

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

The app is not notarized, so the first launch needs a right-click on Sonary and **Open**. Updates through Sparkle install without that step. With an Apple Developer ID certificate (99 $/year) signing and notarization move into the workflow, and the `disable-library-validation` entitlement can go.
