# Ciniva for macOS

Native macOS player for a [Ciniva](https://github.com/Ciniva/ciniva) server. It direct-plays every format through mpv
or AVFoundation (Dolby Vision, HDR10, Atmos passthrough), with resume, Continue watching / Up next, credits detection,
episode navigation, trickplay previews, plugin pages, Download & watch (play torrents while they download) and a
library rescan button.

## Install

Download `Ciniva-<version>.zip` from the [latest release](https://github.com/Ciniva/ciniva-macos/releases/latest),
unzip it and move `Ciniva.app` to Applications. It needs macOS 15 or later on Apple silicon.

Releases are signed with a Developer ID and notarized by Apple, so they open without a Gatekeeper warning. (Releases up
to 1.1.1 used a self-signed certificate: allow those once in **System Settings → Privacy & Security → Open Anyway**.)

## Updates

Ciniva checks GitHub for a new release at launch and every six hours (Settings → Updates, or **Ciniva → Check for
Updates…**). Updates are installed only if their Ed25519 signature matches the key built into the app; then the app
replaces itself and relaunches.

## Building

```sh
brew install mpv dylibbundler
swift test
./build.sh                       # build/Ciniva.app, linked against Homebrew's libmpv
BUNDLE_LIBS=1 ./build.sh         # self-contained app with libmpv and its dependencies in Contents/Frameworks
```

## Releases

GitHub Actions tests and builds pull requests and manual runs on any branch (the zip is a workflow artifact). Pushing
tag `v<VERSION>` publishes that release with the zip and its signature. Repository secrets:

- `UPDATE_SIGNING_KEY`: base64 raw Ed25519 private key; its public half is `Updater.publicKey`.
- `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD`: base64 PKCS#12 with a "Developer ID Application" identity. Builds are
  then signed with the hardened runtime and notarized with `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` (an app-specific
  password) and `NOTARY_TEAM_ID`, so Gatekeeper opens them without a warning. Nothing is submitted to the App Store.
- `MACOS_SIGNING_P12`, `MACOS_SIGNING_PASSWORD`: fallback self-signed "Ciniva Code Signing" identity, used when no
  Developer ID is set. Without either, builds are signed ad hoc.
