# Handover — Instructor mobile app

Written on 16 Nov 2026 by the Claude Code session that builds the backend and web app, for the Claude Code session that builds this app. Read this, then `CLAUDE.md`, then [SCREENS.md](SCREENS.md).

## 1. The product

**Instructor** runs schools, coaching centres, IELTS centres and solo teachers in Bangladesh: attendance, homework, tests with proctoring, results and report cards, calendar and timetable, chat, resources, plagiarism checks and an IELTS workspace. The web app is live on beta at https://beta.instructor.academy. The mobile app brings **everything a person does on the web** to Android and iOS from **one Flutter codebase**, in stages (§4).

- **Workspace types:** Academic (schools, coaching centres, solo tutors) and IELTS (IELTS centres and solo IELTS trainers). They are separate products with separate menus; IELTS users never see academic pages.
- **Every account is an organisation**: a solo teacher has an organisation of one. A user can belong to several workspaces and switches between them.
- **Roles:** Owner, Admin, Assistant, Teacher (a class teacher is a teacher with one section to look after), Student; Branch Manager is coming (P12). Guardians have no login; they get SMS. Platform admins work on the web only.
- **Languages:** Bangla and English everywhere, chosen by the user.

## 2. Where everything is

| What | Where |
| --- | --- |
| Backend and web (NestJS, Next.js) | [Sadiquzzaman/tes-taker](https://github.com/Sadiquzzaman/tes-taker), public. Read it; never change it from here |
| **API guide (the contract)** | [`docs/mobile/api.md`](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/mobile/api.md) and [`api-changelog.md`](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/mobile/api-changelog.md) |
| Feature stories (IDs like ATT-06, IEL-13) | [`docs/spec.md`](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/spec.md) |
| Architecture, tables, decisions | [`docs/design.md`](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/design.md) |
| Design system (colours, type, spacing, components) | [`docs/ui/design-system.md`](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/ui/design-system.md) and `frontend/app/tokens.css` |
| Wording in Bangla and English | `frontend/messages/en.json`, `frontend/messages/bn.json` |
| Which role sees which page | `frontend/utils/sidebarList.tsx` |
| Each web page | `frontend/app/<route>/page.tsx` and `frontend/component/<Feature>/` |
| Beta API | `https://api-beta.instructor.academy/api/v1` |
| Test accounts on beta | `backend/src/user/test-users.seed.ts`: Demo School, Sunrise School (every role, 60 students, 3 months of data) and Bright Path IELTS. Ask the owner for the password; never write it in this repo |

## 3. Technical choices

- **Flutter (stable channel) and Dart**, one codebase for Android and iOS. Minimum versions to agree with the owner in the first PR (suggested: Android 7.0 / API 24, iOS 13).
- **App id:** `academy.instructor.app` (reverse of instructor.academy) for both stores. Changing it after the first store release is not possible, so confirm it with the owner in the first PR.
- **Packages:** none are approved yet. Propose them in the first plan with versions and licences. Typical choices: an HTTP client with interceptors (for the token refresh in API guide §3), secure storage for tokens, routing, a state-management library, `intl`/ARB for Bangla and English, Socket.IO client, image picking and compression, geolocation (check-in), camera (selfie and proctoring), local notifications, and Firebase Messaging once push exists on the server.
- **Theme:** build one theme (light and dark) from the web's design tokens; Bangla text needs a font that renders Bangla well (the web's font choice is in the design system).
- **Structure:** one folder per feature (auth, workspace, today, attendance, homework, tests, results, calendar, chat, resources, notifications, ielts, …), each with its API calls, models, state and screens; shared widgets and the API client in a core folder.
- **CI (GitHub Actions; free for public repos):** `flutter analyze` and `flutter test` on every PR; an Android APK built on every merge to `develop` and attached to a GitHub pre-release; an iOS build check on a macOS runner without signing (`flutter build ios --no-codesign`).

## 4. What to build, in order

The owner wants everything the web has. The order below gives a usable app early; [SCREENS.md](SCREENS.md) lists every screen with its web route.

| Stage | Who | What |
| --- | --- | --- |
| 0 | Everyone | Project setup, theme, Bangla/English, API client with refresh, sign up / log in / OTP / forgot password, workspace switcher, menu by role and plan, notifications inbox, profile |
| 1 | Students | Today, check-in, my attendance, leave, homework (see and hand in), tests (take them), results, calendar and timetable, chat, resources |
| 2 | Teachers | Dashboard, classes, attendance and the paper register, homework (create, mark), tests (list, results, grading), marks and behaviour, calendar, chat, resources |
| 3 | Owners, admins, branch managers | Organisation overview, people (teachers, assistants, students, invitations), classes, sessions, subjects and assignments, approvals, attendance reports, settings, plan and usage (view only) |
| 4 | Authoring on tablets | Test creation, the academic setup wizard, IELTS test builder and band tables |
| 5 | IELTS | After the backend's P12 (courses, live classes, recordings) is on the web; until then IELTS screens stay out of the app |

**Platform admin** (`/admin/*`) stays web-only.

## 5. Signing in and workspaces

All of it is in the API guide §3–4. In short: log in → list workspaces → select one (new tokens) → send `Authorization` and, in an organisation, `X-Organization-Id`. On a 401, refresh once, then sign out. Store tokens in secure storage.

**Until the server's mobile work ships** (API guide §9):

- Logging in on the phone ends the web's refresh token and the other way round.
- Google sign-in is not available in the app.
- There is no push.

Build around these; the server will add device sign-in, Google ID-token sign-in, push and a version check in that order.

## 6. Things that need the owner's decision (ask before building them)

1. **Proctored tests on phones.** The web watches the camera, face and tab switches in the browser. Suggestion: tests without proctoring and with light proctoring in the app; strictly proctored tests ask for a computer until a native version is designed.
2. **Payments.** Apple and Google have rules on selling subscriptions inside apps. Suggestion: no buying and no "buy elsewhere" links in the app; billing shows the plan only.
3. **App name, icon and splash screen.**
4. **Minimum Android and iOS versions** and the app id (§3).
5. **Offline use.** Suggestion: read-only cache of today's timetable and the last lists seen; no offline writes except a queued check-in, if the owner wants it.

## 7. Testing and getting it onto phones

- **Store accounts:** none yet. The owner launches the web first, then the app. The code must still be ready for both stores.
- **Android:** every merge to `develop` produces an APK on a GitHub pre-release. Testers download it and install it (allow "install unknown apps"). Use a debug or test signing key kept in GitHub Actions secrets, never in the repo.
- **iOS:** Jubaer (co-founder) has a Mac. Install with Xcode and a free Apple ID (the app expires after 7 days and must be reinstalled), or on the iOS Simulator. TestFlight needs the paid Apple developer account later.
- **Point builds at beta** (`api-beta.instructor.academy`) with a build flavour or `--dart-define`; production comes later.
- **Check every screen** on a small Android phone, a large phone, a tablet, and iOS, in Bangla and English, light and dark.

## 8. Working with the backend session

The two Claude Code sessions do not talk directly. GitHub is the channel:

1. **Need something from the API, or found a server bug?** Open an issue in [tes-taker](https://github.com/Sadiquzzaman/tes-taker/issues) with the label `mobile-api`. Say which screen needs it, what the app sends and expects back (fields and types), and the error codes to handle. Then tell the owner, who passes it to the backend session.
2. **The backend answers** with a PR into `develop`, a comment on the issue, and an entry in `api-changelog.md` once it is on beta.
3. **Read `api-changelog.md`** at the start of each task.
4. **Nothing is renamed or removed** in the API without a new version agreed with the owner, so the app does not break under you.

## 9. Release flow (same as the web)

- Feature branches → PR into `develop` → CI green → test the APK and on iOS.
- When a stage is ready: a "Release: …" PR from `develop` into `main`, merged only when the owner says so, then a PR from `main` back into `develop`.
- Store submission happens after the web goes live, with the owner.
