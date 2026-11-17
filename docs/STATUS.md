# Status

Updated in every pull request, so the owner and the backend session can see where the app is.

**Last updated:** 17 Nov 2026

## Current stage

**Stage 0:** all 14 PRs done ([STAGE-0-PLAN.md](STAGE-0-PLAN.md) §11), plus the #345 error codes; its end-of-stage device check is still to do.

**Stage 1 (students):** plan approved 17 Nov ([STAGE-1-PLAN.md](STAGE-1-PLAN.md)). Done: PRs 1–13 and 15 (files, Today, My attendance and check-in, read-only cache, leave, timetable, homework, classes, class discussions, calendar, tests and results, taking a test, results, resources). Next: chat (PR 14), then the integration tests.

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

- PR 12: the account screen (`/account`, from the menu): the profile as on the web (name, role, email, phone, verified, member since; read-only, as the API has no way to change the name); change password (the web's checks and wording; a wrong current password says so; the other devices are signed out by the server and the list reloads); signed-in devices (platform, name, app version, last used in Dhaka time, "This device"; sign out one or all the others, each after a confirmation). The language switch now also saves the choice to the account (`PATCH /user/me/locale`), as the web does, and says so if that fails. Checked on beta as a test student in English and Bangla (no password changed, no device signed out).

- The #345 error codes: sign-up, the SMS code, forgot password and sign-in now say what went wrong in Bangla or English (phone or email already has an account, under that field; the code could not be sent, the hourly limit; no such account; already verified; wrong, expired or locked code; not verified yet (sign up again with the same number for a new code); account disabled). The server's English message is never shown. Checked on beta: forgot password with a made-up email says "No account was found…".

- PR 13: "More features" (`/features`, from the menu, as on the web). It shows:
  - the plan's name;
  - every feature from `GET /subscriptions/feature-catalog`, by group, with the web's name and one-line description in Bangla or English, marked Included or Locked from `GET /me/entitlements`. `tool/import_web_messages.dart` now also writes `feature_names.g.dart`; a feature the messages do not know shows the API's label;
  - "Request this feature" with an optional note (`POST /me/feature-requests`); the feature is then marked "Requested".

  Only the owner or an admin (a solo teacher in their own workspace) sees it; everyone else is told to ask them. There is no upgrade button (CLAUDE.md "Payments"). The locked-feature sheet now offers owners and admins "See all features and request one", and scrolls on short screens. Checked on beta as the Demo School owner in English and Bangla. No request was sent, because sending one emails the platform admins.

- PR 14: the app icon and splash from the owner's logo (`assets/brand/`), made by `flutter_launcher_icons` and `flutter_native_splash` (dev only, approved in the plan; settings in `pubspec.yaml`):
  - **Android:** an adaptive icon (the logo on white, small enough for round masks) and a splash on the canvas colour, including Android 12's.
  - **iOS:** the icon on white (iOS icons cannot be transparent) and the launch screen.

  `test/brand_test.dart` keeps the splash colour equal to the canvas token. Checked on the emulator: the icon is whole under the round mask, and the splash shows the logo on the canvas colour. iOS was not seen on a device.

- Stage 1 PR 1: files. Uploads in three steps (presign, PUT to the signed link with no session headers, complete) with progress, cancel and retry; take a photo, choose photos (resized to 2000 px, JPEG 80) or choose files, limited to the types the server takes for each purpose; 20 MB limit; over the storage quota shows the locked-feature sheet, and 90% full is said; open a file through `/files/:id/content`. Packages `image_picker` and `file_picker` (approved with the plan); iOS camera and photo-library reasons. Used by leave, homework and chat. Found that the server refuses `HOMEWORK` uploads (tes-taker#349).

- Stage 1 PR 2: Today, now the home screen (`/` and `/today`): today's classes, events, exams and homework from `GET /calendar/me` (all the person's workspaces, each item named when there are several), "Check-in is open: …" with a button to My attendance (where the web checks in), homework due this week (not handed in), and the next 5 events and exams; each item opens its details, or says it belongs to another workspace; owners, admins and assistants also get "Your school". Checked on beta as an owner in Bangla, and against a test student's real feed.

- Stage 1 PR 3: My attendance and check-in (`/my-attendance`). Today's classes (read again every minute, as the web) with their window and own record, "You teach", paper-register and cancelled notes, and Check in: online classes send nothing; in-person classes ask for location once (Android fine location, iOS "when in use"; reasons in both languages) and send one fresh, accurate fix (`geolocator`). Every server refusal says what happened in the web's words (too far with the distance and radius, not accurate enough, not open yet, closed, already checked in…); location off or refused says how to fix it, with "Open settings". Then the month: attendance rate, present, late, absent, leave, and a Saturday-first calendar with a mark and letter per class and the legend. Checked on beta as an owner (no classes today; the November grid with Fridays off).

- Stage 1 PR 4: the read-only cache (owner's decision 5). Today's week (Today) and today's classes (My attendance) are kept on the phone per user and workspace; with no connection they are shown under "No internet connection. This was saved on your phone at …", never written to, and nobody can check in from them; a copy from another day is not shown; everything is removed when the person signs out. The timetable joins it in PR 6.

- Stage 1 PR 5: Leave for students (`/leave`): "Apply for leave" (first day, last day or one day, a reason, an optional photo or PDF through the files PR), with the web's checks and every refusal in its words (too long, too old, too far ahead, no school days, overlapping with the other request's dates…); "My leave" with dates, school days, status, the answer and who gave it, the attachment, and Withdraw (asked first) while pending. Approving others' leave is Stage 2. Checked on beta in Bangla as an owner (the form and the Bangla date picker; nothing applied).

- Stage 1 PR 6: the timetable (`/routine`, read only): the week of the person's section, Saturday first, today marked, each period with its time, subject, teacher (the one named, else the subject's teachers) and room; a section picker when there are several; kept in the read-only cache. Changing the routine stays on the web. Checked on beta in Bangla as an owner (section picker, Wednesday marked).

- Stage 1 PR 7: homework for students (`/homework`, `/homework/:id`): the list with "Handed in (version n)" or when it is due (overdue, within a day, later); the page with subject, type, marks, the instructions (the web's HTML shown as plain paragraphs and lists, see TODO), the teacher's files; hand in a typed answer and/or photos and files (purpose HOMEWORK, fixed by the backend in tes-taker#349), with the web's checks and refusals and "Handed in again" counts; every version with its late tag and files; the score (marks, %, grade, late penalty, feedback, ratings). Paper homework says to hand it to the teacher. Teachers see "use the website" until Stage 2. Checked against a test student's real homework on beta (read only) and a HOMEWORK upload link (deleted).

- Stage 1 PR 8: classes for students (`/classes`, `/classes/details/:id` as on the web): the classes in this workspace with when the student joined; a class's page with its classmates. Its tests join with the tests PR and its discussions with the next PR. Teachers see "use the website" until Stage 2. Notification links to a class open in the app.

- Stage 1 PR 9: class discussions (the class page's Discussions tab), per subject as on the web: the class discussion (posts with their type, files and replies; a type filter; a new post with up to 5 photos or files, purpose DISCUSSION; replies; delete your own post) and private messages with the subject's teachers (start a conversation, read and send with files). Both are read again every 20 seconds, as the web. Editing a post stays on the web (TODO).

- Stage 1 PR 10: the calendar (`/calendar`, month view): the person's classes, events, exams, homework and holidays from every workspace, filtered by kind and workspace; a Saturday-first month with a dot per kind, today outlined; the chosen day's list (the same tiles and details as Today); "My reminders" read only (changed on the web, owner's decision). Week and day views, adding events and the calendar link stay on the web.

- Stage 1 PR 11: tests and results (`/tests`, `/tests/:id/results`, and a class's Tests tab): the tests set to the student with their type, status, subject, schedule and hand-in progress, filtered by status; a finished test's result with score, percentage, grade, right/wrong/not answered, and the answer sheet (each question, the student's answer, the right one, the marks; passages shown once above their questions). Start says taking tests in the app comes next. Teachers see "use the website" until Stage 2.

- Stage 1 PR 12: taking a test (`/tests/:id/take`, full screen): eligibility (the web's messages for not started, ended, already submitted, disqualified, not assigned, full); Strict and IELTS tests say to use a computer; the rules (what is watched, the warning and the limit); then the questions (single and multiple choice, matching, written answers, passages once above their questions) with a timer, answers kept on the phone and sent a few seconds after each change, submit after a confirmation (open questions counted), automatic when time is up, retried while offline. Live connection (`socket_io_client` 3.1.6, pinned): joins the test, a heartbeat every 15 s, the teacher's warning, "ended by your teacher". Light proctoring: leaving the app is flagged (live and on the attempt), paste is off, screenshots are blocked on Android; auto-disqualification counts flags as the web. Checked end to end on beta with the approved test exam ("Mobile app check (Stage 1)", made by demo.teacher1 for Class 6, Off proctoring): demo.student1 was eligible, started, autosaved, submitted (3/5, the essay waits for marking) using the app's exact requests; the result is not published yet (tes-taker#351 asks for an error code).

- Stage 1 PR 13: results for students (Academic): paper-exam marks (`/marks`: marks, %, grade, absent), my performance (`/performance`, `GET /scores/students/:me`: overall score, grade, GPA, position, the four parts, homework on time, subjects with score and grade, exams), report cards (`/report-cards` and a card: school, term, overall, subjects, position when shown, attendance days, remarks). Charts and printing stay on the web. Teachers see "use the website" until Stage 2. demo.student1 has none on beta yet (checked: empty lists and a performance answer in the expected shape).

- Stage 1 PR 15 (built before chat): resources for students (`/resources`): files and links shared with their classes, with search (after typing stops), subject and type filters, the "New" tag and the view-only note; Open records the opening (`POST /resources/:id/open`, as the web) and then opens the file or link. "Not in your plan" (403) says so.

## In progress

- Stage 1 ([STAGE-1-PLAN.md](STAGE-1-PLAN.md)), PR 14 of 15: chat. Stage 0 still needs its end-of-stage check (360 px phone, tablet, iOS).

## Owner's decisions since the plan

- 17 Nov: the Stage 1 plan approved as written: `image_picker`, `file_picker`, `geolocator` and `socket_io_client`; location, camera and photo permissions; Light proctoring in the app (leaving the app reported like a tab switch, screenshots blocked on Android, no copy and paste in answers); reminders read-only; one test exam on beta for demo.student1; class discussions in Stage 1.
- 17 Nov: the logo the owner sent (green ring with a yellow "i") replaces `logo.png` for the app icon and splash (PR 14). The black background was removed; PR 14 added it as `assets/brand/logo.png`.
- 17 Nov: `cupertino_ui` approved as a direct dependency (Bangla texts for iOS-style menus; it already came with `material_ui`).

## `mobile-api` issues

| Issue | What | Priority | Blocked? |
| --- | --- | --- | --- |
| [tes-taker#345](https://github.com/Sadiquzzaman/tes-taker/issues/345) | Error codes for sign-up, OTP and password reset (and login: wrong credentials vs not verified) | Done | No: on beta and used by the app; closed by the backend on 17 Nov |
| [tes-taker#349](https://github.com/Sadiquzzaman/tes-taker/issues/349) | `POST /files/presign` refuses purpose HOMEWORK (the web's homework uploads fail too) | Done | No: fixed on beta 18 Nov (#350); the app uploads homework files |
| [tes-taker#351](https://github.com/Sadiquzzaman/tes-taker/issues/351) | A code for "Result has not been published yet" (403 with no code) | Low | No: the app reads any 403 there as "not published yet" |

## Waiting on the backend (planned, no issue needed)

| Item | Effect on the app until then |
| --- | --- |
| PM-02 Google sign-in for apps | No "Continue with Google" in the app |
| PM-04 Push notifications | The bell polls; no push |

Live classes are postponed by the owner and left out of every stage.

## Decisions needed from the owner

None right now.
