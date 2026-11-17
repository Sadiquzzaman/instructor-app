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

The integration tests (sign-in, and a student's main flows: Today and check-in, handing in homework, taking a test) run the real app on a device or emulator against an in-process fake API (no network, no password). The student flows also run on the host with the rest of `flutter test` (`test/flows`), so CI covers them:

```sh
flutter test integration_test -d <device-id>
```

## Text in Bangla and English

Every user-facing string comes from `lib/l10n/app_en.arb` and `app_bn.arb`, which are **generated** (never edit them):

- `l10n/web/{en,bn}.json`: the web's wording (tes-taker `frontend/messages`), for the namespaces listed in `tool/import_web_messages.dart`;
- `l10n/app/{en,bn}.json`: strings only the app has, under `app`.

```sh
dart run tool/import_web_messages.dart ../tes-taker/frontend/messages   # refresh the web's wording, rebuild the ARB files
dart run tool/import_web_messages.dart                                 # rebuild after editing l10n/app/
```

`flutter pub get` then generates `AppLocalizations` (`context.l10n.uiErrorRetry`). `test/l10n/messages_test.dart` checks the ARB files are up to date, both languages have the same keys and placeholders, and every Bangla string is in Bangla. Use `ref.levels(context, …)` for messages with `[[Classes]]`-style tokens, `RichMessage` for `<tag>` parts, and `OrgTime` for dates, times and numbers.

## The menu

The side menu is generated from the web (tes-taker `frontend/utils/sidebarList.tsx` for the items and who sees them, `sidebarGroups.ts` for the order):

```sh
dart run tool/import_menu.dart ../tes-taker/frontend/utils
```

This copies both files into `tool/` and regenerates `lib/features/shell/menu/menu_items.g.dart`; it fails if a label has no message (import the web's `nav` wording first). `lib/features/shell/menu/menu_filter.dart` applies the web's rules; `test/features/shell/menu_test.dart` checks both.

## Design tokens

Colours, type sizes, radii, shadows and motion come from the web (tes-taker `frontend/design/tokens.json`). When the web changes them:

```sh
dart run tool/import_tokens.dart ../tes-taker/frontend/design/tokens.json
```

This copies the file to `tool/tokens.json` and regenerates `lib/core/theme/tokens.g.dart`; `test/core/theme/tokens_test.dart` fails until both agree. Screens never write a colour or font size: they use `AppColors.of(context)`, the theme's text styles, `AppSpacing`, `AppRadius`, `AppShadows` and `AppMotion`.

## Test builds

Every merge into `develop` publishes an Android APK as a pre-release under [Releases](https://github.com/Sadiquzzaman/instructor-app/releases). It talks to beta and is signed with a test key, so each new build installs over the last one (allow "install unknown apps" the first time). The key is only in the repository's Actions secrets; locally, `flutter build apk --release` signs with the debug key unless `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` are set.

iOS: build from a Mac with Xcode (HANDOVER §7).

## Facts

| | |
| --- | --- |
| App id | `academy.instructor.app` (Android and iOS) |
| Minimum versions | Android 7.0 (API 24), iOS 15.0 |
| Branches | work on `feature/`, `task/`, `fix/` branches from `develop`; pull requests into `develop` |
