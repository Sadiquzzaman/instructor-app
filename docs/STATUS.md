# Status

Updated in every pull request, so the owner and the backend session can see where the app is.

**Last updated:** 17 Nov 2026

## Current stage

**Stage 0:** PRs 1–5 of 14 ([STAGE-0-PLAN.md](STAGE-0-PLAN.md) §11). Next: PR 6, the version check at start-up.

## Done

- Development computer set up (Windows 11): Flutter 3.50.0 stable, Dart 3.14.0, Java 17 (Temurin), Android SDK 36 and an Android 16 Pixel 8 emulator; `flutter doctor` green for Flutter and Android; a test app ran on the emulator.
- Read the handover, rules, screen map and the backend's docs; summary and the owner's decisions in [PROJECT-NOTES.md](PROJECT-NOTES.md).
- Read the API changelog up to 17 Nov 2026: PM-01 (devices), PM-03 (version check), PM-05 (openapi.json), IELTS courses and branch managers (P12-01 to P12-05).
- Looked at beta through the API, read-only, as a student, teacher, owner, IELTS student, IELTS owner and solo teacher.
- Wrote the Stage 0 plan.
- Created the Android test signing key (outside the repo); its four secrets are in the repository's Actions secrets.
- PR 1: the Flutter project (`academy.instructor.app`, "Instructor", Android 7.0 / API 24, iOS 15.0), lints, a placeholder home, tests, and CI (`ci.yml`: format, analyze, test; `ios-build.yml`: iOS build without signing; Dependabot for actions).
- PR 2: every merge into `develop` publishes a test APK as a GitHub pre-release ([Releases](https://github.com/Sadiquzzaman/instructor-app/releases)), signed with the test key so it installs over earlier test builds. First one: `v0.1.0-dev.3`.
- PR 3: the theme from the web's design tokens (`tool/tokens.json` → `lib/core/theme/tokens.g.dart`), `AppColors` by role, the type scale with Bangla line height 1.7, the bundled fonts (Instrument Sans, Hind Siliguri; OFL), and shared widgets (button, text field, card, status pill, loading/empty/error states). Tests check the tokens against the web's file, WCAG AA contrast and that no screen hard-codes a colour or font size.
- CI fix: the Android build keeps the NDK (~700 MB) and Gradle's downloads in the Actions cache and stops after 15 minutes (a slow NDK download hung a build for 24 minutes on 17 Nov).
- PR 4: Bangla and English. The web's wording is imported into the ARB files by `tool/import_web_messages.dart` (namespaces so far: `common`, `language`, `ui`, `validation`); a language switch saved on the phone (default: the phone's language if Bangla, else English, until sign-in brings the account's); the theme follows the language; level labels (`[[Classes]]` → the workspace's words), rich-text tags, and `OrgTime` (Asia/Dhaka, Bangla digits).

- PR 5: the API client (`lib/core/api/`, `lib/core/auth/`): the answer envelope and `ApiException` (codes, features, limits, every shape of `message`); the session in secure storage (Keychain "this device only" / Keystore); bearer and `X-Organization-Id` headers; one refresh at a time with the rotated pair stored before any retry; sign-out when a refresh is refused, but not when the connection drops; `device` (make and model, never the owner's phone name) on refresh; a debug log that never shows headers, bodies or query values.

## In progress

- PR 6: the version check at start-up (`GET /app/version`; required update blocks, optional update suggests).

## Owner's decisions since the plan

- 17 Nov: the logo the owner sent (green ring with a yellow "i") replaces `logo.png` for the app icon and splash (PR 14). The black background was removed; the transparent version is kept outside the repo until PR 14 adds it.
- 17 Nov: `cupertino_ui` approved as a direct dependency (Bangla texts for iOS-style menus; it already came with `material_ui`).

## Open `mobile-api` issues

None. Not blocked.

## Waiting on the backend (planned, no issue needed)

| Item | Effect on the app until then |
| --- | --- |
| PM-02 Google sign-in for apps | No "Continue with Google" in the app |
| PM-04 Push notifications | The bell polls; no push |

Live classes are postponed by the owner and left out of every stage.

## Decisions needed from the owner

None right now.
