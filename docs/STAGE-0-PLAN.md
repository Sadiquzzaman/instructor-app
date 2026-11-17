# Stage 0 plan

**Approved by the owner on 17 Nov 2026** (packages, actions, iOS 15 minimum, CI against a fake API only). Still open: who creates the Android test signing key (§12.3), asked again in PR 2.

Stage 0 (HANDOVER §4): project setup, theme, Bangla/English, API client with refresh, sign up / log in / OTP / forgot password, workspace switcher, menu by role and plan, notifications inbox, profile. Written 17 Nov 2026 against tes-taker `develop` `8fb2e7f` and beta.

## 1. Setup

| Tool | Version |
| --- | --- |
| Flutter | 3.50.0 stable (Dart 3.14.0), pinned in CI |
| Java | Temurin 17.0.21 |
| Android | SDK platform 36, build-tools 36.1.0; emulator Pixel 8, Android 16 (API 36), x86_64 with Google Play |
| Computer | Windows 11, Ryzen 7 3700X, 16 GB; everything on `E:\dev` |

`flutter doctor -v`: Flutter, Android toolchain (licences accepted), Chrome and devices green. Visual Studio red (Windows desktop apps only, not needed). Xcode not applicable on Windows: iOS is checked in CI on a macOS runner and on Jubaer's Mac.

## 2. What I learned from beta (read-only, 17 Nov)

Signed in through the API as a Demo School student, teacher and owner, a Bright Path IELTS student and owner, and a solo teacher; each signed out afterwards.

- A user with one workspace is **already in it after login** (`session_mode: organization`, `workspace_type` set); the answer also carries `contexts` and `requires_context_selection`. The picker only shows when that flag says so or the user opens the switcher.
- `contexts` items carry no `workspace_type`, so the switcher shows the name and role only (the type arrives with the new tokens).
- `GET /attendance/me/today` already returns everything the Today screen needs (`can_check_in`, `needs_location`, `state`, windows, `time_zone`).
- Errors come back exactly as api.md says, for example 403 `NOT_IN_IELTS` (IELTS leave) and 403 `FEATURE_NOT_IN_PLAN` with `feature: "attendance"` (solo teacher on Free).
- `GET /app/version` answers `{platform, minimum, latest, update_url, update}`; nothing set on beta, so `update: NONE`.
- **openapi.json** names all 453 operations and describes 180 request bodies, but only 4 answers. So: request bodies are checked against it, answer models are written by hand (no code generator).
- **Time zone:** no endpoint returns the organisation's time zone except attendance; the web hard-codes `Asia/Dhaka`. The app does the same in one place (`OrgTime`), Dhaka is UTC+6 with no daylight saving, so no time-zone package is needed yet.

## 3. Packages (each needs your approval)

| Package | Version | Licence | Publisher | Why |
| --- | --- | --- | --- | --- |
| `dio` | ^5.11.1 | MIT | flutter.cn | HTTP client with interceptors: adds the headers, refreshes once on 401, maps errors to codes |
| `flutter_riverpod` | ^3.5.0 | MIT | dash-overflow.net | State management: testable (providers can be overridden in tests), no `BuildContext` needed, easy to clear everything on workspace switch. Used without code generation |
| `go_router` | ^18.1.4 | BSD-3 | flutter.dev | Routing with redirects (signed out → login, update required → update screen, no workspace → picker) and deep links later (join links) |
| `flutter_secure_storage` | ^11.2.0 | BSD-3 | steenbakker.dev | Tokens in Keychain / Keystore (CLAUDE.md, api.md §3) |
| `shared_preferences` | ^2.5.6 | BSD-3 | flutter.dev | Non-secret settings: language, last workspace, read-only cache |
| `intl` | ^0.20.3 | BSD-3 | dart.dev | Bangla/English messages (`gen-l10n`), Bangla digits, dates |
| `package_info_plus` | ^10.2.2 | BSD-3 | fluttercommunity.dev | The app's version for `device.app_version` and the version check |
| `device_info_plus` | ^13.3.0 | BSD-3 | fluttercommunity.dev | The phone's name for `device.name` (shown in the signed-in devices list) |
| `url_launcher` | ^6.3.3 | BSD-3 | flutter.dev | "Update the app" opens `update_url`; later, links in resources |
| `material_ui` | ^1.11.1 | BSD-3 | flutter.dev | Flutter's Material widgets. Flutter 3.50 deprecated `package:flutter/material.dart` in favour of this package, and `flutter create` adds it. Approved 17 Nov 2026 with PR 1 |
| `cupertino_ui` | ^1.1.7 | BSD-3 | flutter.dev | Flutter's iOS-style widgets and their translations (moved out of the SDK in 3.47). Already a dependency of `material_ui`; listed directly for its Bangla `GlobalCupertinoLocalizations`. Approved 17 Nov 2026 with PR 4 |
| **dev only** | | | | |
| `flutter_lints` | ^6.0.0 | BSD-3 | flutter.dev | Standard lint rules for `flutter analyze` |
| `mocktail` | ^1.0.5 | MIT | felangel.dev | Fakes in unit and widget tests |
| `flutter_launcher_icons` | ^0.14.4 | MIT | fluttercommunity.dev | App icon for both platforms from `logo.png` |
| `flutter_native_splash` | ^2.4.8 | MIT | jonhanson.net | Native splash screen from `logo.png` |

Also from the Flutter SDK (no approval needed, listed for completeness): `flutter_localizations`, `flutter_test`, `integration_test`.

**Fonts** (bundled as assets, not a package): Instrument Sans and Hind Siliguri, both SIL Open Font Licence, from their official repositories (same fonts as the web).

**Not in Stage 0, asked for later with the stage that needs them:** image picking and compression (profile photo, homework), geolocation (check-in, stage 1), Socket.IO (chat), Firebase Messaging (when PM-04 push is on beta).

**GitHub Actions** (pinned to a commit, Dependabot keeps them current):

| Action | Version | Licence | Why |
| --- | --- | --- | --- |
| `actions/checkout` | v7.0.1 | MIT | Get the code |
| `actions/setup-java` | v6.3.0 | MIT | Java 17 for the Android build |
| `actions/cache` | v6.1.0 | MIT | Cache pub and Gradle downloads |
| `subosito/flutter-action` | v2.23.0 | MIT | Install Flutter 3.50.0 on the runner (third party, widely used) |

Pre-releases are made with the `gh` CLI that runners already have, so no release action is needed.

## 4. Folder structure

```text
lib/
  main.dart                  start-up: version check, session restore, then the app
  app.dart                   MaterialApp.router, theme, languages
  core/
    api/                     ApiClient (dio), envelope, ApiException(code, status, feature, limit), auth interceptor
    auth/                    TokenStore (secure storage), Session (user, workspace, tokens), refresh
    config/                  API base URL and environment from --dart-define
    l10n/                    generated localisations, rich-text and level-label helpers
    routing/                 routes and redirects
    theme/                   tokens (generated), ThemeData, text styles for Latin and Bangla
    time/                    OrgTime: UTC → organisation time, Bangla digits
    menu/                    menu items and the filter by role, workspace type and plan
    widgets/                 shared widgets: buttons, fields, cards, empty, error and loading states, locked-feature sheet
  features/
    version/                 start-up check and the update screen
    auth/                    login, sign up, OTP, forgot password
    workspace/               picker and switcher
    shell/                   home shell: bottom bar on phones, side rail on tablets
    notifications/           inbox and unread badge
    account/                 profile, language, password, signed-in devices
    locked_features/         "More features"
    not_yet/                 "Use the web for this for now" placeholder
  l10n/                      app_en.arb, app_bn.arb
assets/fonts/, assets/images/
test/                        mirrors lib/
integration_test/            sign-in and workspace flows against a fake API
tool/                        import_web_messages.dart, import_tokens.dart (plain Dart, no packages)
```

Each feature folder has `data/` (API calls and models), `state/` (providers) and `screens/`.

## 5. State and routing

- **Riverpod** providers per feature. Everything that belongs to a workspace hangs off one `workspaceScope` provider; switching workspace or signing out invalidates it, so no data from the old workspace survives (multi-tenancy rule).
- **go_router** with one redirect function, in this order: update required → update screen; no session → login; `requires_context_selection` → workspace picker; otherwise the requested page. Routes follow the web's names (`/today`, `/account`, …) so deep links can map later.
- **Menu:** a table that mirrors `sidebarList.tsx` (`role`, `memberRoles`, `personalWorkspaceOnly`, `workspaces`, `feature`) and one pure function that filters it; unit-tested per role, workspace type and plan. Items not built yet open the "Use the web for this for now" screen, so the menu is complete from day one.
- **Branch managers** see only what answers: workspace, profile, notifications, and (IELTS) courses. Any 403 `NOT_FOR_BRANCH_MANAGERS` shows "Not available for branch managers yet".
- **IELTS before stage 5:** shared features as they are built; IELTS-only items show "Use the web for IELTS for now" (owner's decision 6).

## 6. Tokens: storage and refresh

- `TokenStore` keeps the access token, refresh token and the session (user, organisation id, member role, workspace type) in secure storage. Nothing is logged; the dio log interceptor (debug builds only) hides `Authorization`, tokens, passwords, OTPs and phone numbers.
- Every request: `Authorization: Bearer`, and `X-Organization-Id` only in an organisation session, taken from the session the API gave us.
- Login and refresh send `device: { platform: ANDROID | IOS, name, app_version }`.
- **Refresh:** on a 401, one refresh runs at a time; every request waiting on it gets the result. The new pair is written to secure storage **before** any request is retried (the old refresh token dies 60 s later). If refresh fails: clear the tokens and go to login. The refresh call itself never triggers another refresh.
- **Sign out:** `POST /auth/logout`, then delete tokens and every cache, whatever the answer.
- **Workspace switch:** `POST /auth/select-context` → store the new pair → invalidate `workspaceScope` → reload the menu and entitlements.
- **Version check:** `GET /app/version?platform=…&current=…` at start-up and when the app comes back after an hour. `REQUIRED` → full-screen "Update the app" (button opens `update_url`); `OPTIONAL` → a dismissible banner; network failure → carry on.
- Tests: unit tests for the interceptor (headers per session type, single refresh with several 401s at once, rotation stored before retry, failed refresh signs out, no refresh loop) and the store.

## 7. Bangla and English

- **gen-l10n** with `lib/l10n/app_en.arb` and `app_bn.arb`.
- **Wording from the web:** `tool/import_web_messages.dart` copies the namespaces each stage needs from tes-taker `frontend/messages/en.json` and `bn.json` into the ARB files with flat keys (`auth.logIn` → `authLogIn`; keys that differ only by capitals stay distinct). ICU `plural` and `select` work as they are. App-only strings live under an `app` prefix. Re-running the script picks up the web's wording changes.
- **Rich tags** (`<highlight>…</highlight>`) stay in the string; a small `RichMessage` widget turns them into styled spans.
- **Level labels** (`[[Classes]]`, `[[section]]`, …) are replaced at runtime from `GET /workspace/level-labels` (Class / Section by default; Course / Batch in IELTS).
- **Language choice:** the account's `locale`, else the organisation's `default_locale`, else the phone's; changing it in Account saves it with `PATCH /user/me/locale`.
- **Numbers and dates:** Bangla digits and 24-hour time, in `Asia/Dhaka` through `OrgTime` (§2).
- **Tests:** both ARB files have the same keys and placeholders, and every Bangla string contains Bangla; widget tests render in both languages.

## 8. Theme

- `tool/import_tokens.dart` reads tes-taker `frontend/design/tokens.json` and writes `lib/core/theme/tokens.g.dart`. A test fails if it is out of date, as the web does with `pnpm tokens:check`.
- `AppColors` is a `ThemeExtension` named by role (`primary`, `ink`, `inkMuted`, `canvas`, `surface`, `border`, `success`/`warning`/`danger`/`info` and their soft variants), so dark colours can be added later without touching screens (owner's decision 4). Light only for now.
- Type scale 12/14/16/20/24/32, line height 1.5 for English and 1.7 for Bangla, Instrument Sans with Hind Siliguri; radius 6/10/16; two elevations; 150/250 ms motion, off when the phone asks for reduced motion.
- A test scans `lib/features/` and fails on `Color(0x…`, `Colors.` or a raw `fontSize:` (CLAUDE.md: no hard-coded colours or sizes).
- Layout: works from 360 px; tablets (≥ 600 px wide) get the side rail and wider content; tap targets ≥ 44 px.

## 9. App id, versions, environments

- App id `academy.instructor.app`, name "Instructor", icon and splash from tes-taker `frontend/public/logo.png` (owner's decisions 1 and 3).
- **Minimum versions: Android 7.0 (API 24) and iOS 15.0.** iOS 15, not 13: Flutter 3.50 moves every project below iOS 15 up to 15 when it builds, so 15 is the lowest it supports. You asked to be told when Flutter needs higher; this is that case.
- Target and compile SDK 36 (Flutter's defaults).
- `--dart-define=API_BASE_URL=https://api-beta.instructor.academy/api/v1` for beta builds (the default); production is added when it exists.
- Version `0.1.0+<build>`, the build number from the CI run.

## 10. CI (GitHub Actions)

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` | every PR into `develop` or `main` | `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`; checks the ARB files and tokens are in sync |
| `ios-build.yml` | every PR | macOS runner: `flutter build ios --no-codesign` |
| `android-prerelease.yml` | every merge into `develop` | build a release APK signed with a **test key** from Actions secrets, attach it to a GitHub pre-release `v0.1.0-dev.<run>` with the PR titles as notes |

The test signing key keeps the same signature on every build, so testers can install new APKs over old ones. It never enters the repo (see §12).

## 11. Pull requests, in order

Each is small, starts from `develop`, updates `docs/STATUS.md`, and passes analyze and test.

1. **chore: Flutter project** — app id, name, minimum versions, lints, folder skeleton, a placeholder home, README run steps; `ci.yml` and `ios-build.yml`.
2. **ci: Android pre-release APK** — `android-prerelease.yml` with the test signing key (needs the secrets, §12).
3. **feat: theme from the web's tokens** — token import, `AppColors`, fonts, shared widgets (buttons, fields, cards, empty, error and loading states).
4. **feat: Bangla and English** — message import, gen-l10n, `RichMessage`, level labels, `OrgTime`, language switch.
5. **feat: API client** — envelope, `ApiException` codes, interceptor, secure `TokenStore`, single refresh with rotation, device info; unit tests.
6. **feat: version check** — start-up check, update screen and banner.
7. **feat: log in and log out** — login (phone or email), session restore, logout; integration test against a fake API.
8. **feat: sign up and forgot password** — student, teacher and organisation sign-up (Academic or IELTS), OTP, the "waiting for approval" states, forgot password.
9. **feat: workspaces** — picker, switcher in the shell, clearing caches.
10. **feat: app shell and menu** — menu by role, workspace type and plan; locked-feature sheet by role; "Use the web for this for now"; branch managers.
11. **feat: notifications** — inbox (paged), mark one or all read, unread badge polled every minute while the app is open and when it comes back.
12. **feat: account** — name, language, change password, signed-in devices (sign out one, sign out the others); profile photo waits for the image packages (stage 1).
13. **feat: more features** — the locked-features list with "Request this feature" (`/me/feature-requests`).
14. **chore: icon and splash** — from `logo.png`.

Testing for each: unit and widget tests in CI; on the Android emulator (360 px phone and a tablet) in both languages; iOS through the CI build, and on Jubaer's Mac at the end of the stage.

## 12. Decisions needed from you

1. **Approve the packages** in §3 (and the four actions).
2. **iOS 15 minimum** instead of 13 (§9).
3. **Test signing key for Android pre-releases:** I can create it on this computer (`keytool`, in the git-ignored folder outside the repo) and you add it to the repository's Actions secrets yourself (`gh secret set`, four values). Or you create it. Either way it never enters the repo. Which do you prefer?
4. **Integration tests against beta:** CI runs sign-in tests against a fake API only. A real sign-in on beta would need the test password as an Actions secret; I suggest not, and running the beta check by hand on the emulator before each stage ends.
5. **This plan as a PR into `develop`** (`docs/STAGE-0-PLAN.md`), so it is on record?

## 13. Backend: nothing blocking

No `mobile-api` issue is needed for Stage 0. Two **Later** requests I would open only with your OK:

- the organisation's `timezone` in the sign-in, refresh and select-context answers (today the app, like the web, assumes `Asia/Dhaka`);
- answer schemas in `openapi.json` (only 4 of 453 have one), so models could be generated instead of hand-written.
