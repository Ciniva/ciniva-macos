# Ciniva for macOS

Native macOS player for a [Ciniva](https://github.com/Ciniva/ciniva) server. It direct-plays every format through mpv
or AVFoundation (Dolby Vision, HDR10, Atmos passthrough), with resume, Continue watching / Up next, credits detection,
episode navigation, trickplay previews, plugin pages, Download & watch (play torrents while they download) and a
library rescan button.

## Install

Download `Ciniva-<version>.zip` from the [latest release](https://github.com/Ciniva/ciniva-macos/releases/latest),
unzip it and move `Ciniva.app` to Applications. It needs macOS 15 or later on Apple silicon.

The app is signed with Ciniva's own certificate, not an Apple Developer ID, so macOS blocks the first launch. Open it
once, then go to **System Settings → Privacy & Security** and click **Open Anyway** (or run
`xattr -dr com.apple.quarantine /Applications/Ciniva.app`).

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

GitHub Actions tests and builds every push. Pushing a commit to `main` that changes `VERSION` publishes release
`v<VERSION>` with the zip and its signature. Repository secrets:

- `UPDATE_SIGNING_KEY`: base64 raw Ed25519 private key; its public half is `Updater.publicKey`.
- `MACOS_SIGNING_P12`, `MACOS_SIGNING_PASSWORD`: base64 PKCS#12 with the "Ciniva Code Signing" identity. A stable
  identity keeps keychain access across updates; without it builds are signed ad hoc.
