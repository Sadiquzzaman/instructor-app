# Status

Updated in every pull request, so the owner and the backend session can see where the app is.

**Last updated:** 17 Nov 2026

## Current stage

**Stage 0:** PRs 1–11 of 14 ([STAGE-0-PLAN.md](STAGE-0-PLAN.md) §11). Next: PR 12, the account screen (name, language, password, signed-in devices).

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
- PR 6: the version check (PM-03). At start-up and when the app comes back after an hour, `GET /app/version` with this build's platform and version: REQUIRED replaces the app with "Please update Instructor" (button opens `update_url`, https only), OPTIONAL shows a banner with "Update" and "Later", any failure lets the app start. The backend sets `APP_MIN_VERSION`, `APP_LATEST_VERSION` and `APP_UPDATE_URL_ANDROID/IOS` (nothing set on beta yet, so every build is fine).

- PR 7: log in and out. The login screen (the web's wording and checks; email or 01XXXXXXXXX and a password; the app's own sentence for a wrong password, as the API sends no code), `POST /auth/login` with this device, the account's language applied after sign-in; go_router sends signed-out people to login and signed-in people home; the session is restored before the first frame; "Sign out" ends this device's session (`POST /auth/logout`) and works offline; a refused refresh returns to login. Tested on beta from the emulator as a test student (sign in, restart, sign out). Android lint's release check is skipped for a lint crash on url_launcher (docs/TODO.md).

- PR 8: sign-up and forgot password. Choose student, teacher (Academic or IELTS) or organisation (school or IELTS centre); the web's forms, checks (strong password, terms) and wording; the 6-digit SMS code with a 60 s resend (which repeats the sign-up, as the API sends a new code for an unverified phone); back to login with the web's message (verified, teacher pending approval, or the organisation number); forgot password in three steps (code by SMS or email, masked target, new password). Nothing is sent to beta from tests; the screens were checked on the emulator without submitting.

- PR 9: workspaces. After sign-in with several workspaces and none chosen (`context_type: individual`) the app shows "Your workspaces" (the web's wording; "Pending approval" marked); the home switcher opens the same list; `POST /auth/select-context` gives the new tokens on the same device; everything that belongs to a workspace (level labels so far) reloads or drops by itself when the workspace changes or the person signs out; the organisation's language applies when the person has none. Tested on beta with a Sunrise School teacher who has two schools.

- PR 10: the app shell and menu. The menu is generated from the web's `sidebarList.tsx` and `sidebarGroups.ts` (95 items, same rules and order: section by session, role, member role, personal workspace, Academic/IELTS, plan features from `GET /me/entitlements`; groups, "Setup" heading, a group of one as a link; the web-only Admin section left out). Phones: a drawer; screens 840 px and wider: the menu stays open. Every menu page not built yet says "Please use the website for it for now" (IELTS pages: "… for IELTS"). Locked features show the web's "Not in your plan" wording by role, with no upgrade button; NOT_FOR_BRANCH_MANAGERS and NOT_IN_IELTS have short messages. Checked on beta as a student, an owner and an IELTS owner.

- PR 11: notifications. The bell in the top bar with the unread count (`GET /me/notifications/unread-count` at once, every minute while the app is open and when it comes back, as the web; Bangla digits; read aloud as "Notifications, 22 unread"); the inbox (newest first, 20 at a time, more on scroll, pull to refresh, unread marked, times in Dhaka time, "Mark all as read"); opening an item marks it read and opens its page when the app has it. Push waits for PM-04. Checked on beta with a test student's 22 real notifications (none opened).

## In progress

- PR 12: the account screen: name, language (saved to the account), change password, signed-in devices (sign out one or the others).

## Owner's decisions since the plan

- 17 Nov: the logo the owner sent (green ring with a yellow "i") replaces `logo.png` for the app icon and splash (PR 14). The black background was removed; the transparent version is kept outside the repo until PR 14 adds it.
- 17 Nov: `cupertino_ui` approved as a direct dependency (Bangla texts for iOS-style menus; it already came with `material_ui`).

## Open `mobile-api` issues

| Issue | What | Priority | Blocked? |
| --- | --- | --- | --- |
| [tes-taker#345](https://github.com/Sadiquzzaman/tes-taker/issues/345) | Error codes for sign-up, OTP and password reset (and login: wrong credentials vs not verified) | Soon | No: the app shows a general message meanwhile |

## Waiting on the backend (planned, no issue needed)

| Item | Effect on the app until then |
| --- | --- |
| PM-02 Google sign-in for apps | No "Continue with Google" in the app |
| PM-04 Push notifications | The bell polls; no push |

Live classes are postponed by the owner and left out of every stage.

## Decisions needed from the owner

None right now.
