# APU Auto Signer

A lightweight Flutter mobile app for batch attendance signing at APU (Asia Pacific University).

## Features

- **Multi-account management**: Add multiple student accounts via WebView OAuth login
- **One-tap batch signing**: Enter 3-digit OTP and sign attendance for all selected students simultaneously
- **Secure local storage**: Student tokens stored encrypted in local SQLite database
- **Token auto-refresh**: Detects expired tokens and prompts re-authorization

## Tech Stack

- Flutter 3.24.x
- `webview_flutter` - OAuth login via Microsoft
- `sqflite` + `sqflite_common_ffi` - Local encrypted database
- `http` - Native HTTP client for GraphQL calls
- `flutter_secure_storage` - Secure credential storage

## Getting Started

```bash
flutter pub get
flutter run
```

## Architecture

```
lib/
├── main.dart                    # App entry point
├── models/
│   └── student.dart             # Student data model
├── services/
│   ├── auth_service.dart        # OAuth + token exchange
│   ├── attendance_service.dart  # GraphQL attendance calls
│   └── database_service.dart    # SQLite local storage
├── screens/
│   ├── home_screen.dart         # Main attendance screen
│   ├── add_student_screen.dart  # WebView OAuth login
│   └── student_list_screen.dart # Manage saved students
└── widgets/
    ├── student_tile.dart        # Student list item
    └── result_dialog.dart       # Sign-in result display
```

## Auth Flow

1. User adds a student → WebView opens Microsoft OAuth
2. After login, redirect to `auth.apu.edu.my/auth_token` → exchange code at `auth.apu.edu.my/token`
3. Save token + user_id to local SQLite
4. On sign-in: use stored token to call `attendix.apu.edu.my/graphql` with OTP

## Release Build

Requires **JDK 17**. The project is pinned to Flutter 3.24.x + Gradle 8.3, which are incompatible with newer JDKs (e.g. 25 will SIGKILL the Gradle build). Point `JAVA_HOME` at a JDK 17 install.

```bash
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

For a distributable (non-debug) build, configure `signingConfigs.release` in `android/app/build.gradle` and provide `android/key.properties` (storePassword / keyPassword / keyAlias / storeFile). `key.properties` and `*.jks` are git-ignored — never commit them.

## Sign-in Timing & Request Hardening

Batch sign-in deliberately avoids firing every account at the exact same instant:

- `AttendanceService.batchSignIn` staggers each account **500–2500 ms** apart (random `dart:math` jitter) instead of `Future.wait` all-at-once. This avoids bursting all accounts from one IP at one timestamp and de-correlates request timing.
- `AttendanceService._buildHeaders` sends a **real HuaweiBrowser / WebView User-Agent** (captured from the official APSpace app on the same device) plus a matching `Accept-Language`, instead of a hardcoded desktop UA.

Why this is enough (and why we stopped here):

- The Attendix GraphQL endpoint authenticates by **Bearer token + OTP + API key only**. It does not validate the User-Agent, so a realistic UA is purely cosmetic "looks normal" hygiene, not a security control.
- All accounts necessarily originate from the **single device IP** (a phone). Spreading IPs would require a proxy pool, which is over-engineering for a handful of accounts and tends to look *more* suspicious (datacenter / residential proxy ASN).
- `X-Amz-User-Agent: aws-amplify/2.0.7` is kept as-is (AWS telemetry header, not validated by the endpoint).

## Repository Hygiene (before pushing to GitHub)

Never commit local secrets or debug artifacts — they are already git-ignored:

- `token_b64.txt`, `token2_b64.txt`, `refresh_secret.txt` — captured tokens / MS refresh secret
- `decode_any.py`, `decode_token.py`, `decode_token.ps1`, `extract.py`, `ms_refresh_test.py` — personal debug scripts
- `android/key.properties`, `*.jks`, `*.keystore` — release signing material

Delete the token dump files from disk before the first push if they are still present.
