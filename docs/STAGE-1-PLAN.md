# Stage 1 plan: students

**Approved by the owner on 17 Nov 2026, as written** (§7 records the answers).

Stage 1 ([HANDOVER.md](HANDOVER.md) §4) gives students the app they use every day. They can:
- see today and check in;
- see their attendance and ask for leave;
- see their classes and hand in homework;
- take tests and see their results;
- see the timetable and calendar;
- chat and open resources.

Written 17 Nov 2026 against tes-taker `develop` `0ae47df` and beta, after reading the web's student pages and calling every student endpoint on beta as a test student. The calls were read-only, and the account was signed out afterwards.

## 1. Screens, web pages and API

Each screen copies the web page named here: the same wording, rules and order. Every endpoint below is one the web already uses; nothing is invented (API guide §8).

| Screen | Web | API (all checked on beta, 17 Nov) |
| --- | --- | --- |
| **Today** | `/today` (`TodayPage`) | `GET /attendance/me/today` (classes, check-in windows, own record, `time_zone`); `GET /calendar/me?from&to` (exams, homework and events for today and the next days) |
| **Check-in** | from Today | `POST /attendance/check-in`: online classes send nothing; in-person classes send `latitude`, `longitude`, `accuracy_m` (100 m or better, inside the branch radius). Open from 15 min before the start until the end; once per class; no offline check-in (§6a) |
| **My attendance** | `/my-attendance` | `GET /attendance/me/calendar?month=YYYY-MM` (each day, totals) |
| **Leave** | `/leave` | `GET /attendance/leave/mine` (`can_apply`, own requests); `POST /attendance/leave` (dates, reason, optional file with purpose `LEAVE`: an image or a PDF); `POST /attendance/leave/:id/cancel` |
| **Classes** | `/classes` | `GET /student/classes`, `GET /student/classes/:id`; class discussions `GET/POST /classes/:id/subjects/:subjectId/…` (read and reply) |
| **Homework** | `/homework`, `/homework/[id]` | `GET /homework/mine`, `GET /homework/:id`, `GET /homework/:id/my-submissions`, `POST /homework/:id/submissions` (text, photos, files with purpose `HOMEWORK`); the score and the teacher's comment once published |
| **Tests** | `/tests` | `GET /student/exams/assigned`, `/upcoming`, `/history`; `GET /student/exams/:id/eligibility` (can start? proctoring level and checks) |
| **Taking a test** | `/test` | `POST /student/exams/:id/start`; answers saved as they change with `PUT /student/exams/:id/answersheet`; `POST /student/exams/:id/answersheet` to submit (retried while offline); Socket.IO default namespace `exam:join`, `heartbeat`, `flag:report`, `exam:submit`; teacher events `proctor:warning`, `exam:ended`; `POST /student/exams/:id/report-violation` |
| **Test result** | `/tests` → result | `GET /student/exams/:id/result` |
| **Marks** (Academic) | `/marks` | `GET /offline-exams/mine` |
| **Performance** (Academic) | `/performance` (own view) | `GET /scores/students/:myId` (own published results only) |
| **Report cards** (Academic) | `/report-cards` | `GET /report-cards/mine`, `GET /report-cards/:id?locale=`; printing and the share link stay on the web |
| **Timetable** | `/routine` | `GET /routine` (the student's week) |
| **Calendar** | `/calendar` | `GET /calendar/me?from&to` (month and agenda); `GET /reminders` (shown, not edited, §7.3) |
| **Chat** | `/chat` | `GET /chat/groups`, `GET /chat/direct`, `GET /chat/direct/contacts`, messages, post threads and comments, report a message, mute; Socket.IO `/chat` (`chat:message`, `chat:deleted`, `chat:read`, `chat:group`, `chat:subscribe`) |
| **Resources** | `/resources` | `GET /resources/mine`, folders, `POST /resources/:id/open`; files open through `GET /files/:id/content` |

**Not in Stage 1:**
- **`/learning`:** the web now redirects it to Classes, so the app drops it.
- **IELTS-only student pages** (`/ielts/*`): they keep "use the web for IELTS for now" (owner's decision 6). IELTS students do get the shared screens above as they are built.

**Files, the same for every screen** (API guide §6):
1. `POST /files/presign`;
2. `PUT` the bytes;
3. `POST /files/:id/complete`;
4. send the file id to the feature.

Showing a file goes through `GET /files/:id/content`. Its 1-hour redirect is never cached. An upload over quota gets the locked-feature sheet (`PLAN_LIMIT_REACHED`).

## 2. Pull requests, in order

Small PRs into `develop`, one at a time, each merged when CI is green and it has been checked on the emulator against beta. Every PR:
- adds its screen to `AppRoutes.built` (so the menu and notification links open it in the app instead of "use the website");
- keeps the plan's feature switches and the Academic/IELTS rules of the web's menu;
- covers loading, empty and error states, Bangla and English, Dhaka time, and phones from 360 px to tablets.

| # | PR | What |
| --- | --- | --- |
| 1 | **feat: files** | Upload (presign, PUT, complete) with progress and cancel; choose photos (camera or gallery) and documents; open or download a file. Packages: `image_picker`, `file_picker` (§3). Used by PRs 5, 7 and 13 |
| 2 | **feat: today** | Today (home): today's classes, events, exams and homework from the personal calendar, "Check-in is open" with a link to My attendance, due this week, coming up. As on the web, check-in itself is on My attendance (changed while building, 18 Nov) |
| 3 | **feat: my attendance** | Today's classes with their check-in window and own record, online check-in, the month calendar (present, late, absent, leave, holiday) and the totals. Today's classes kept in the read-only cache (owner's decision 5) |
| 4 | **feat: in-person check-in** | Location permission with the reason in Bangla and English; one accurate fix (100 m or better) sent with the check-in; clear messages for "too far", "not accurate enough", "location off", "not open yet" and "already checked in". Package: `geolocator` (§3) |
| 5 | **feat: leave** | My requests with their status; ask for leave (dates, reason, optional photo or PDF); withdraw a pending one |
| 6 | **feat: timetable** | The week by day, today first; kept in the read-only cache |
| 7 | **feat: homework** | List (due, handed in, marked), detail with the teacher's files, hand in text, photos and files before the due date (and late if allowed), see the score and comment |
| 8 | **feat: classes** | My classes and their subjects; class discussions (read and reply) |
| 9 | **feat: calendar** | Month and agenda of exams, homework, events and holidays; an item opens its screen in the app; my reminder settings shown read-only |
| 10 | **feat: tests list and results** | Assigned, upcoming and past tests; whether a test can be started and how it is proctored; results once published |
| 11 | **feat: taking a test** | Tests with proctoring Off or Light (§7.2); single and multiple choice, matching, written answers; a timer, answers saved as they change and on the phone, submit retried while offline, the teacher's warning and "ended by your teacher". Strict tests, and tests with a recorded (audio) answer, say "Use a computer for this test" (owner's decision 7). Package: `socket_io_client` (§3) |
| 12 | **feat: results** (Academic) | Marks, my performance, report cards (view only) |
| 13 | **feat: chat** | Class groups (posts, comments, pinned, announcement-only), private chat with teachers, send text and attachments, report a message, mute; live updates over Socket.IO `/chat` with a fresh token after each refresh |
| 14 | **feat: resources** | Folders and files shared with my classes; open, download |
| 15 | **test: student flows** | Integration tests (sign in, Today, check-in, hand in homework, take a test) against the fake API; the end-of-stage check on a 360 px phone, a tablet and iOS (Jubaer's Mac) |

PRs 2–6 make a useful app on their own; if time is short, they ship first.

## 3. Packages (each needs your approval)

| Package | Version | Licence | Publisher | Why | PR |
| --- | --- | --- | --- | --- | --- |
| `image_picker` | ^1.2.4 | Apache-2.0 / BSD-3 | flutter.dev | Photos from the camera or gallery for homework, leave and chat; resizes and compresses (`maxWidth`, `imageQuality`), so no separate compression package | 1 |
| `file_picker` | ^13.4.0 | MIT | victorcarreras.dev | PDFs and documents for homework, leave and chat | 1 |
| `geolocator` | ^14.1.2 | MIT | baseflow.com | One accurate location fix with its accuracy for in-person check-in; permission state | 3 |
| `socket_io_client` | ^3.1.6 | MIT | (no verified publisher) | Socket.IO client for chat (`/chat`) and the test connection (default namespace). The server is Socket.IO 4.8; this client supports v4. It is the Dart client most apps use; it has no verified publisher, so I'll pin the exact version and read its changes before every update | 11, 13 |

**Not needed:** a calendar widget package (the month grid is ours, as on the web), an image compression package, and a permissions package (`geolocator` and `image_picker` ask themselves).

**New permissions:**
- **Android:** fine location, plus camera for `image_picker`.
- **iOS:** `NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`, with the reason in English. The store descriptions get a Bangla version when the app is published.
- No background location, no microphone, no contacts.

## 4. Tests and checks

- **Each PR:** unit and widget tests against the fake API, covering every state (loading, empty, error, each status), both languages, and the codes that screen can meet (`FEATURE_NOT_IN_PLAN`, `PLAN_LIMIT_REACHED`, `NOT_IN_IELTS`, the check-in and leave refusals).
- **Beta checks:** done by hand on the emulator with the test accounts, signing out afterwards:
  - reading data as demo.student1;
  - checking in only inside a real check-in window, with the emulator's location set to the branch;
  - handing in homework and asking for leave only as test students (both are changes to beta, which the brief allows with test accounts).
- **No real test is started without a test exam made for it (§7.4),** and the IELTS mock is never touched.
- **Gaps on beta:** demo.student1 has no tests, marks, report cards or resources today, so those screens are checked for their empty state on beta and for content in the widget tests, unless §7.4 is approved.

## 5. Backend

Nothing blocks Stage 1: every endpoint above is on beta. If a screen meets a gap (for example, an answer missing a field the screen needs), I'll open a `mobile-api` issue in tes-taker rather than work around it.

Push notifications (PM-04) would help (homework due, test starting, chat). Until the backend has them, the bell polls every minute (Stage 0).

## 6. Rough size

About 15 PRs. Tests (PRs 10–11) and chat (PR 13) are the largest. Today to timetable (PRs 2–6) are small to medium.

## 7. Decisions (approved by the owner, 17 Nov 2026, as written)

The owner approved the plan as written, so each question below takes the suggestion made in it: the four packages and the permissions; Light proctoring as described; reminders read-only; one small test exam on beta as a Demo School teacher for demo.student1 (made when PR 11 is reached); class discussions in PR 8.

1. **Approve the four packages** in §3, and the new location, camera and photo permissions.
2. **Light proctoring in the app.** The web's Light level watches the browser (leaving the tab, leaving full screen, refreshing the page, copy and paste). In the app I suggest:
   - leaving the app (switching apps, going home) counts as the web's "tab switch" and is reported the same way;
   - screenshots and screen recording are blocked during a test on Android (`FLAG_SECURE`, no package needed); iOS can't block them;
   - copy and paste is turned off in answers.

   The teacher sees the same flags as from the web. OK?
3. **Calendar reminders:** show them read-only in the app for now, and edit them on the web? Reminders reach the phone only through the bell until push (PM-04) exists, so editing them in the app isn't worth much yet.
4. **A test exam on beta:** may I create one small test as a demo teacher (Demo School), assigned to demo.student1, with proctoring Off and then Light? It would let me check taking a test end to end on beta. Otherwise PR 11 is checked against the fake API only.
5. **Class discussions** (reading and replying in a subject's discussion): include them in Stage 1 (PR 8), as on the web? Or leave them for later and give students chat only?

