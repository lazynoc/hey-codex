# Releasing Hey Codex

## Local test release

Hey Codex can produce a drag-to-Applications DMG for private testing:

```bash
./scripts/build-release.sh 0.1.0-test.1
```

This creates:

- `dist/Hey-Codex-0.1.0-test.1.dmg`
- `dist/Hey-Codex-0.1.0-test.1.dmg.sha256`

The disk image contains `Hey Codex.app` and an Applications shortcut. The release test verifies the checksum, mounts the image read-only, validates the bundle, and verifies its code signature:

```bash
./scripts/test-release.sh
```

## Version stamping

`scripts/build-release.sh VERSION` stamps the full version (including any `-test.N` suffix) into the app's `CFBundleShortVersionString` so Check for Updates compares real versions. When installing locally with `scripts/install.sh`, pass the same version through the environment:

```bash
HEY_CODEX_VERSION=0.1.0-test.12 ./scripts/install.sh
```

An Apple Development or ad-hoc signed DMG is suitable only for testing. Gatekeeper may require **Control-click > Open** on another Mac. It must not be described as a trusted public download.

## One-time public-release setup

Install a `Developer ID Application` certificate from the Apple Developer account. Confirm that it is available:

```bash
security find-identity -v -p codesigning
```

Store notarization credentials in the login keychain. Never put an Apple ID, app-specific password, API key, or certificate in this repository:

```bash
xcrun notarytool store-credentials "hey-codex-notary" \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

## Build and notarize

The public build enables Hardened Runtime, signs the app and DMG with Developer ID, submits the DMG to Apple's notary service, staples the ticket, checks Gatekeeper, and writes the checksum after stapling:

```bash
./scripts/build-release.sh 1.0.0 \
  --notarize \
  --notary-profile "hey-codex-notary"
```

Run the independent public-artifact gate:

```bash
./scripts/test-public-release.sh 1.0.0
```

It must finish with:

```text
HEY_CODEX_PUBLIC_RELEASE_PASS
```

Publish both generated files:

- `dist/Hey-Codex-1.0.0.dmg`
- `dist/Hey-Codex-1.0.0.dmg.sha256`

Finally, install the downloaded DMG on a clean Mac and complete onboarding, wake, dictation, stop, focus restoration, and relaunch testing before announcing the release.
