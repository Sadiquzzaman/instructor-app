# Instructor app — status report

**Written 23 Nov 2026** for the owner and the backend session. Checked against the code on `develop`, the pull requests, CI, the published test builds and a fresh test run. Where something isn't known, the report says so. The day-to-day log stays in [STATUS.md](STATUS.md).

## 1. Summary

- **Every stage in the handover (0 to 5) is built and merged into `develop`:** 105 pull requests, none open, nothing on `main` yet.
- **Students, teachers, owners and IELTS centres** can do almost everything they do on the web. What stays on the web is mostly printing, CSV imports and a few rich-text and media cases (§2).
- **Can a real school use it on Android today? Not yet, for two reasons.**
  1. **The network permission.** Until PR #105 (merged 23 Nov), the test APKs had no Android INTERNET permission, so on a real phone they couldn't reach the server. Every check so far ran on the emulator with a debug build, which adds it by itself. Build 119 (the first build after the fix, checked with `aapt`) and later have it. **The app has never been tried on a real phone.**
  2. **IELTS has never touched beta.** No demo account has an IELTS workspace (tes-taker#352), so the IELTS screens are tested only against a fake server.
- **Before a store release:**
  - a real-phone check of each role;
  - the iOS check on Jubaer's Mac (nothing done there yet);
  - a Play upload key and the Apple signing setup;
  - a privacy policy, the Play data-safety form and the store listing;
  - in-app account deletion, which both stores require and which the API doesn't have yet (§6).

## 2. Stages 0–5: plan against what was built

| Stage | Who | Plan | Pull requests | State |
| --- | --- | --- | --- | --- |
| 0 | Everyone | Project, theme, Bangla/English, API client, sign-in, sign-up, workspaces, menu, notifications, account, locked features | Plan #2; built #3–#18 (14 PRs, plus #6 CI caching and #16 the tes-taker#345 error codes) | Done |
| 1 | Students | Today, check-in, attendance, leave, homework, classes, discussions, calendar, timetable, tests (taking them), results, resources, chat | Plan #19; built #20–#33, #35, #36 (16 PRs) | Done |
| 2 | Teachers | Dashboard, attendance, the paper register, leave approvals, classes, homework, plagiarism, tests (list, monitor, integrity, marking), paper-exam marks, behaviour, performance, report cards, chat, resources | Plan #37; built #34, #38–#47, #49–#59 (15 planned PRs, some split in two); fixes #48, #60, #61 | Done |
| 3 | Owners, admins, assistants, branch managers | Overview, people, subjects and classes, who teaches what, sessions, attendance settings, holidays, branches, class setup, settings, grading scale, chat review, logs, plan (view only), reports | Plan #62; built #63–#78 (13 planned PRs); check #79 | Done |
| 4 | Authoring | Academic setup wizard; create and edit tests with every academic question type | Plan #80; built #81–#88 (8 PRs); beta check #89 | Done |
| 5 | IELTS | Overview, courses, students, band tables, tests and the builder, openings, taking all four modules, marking, Speaking examiner, progress, band report, Writing plagiarism, IELTS types in the wizard | Plan #90; built #91–#103 (13 PRs) | Done in code; never checked on beta |
| — | Fixes and checks | Stage 0 and 1 device checks; the network permission for release builds | #104, #105 | Done |

### Skipped, cut down or left on the web

| From SCREENS.md | In the app | Why |
| --- | --- | --- |
| Help | "Use the website for now" | Not planned in any stage |
| Join a class or test by link or code (`/join/...`) | Not built; such links open in the browser | Deep links were planned for "later" and never scheduled |
| Learning (`/learning`) | Left out | The web now sends it to Classes |
| Live classes and recordings (IELTS P12) | Left out | The server side isn't deployed (switch `live_classes` is off) |
| Platform admin, report-card printing, payment pages, public report link | Web only | By design (HANDOVER and SCREENS) |
| Calendar | Month view only; week and day views and adding events stay on the web | Kept small for phones |
| Timetable | Read only; changing it stays on the web | Owner's decision in the Stage 1 plan |
| Charts (attendance, performance) | Figures and lists instead of charts | No chart package |
| Printing (report cards, registers, band report, question paper) | On the web | Phones print poorly; would need a PDF package |
| CSV files (member and student imports, paper-exam sheet, class times) | On the web | No CSV/file package; owner's decision (Stage 3 §7) |
| Rich text (bold, links, tables, maths) | Shown as plain paragraphs; anything with formatting opens read-only with "Edit on the website" | Option A in the Stage 4 plan, so nothing made on the web is damaged |
| Homework photos combined into one PDF | Each photo is uploaded separately | Needs a PDF package |
| Discussions: editing a post, deleting a comment; chat: deleting others' comments | On the web | Left for a second pass |
| Tests: question import/export, voice dictation, passage audio/images, images on matching items, reordering options | On the web | Stage 4 plan §7 |
| Strict proctoring tests | The app says "use a computer" | Strict needs the camera and screen checks of the web |
| IELTS mocks on phones | Tablets only (practice sets work on phones) | Same rule as the web (IEL-08) |
| IELTS Reading highlights and notes | Not yet; the passage is selectable text | Left for later (TODO.md) |
| Account page extras (photo, notification channels, "become a teacher") | Not yet | TODO.md |

## 3. What each role can do

"Everyone" means all roles: sign in, sign up, workspaces, notifications (the bell checks every so often; there is no push yet), account, Bangla/English, plan features. The app shows each person exactly the menu the web shows them (`sidebarList`), filtered by the workspace type and the plan.

| Role | In the app | Still on the web |
| --- | --- | --- |
| **Student** (school) | Today; check-in by location; my attendance; leave (apply, withdraw); timetable; homework (hand in text, photos, files; see the score); classes and discussions; calendar; taking tests (Off and Light proctoring); results (marks, performance, report cards); resources; chat | Strict tests; printing report cards; editing a discussion post; calendar week and day views; Help |
| **Teacher** | Dashboard; class attendance (and changing a class for one day); attendance reports; the paper register; classes; discussions; set and mark homework; plagiarism; tests (list, live monitor, integrity report, marking written answers); **creating and editing tests**; paper-exam marks; behaviour; performance; report cards; chat; resources; calendar; my attendance | Tests with formatting, maths or passage media; importing or downloading question papers; the paper-exam CSV sheet; printing; charts |
| **Class teacher** | Everything a teacher has, plus leave approvals for their section | As teacher |
| **Owner / admin / assistant** | Everything above that their role allows, plus: overview; setup wizard; teachers, assistants, students, invitations, pending; subjects and classes; who teaches what; sessions and terms; attendance settings, holidays, branches and the check-in pin; class setup; homework, plagiarism and performance settings; grading scale; chat review; activity and message logs; plan and usage (view only); the teachers' attendance report; whole-school performance. The app hides what the web hides for each role, but I haven't checked each difference between owner, admin and assistant one by one. | CSV imports; buying or changing the plan (by the owner's rule, the app shows no buy buttons or links) |
| **Branch manager** | Today, and the IELTS courses of their branch (the API refuses them everything else, and the app shows only what answers) | Everything else is closed to them by the server, on the web too |
| **IELTS staff** | IELTS overview; courses; students and profiles; the tests list and builder; band tables (owners and admins edit); openings and results; Writing marking; the Speaking examiner; progress; band report; Writing plagiarism; the shared pages (chat, resources, calendar) | Printing the band report; editing a passage that has formatting; live classes (not built anywhere yet) |
| **IELTS student** | Overview; my courses; my IELTS tests: Listening (plays once), Reading, Writing, Speaking practice recordings; results; my profile; progress; band report | Mocks on a phone (they need a tablet or computer); Reading highlights and notes |

## 4. Quality

### Tests (run on 23 Nov 2026)

| Kind | Count | Notes |
| --- | --- | --- |
| All automated tests | **738**, all passing | `flutter test` after PR #105 (736 before it) |
| — widget tests (`testWidgets`) | 530 written | Screens in both languages, 360 px phones, tablets, plan switches, error codes |
| — unit tests (`test`) | 187 written | Request bodies, rules (bands, dates, checks) |
| — end-to-end flows | 17, in 5 files | Student, teacher, owner, authoring, IELTS, against the fake server |
| Integration tests (device runner) | 6 files: the 5 flows plus sign-in | The teacher flows ran on the emulator once (Stage 2); the others haven't, because a device run reinstalls the app and wipes its session |
| `flutter analyze` | No issues | |

The written counts (530 + 187) are lower than the 738 run because some tests repeat over a list of cases. The 97 test files are under `test/`.

**Last CI on `develop`** (commit `a9cdf69`, 21 Nov, #104): CI (format, analyze, tests) ✅, Android pre-release ✅, iOS build (unsigned) ✅. CI for #105 is running as this is written; this report's PR will show its result.

### Where it was checked

| Where | What | When |
| --- | --- | --- |
| **Real Android phone** | **Nothing yet** | — |
| Android emulator (Pixel 8, Android 16) against beta | Stage 0 screens in Bangla at 360 dp; every student page at 360 dp and on a tablet (demo.student1); every teacher page at 360 dp and on a tablet (demo.teacher1); owner pages at 360 dp and the main ones on a tablet (demo.owner); the create-test screen at 360 dp and on a tablet. No layout errors in logcat. | 19–21 Nov |
| Beta, through the app's own requests | Stage 1: a student took a test end to end. Stage 4: a test published, loaded back, saved and switched off (demo.teacher1). | 18 and 21 Nov |
| IELTS on beta | **Nothing**: no demo IELTS account (tes-taker#352) | — |
| **iOS** | Only CI's unsigned build. **Nothing on Jubaer's Mac yet.** | — |

### Languages and screens

- **Languages:** every screen is in Bangla and English. The wording comes from the web's files, plus the app's own strings. Tests fail if the two languages don't have the same messages, if a message is empty, or if a Bangla message isn't in Bangla.
- **Text from the server:** notifications are stored in English by the server, so they show in English in either language.
- **Screen sizes:** each feature's tests include a 360 px phone in Bangla, and the main screens are also tested at tablet size. Tablets get two panes where it helps (test builder, Reading).

### Known bugs and gaps

| Severity | What | State |
| --- | --- | --- |
| **Critical** | Test APKs up to build 117 have no INTERNET permission, so they can't reach the server on a real phone | **Fixed in PR #105**; build 119 and later have it (checked), and a test guards it |
| High | Never run on a real phone or on iOS, so problems only real hardware shows (camera, GPS check-in, microphone, audio, notch, keyboard) are unknown | Open |
| High | IELTS never run against the real server | Waits for tes-taker#352 |
| Medium | Web bug: the web sends IELTS True / False / Not Given as `true-false`, which the server's form refuses; the app sends `true-false-not-given` | tes-taker#353, open |
| Low | Any 403 on a test result is read as "not published yet", which could hide another reason | tes-taker#351, open |
| Low | One widget test (`plagiarism_test.dart`, "run now") didn't finish once in a full run on 23 Nov; it passed alone and in the next full run | Flaky test; watch it |
| Low | Android lint's release check is turned off (it crashes on a plugin's source) | TODO.md |

## 5. Backend dependencies

| Issue (tes-taker) | What | State | How the app copes |
| --- | --- | --- | --- |
| #345 | Error codes for sign-up, OTP and password reset | Closed 17 Nov | Used; the app shows its own words for each code |
| #349 | Homework uploads refused (purpose HOMEWORK) | Closed 17 Nov (fixed on beta) | Homework files upload |
| #351 | A code for "result not published yet" | Open, low | Any 403 on the result counts as "not published yet" |
| #352 | Demo IELTS accounts on beta | Open | IELTS tested on the fake server only |
| #353 | IELTS true/false name mismatch | Open | The app sends the name the server accepts |

**Waiting on planned backend work (no issue needed):**
- Google sign-in for apps (PM-02): no "Continue with Google";
- push notifications (PM-04): the bell checks every so often;
- live classes (`live_classes`): left out.

**Worked around in the app:**
- **Time zone:** no API gives the organisation's time zone, so the app uses Asia/Dhaka in one place (`OrgTime`), as the web hard-codes it.
- **Account deletion:** the API has no endpoint. Nothing works around it; it's needed for the stores (§6).
- **File content links** (`/files/:id/content`) need no login header, so the app opens and plays them directly.

## 6. Builds and release readiness

### Installing the latest test build

1. On the phone, open [Releases](https://github.com/Sadiquzzaman/instructor-app/releases) and take the newest "Instructor 0.1.0 test build N". **Use build 119 or later.** Builds up to 117 can't reach the server on a real phone (§4).
2. Download the file `instructor-v0.1.0-dev.N.apk` (about 76 MB).
3. Open it. Android asks once to allow installs from this source (the browser or Files); allow it.
4. Install. It installs over earlier test builds, because all are signed with the same test key. It talks to beta (api-beta.instructor.academy).
5. Sign in with a demo account. The password isn't written anywhere in this repository.

Every merge into `develop` publishes a new test build automatically.

### The app

| | Android | iOS |
| --- | --- | --- |
| App id | `academy.instructor.app` | `academy.instructor.app` |
| Version | 0.1.0, with the build number from the CI run (build 117 = versionCode 117) | 0.1.0 |
| Minimum | Android 7.0 (API 24); targets API 36 | iOS 15.0 |
| Name, icon, splash | "Instructor", from the owner's logo (#18) | Same |

### Signing

- **Android test key:** created by me in Stage 0. It lives outside the repo on the development computer (`.local-secrets`, next to the repo folder), and its four values are in the repo's GitHub Actions secrets. CI signs every test build with it and checks the signature. The key and passwords are never committed or printed.
- **Android release (Play upload) key:** **not created yet.** Google Play App Signing needs an upload key from the owner, or one we create and the owner keeps.
- **iOS:** no certificates or provisioning profiles exist yet. That needs an Apple Developer account and Jubaer's Mac.

### What the stores need

| Item | Google Play | App Store | State |
| --- | --- | --- | --- |
| Developer account | Play Console ($25 once) | Apple Developer Program (yearly fee) | **Unknown**: not set up by me; the owner's decision |
| App icon | 512 px store icon | 1024 px icon | **App icons done** from the owner's logo (#18), including the iOS 1024 px one; the 512 px Play icon still has to be exported for the listing |
| Signing | Upload key + Play App Signing | Certificates and profiles | **Not done** |
| Screenshots | Phone (and tablet) | iPhone 6.7"/6.5" (and iPad) | **Not done** |
| Store listing | Short and full description (Bangla and English) | Description, keywords, support URL | **Not done** |
| Privacy policy URL | Required | Required | **Not found**: none in the repo or linked from the app |
| Data safety / App privacy form | Required: location (check-in), microphone (IELTS Speaking), photos and files (uploads), account data, device id | Same | **Not done** |
| In-app account deletion | Required for apps with sign-up | Required | **Missing**: needs an API endpoint (tes-taker) and a screen |
| Permissions explained | Location, microphone, camera/photos | Usage texts in Info.plist | Android declared; iOS texts in English only (Bangla needs Xcode) |
| Payments | The app sells nothing and links nowhere to buy | Same | **Done** (owner's rule) |
| Review account | A demo login for the reviewers | Same | Demo accounts exist on beta, but reviewers would need **production** accounts |
| Production server | Builds point at beta today | Same | A production build setting (`API_BASE_URL`) exists; **not tried against production** |

## 7. Packages

| Package | Version | Licence | Why | Approved |
| --- | --- | --- | --- | --- |
| dio | 5.11.1 | MIT | Talking to the API | Stage 0 plan, 17 Nov |
| flutter_riverpod | 3.5.0 | MIT | App state | Stage 0 |
| go_router | 18.1.4 | BSD-3 | Pages and links | Stage 0 |
| flutter_secure_storage | 11.2.0 | BSD-3 | Keeping the sign-in safe | Stage 0 |
| shared_preferences | 2.5.6 | BSD-3 | Settings, drafts, the offline copy | Stage 0 |
| intl | 0.20.3 | BSD-3 | Bangla/English, dates, digits | Stage 0 |
| package_info_plus | 10.2.2 | BSD-3 | The app's version | Stage 0 |
| device_info_plus | 13.3.0 | BSD-3 | The device name for "signed-in devices" | Stage 0 |
| url_launcher | 6.3.3 | BSD-3 | Opening links and files | Stage 0 |
| material_ui | 1.11.1 | BSD-3 | Flutter's Material widgets | Stage 0, 17 Nov |
| cupertino_ui | 1.1.7 | BSD-3 | iOS-style widgets and their Bangla texts | 17 Nov |
| image_picker | 1.2.4 | Apache-2.0 / BSD-3 | Camera and photos | Stage 1 plan, 17 Nov |
| file_picker | 13.4.0 | MIT | Choosing files | Stage 1 |
| geolocator | 14.1.2 | MIT | Check-in by location | Stage 1 |
| socket_io_client | 3.1.6 (pinned) | MIT | Live tests and chat | Stage 1 |
| **just_audio** | 0.10.6 | MIT / Apache-2.0 | IELTS Listening; playing recordings | **Not explicitly approved**: listed in the Stage 5 plan §3 and added under the owner's standing instruction ("do not wait for my approval") |
| **record** | 7.2.0 | BSD-3 | IELTS Speaking recordings | **Not explicitly approved**: same as just_audio |
| *Dev only:* flutter_lints 6.0.0 (BSD-3), mocktail 1.0.5 (MIT), flutter_launcher_icons 0.14.4 (MIT), flutter_native_splash 2.4.8 (MIT) | | | Tests, lint, icon and splash | Stage 0 |

- **Other packages these bring in:** `just_audio` adds `audio_session` (MIT), `rxdart` (Apache-2.0) and `synchronized` (BSD-2). `record` adds its own `record_*` platform parts (BSD-3).
- **Unused:** `mocktail` is approved but no test uses it now; it can be removed.

## 8. Decisions needed from the owner, and next steps

### Decisions

1. **The two audio packages:** confirm `just_audio` and `record`, or say to remove them (IELTS Listening and Speaking would then go back to the web).
2. **Stores:** do you have (or want) a Google Play Console account and an Apple Developer account? Who keeps the Play upload key?
3. **Privacy policy:** who writes and hosts it (a page on instructor.academy)?
4. **Account deletion:** both stores require it. Shall I open a `mobile-api` issue for a delete-account endpoint?
5. **First release to `main`:** CLAUDE.md rule 17 says ask first. I recommend waiting until the real-phone check passes.
6. **Production:** when should builds point at the production API, and which accounts will the store reviewers use?

### Recommended next steps, in order

1. Install build 119 or later on a real Android phone and walk each role (student, teacher, owner) on beta, including camera, check-in, a test, and chat.
2. Ask the backend to seed IELTS demo accounts (tes-taker#352), then check every IELTS screen on beta, including the microphone and audio on a phone.
3. Have Jubaer run the iOS build on his Mac and an iPhone. Add the Bangla iOS permission texts there.
4. Open the account-deletion issue and build the screen once the endpoint exists.
5. Prepare the store items: upload key, privacy policy, data-safety form, screenshots, listing in Bangla and English.
6. Build against production with a review account, then release to `main` with your approval.
