# ScobySense Privacy Policy

_Last updated: 2026-10-29_

ScobySense is a community-built Android companion for The Fermenstation
(KOMBU) kombucha brewer. It is published by the ScobySense project at
<https://github.com/Predator04/ScobySense>.

## Who sees what

**ScobySense never operates its own backend.** The app runs entirely on
your device and talks to third-party services on your behalf:

- **Amazon Cognito (`cognito-idp.us-east-1.amazonaws.com`)** —
  your email and password are sent only to Amazon Cognito to sign you
  into the same Kombu AWS account the official app uses. ScobySense
  never sees, logs, or forwards those credentials anywhere else.
- **Kombu AWS AppSync GraphQL endpoint
  (`*.appsync-api.us-east-1.amazonaws.com`)** — the Cognito ID token
  from the step above is sent with each request to read device status,
  brew-cycle history, and alert rules associated with your account. All
  authorization is enforced by AWS, not ScobySense.
- **GitHub Releases API (`api.github.com/repos/Predator04/ScobySense`)**
  — ScobySense asks GitHub for the latest release to check for app
  updates. GitHub may log the request IP under its own terms of
  service. No account identifier is sent.

That's it. No analytics SDK, no crash reporter, no ads network, no
telemetry endpoint operated by this project.

## What stays on your device

- **Cognito tokens** (`id`, `access`, `refresh`) are stored in Android
  Keystore via `flutter_secure_storage` and only ever used to re-auth
  against Cognito.
- **Temperature history** samples are kept in local Shared Preferences
  for charting; the app caps the ring buffer at 2000 points per device.
- **Preferences** (°C/°F toggle, notification toggle, scheduling draft)
  are also local-only Shared Preferences values.
- **Downloaded APKs** for in-app updates land in the app's external
  files directory and are overwritten by the next download.

Clearing the app's data (Android Settings → Apps → ScobySense → Storage
→ Clear data) removes all of the above.

## Notifications

ScobySense can show local Android notifications when a configured alert
rule's temperature threshold is crossed or when a brew timer completes.
These are generated locally while the app is running. The server-side
push system used by the official Kombu app (Firebase Cloud Messaging) is
**not** part of ScobySense.

## Data we do not collect

- We do not sell any data because we do not collect any.
- We do not run an analytics or crash service.
- We do not share your Cognito credentials, AWS data, or device
  telemetry with any third party. Those stay between your device, AWS,
  and GitHub (for update checks only).

## Device control

ScobySense can send commands to your device (brew timers, sound toggle,
turning a fermenter off) when you tap a control in the app. Commands are
only ever sent on an explicit action from you — the app never sends
anything automatically.

## Contact

Open an issue at <https://github.com/Predator04/ScobySense/issues>.
