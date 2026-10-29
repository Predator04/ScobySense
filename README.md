# ScobySense

A community-built Android companion for the **Fermenstation (SCOBYSENSE)** kombucha brewer — live brew read-out, full device control, and an in-app recipe library, in a clean glass UI.

> **Unofficial.** ScobySense is not made by, endorsed by, or affiliated with ScobySense / The Fermenstation. It talks to the same AWS backend the official app uses, using your own account. It can break if that backend changes.

## Features

- **Sign in with your SCOBYSENSE account** — credentials go only to Amazon Cognito; login is saved securely and auto-refreshes.
- **Live F1 / F2 read-out** — real-time temperatures and remaining brew time for both fermenters, plus brew-cycle history and batch tracking.
- **Full device control** — set a brew timer in **days, hours, or minutes**, toggle the sound, and turn a fermenter off, all from the app.
- **Recipes** — built-in kombucha and soda recipes plus your own. Add, edit, and remove recipes, and manage the category tabs (add/rename). Dual-unit measurements (metric / US).
- **12-hour / 24-hour time** toggle.
- **Update banner** — checks for new releases and shows an "update available" prompt without auto-installing anything.
- **First-launch legal disclaimer** and persistent terms.
- Local device rename, WiFi status label, pull-to-refresh, and local alert notifications.

## Install

Download the latest APK from **[Releases](https://github.com/Predator04/ScobySense/releases)** and sideload it:

1. Download `ScobySense-vX.Y.Z.apk`.
2. Open it on your phone and allow "install unknown apps" when prompted.

You need a Fermenstation device already paired in the **official SCOBYSENSE app** before ScobySense can see it.

## Privacy

ScobySense runs entirely on your device and has no backend of its own. See **[PRIVACY.md](PRIVACY.md)** for exactly what goes where.

## Build from source

```bash
flutter pub get
flutter build apk --release
```

Release signing requires a `keystore.properties` file (not committed) next to `android/`:

```
storeFile=../scobysense-release.keystore
storePassword=...
keyPassword=...
keyAlias=scobysense
```

## Legal

ScobySense is an independent, third-party client. "SCOBYSENSE" and "Fermenstation" are trademarks of their respective owners and are used here only to identify the compatible hardware. This project provides no warranty; use at your own risk, and comply with the device manufacturer's own terms.

If you are the rights holder and would like this project removed, open an issue at <https://github.com/Predator04/ScobySense/issues> and it will be taken down.
