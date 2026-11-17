# Instructor app

The Android and iOS app of [Instructor](https://beta.instructor.academy), built with Flutter from one codebase. The backend and web app live in [Sadiquzzaman/tes-taker](https://github.com/Sadiquzzaman/tes-taker).

- Start with [docs/HANDOVER.md](docs/HANDOVER.md), then [CLAUDE.md](CLAUDE.md) and [docs/SCREENS.md](docs/SCREENS.md).
- The API contract: [tes-taker/docs/mobile/api.md](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/mobile/api.md).
- Where the app stands: [docs/STATUS.md](docs/STATUS.md). The current plan: [docs/STAGE-0-PLAN.md](docs/STAGE-0-PLAN.md).

This repository is public. Never commit keys, signing files, Firebase config files, tokens or passwords.

## Run it

You need Flutter 3.50.0 (stable) and, for Android, Java 17 and the Android SDK (platform 36). `flutter doctor` should show Flutter and the Android toolchain green; iOS needs a Mac with Xcode.

```sh
flutter pub get
flutter run                     # talks to beta (https://api-beta.instructor.academy/api/v1)
```

Another server: `flutter run --dart-define=API_BASE_URL=https://example.com/api/v1`.

## Before every pull request

```sh
dart format lib test
flutter analyze
flutter test
```

CI runs the same on every pull request, plus an iOS build without signing.

## Test builds

Every merge into `develop` publishes an Android APK as a pre-release under [Releases](https://github.com/Sadiquzzaman/instructor-app/releases). It talks to beta and is signed with a test key, so each new build installs over the last one (allow "install unknown apps" the first time). The key is only in the repository's Actions secrets; locally, `flutter build apk --release` signs with the debug key unless `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` are set.

iOS: build from a Mac with Xcode (HANDOVER §7).

## Facts

| | |
| --- | --- |
| App id | `academy.instructor.app` (Android and iOS) |
| Minimum versions | Android 7.0 (API 24), iOS 15.0 |
| Branches | work on `feature/`, `task/`, `fix/` branches from `develop`; pull requests into `develop` |
