# Instructor app — status report

**Updated 24 Nov 2026** (first written 23 Nov) for the owner and the backend session. Checked against the code, the pull requests, CI, the published test builds, a fresh test run, and a walk of every role on beta with a release build. Where something isn't known, the report says so. The day-to-day log stays in [STATUS.md](STATUS.md). How to make a store build is in [RELEASING.md](RELEASING.md).

## 1. Summary

- **Every stage in the handover (0 to 5) is built,** plus the finishing work of 24 Nov: 121 pull requests, released to `main` as version 0.1.0 right after this report (§6).
- **Checked on beta with a release build** (test build 137 on the Pixel 8 emulator, phone and tablet size):
  - every page of every role that has a demo account (student, teacher and class teacher, owner, admin, staff, solo teacher);
  - every IELTS screen as an IELTS teacher and student, including Listening audio and Speaking recording.
  - The IELTS walk found five bugs, all fixed (#112).
- **Not yet checked:** a **real Android phone**, an **iPhone** (Jubaer's Mac), and the **branch manager** role (there is no demo account: tes-taker#360).
- **Before the stores, the humans' part:**
  - store accounts;
  - approving the privacy policy draft and listing texts;
  - keeping the upload key safe and putting it in GitHub;
  - a real-phone walk;
  - the iPhone check.
- **Before the stores, the backend's part:**
  - account deletion (#358);
  - the privacy and deletion web pages (#359).
- **Builds talk to beta.** Production is one setting away (`APP_ENV`, RELEASING §1) and stays off until the owner says production is live.

## 2. Stages 0–5: plan against what was built

| Stage | Who | Plan | Pull requests | State |
| --- | --- | --- | --- | --- |
| 0 | Everyone | Project, theme, Bangla/English, API client, sign-in, sign-up, workspaces, menu, notifications, account, locked features | Plan #2; built #3–#18 | Done |
| 1 | Students | Today, check-in, attendance, leave, homework, classes, discussions, calendar, timetable, tests, results, resources, chat | Plan #19; built #20–#33, #35, #36 | Done |
| 2 | Teachers | Dashboard, attendance, paper register, leave approvals, classes, homework, plagiarism, tests (list, monitor, integrity, marking), paper-exam marks, behaviour, performance, report cards, chat, resources | Plan #37; built #34, #38–#47, #49–#59; fixes #48, #60, #61 | Done |
| 3 | Owners, admins, assistants, branch managers | Overview, people, subjects and classes, who teaches what, sessions, attendance settings, holidays, branches, class setup, settings, grading scale, chat review, logs, plan (view only), reports | Plan #62; built #63–#78; check #79 | Done |
| 4 | Authoring | Academic setup wizard; create and edit tests with every academic question type | Plan #80; built #81–#88; beta check #89 | Done |
| 5 | IELTS | Overview, courses, students, band tables, tests and builder, openings, all four modules, marking, Speaking examiner, progress, band report, Writing plagiarism, IELTS in the wizard | Plan #90; built #91–#103; **beta walk and fixes #112** | Done, checked on beta |
| — | Finishing (23–24 Nov) | Device checks, network permission, report, result codes, lint, flaky test, production switch, iOS Bangla texts, phone gaps, store material | #104–#121 (§2.2) | Done |

### 2.1 What the 24 Nov work added

| PR | What |
| --- | --- |
| #106 | This report |
| #107 | Result refusals by code: "not published" or "another workspace" (tes-taker#351) |
| #108 | Android lint's release check back on (lint 9.5.2 reads the plugin that crashed 9.3.1) |
| #109 | The flaky plagiarism "run now" test made deterministic |
| #110 | Production switch (`APP_ENV`) and a store-build workflow (signed `.aab`); RELEASING.md |
| #111 | iOS permission texts in Bangla, and iOS told the app speaks Bangla |
| #112 | Five IELTS fixes from the beta walk |
| #113 | Edit discussion posts and comments, delete comments |
| #114 | Notification settings (SMS/email per kind of message) |
| #115 | Store material: 512 px icon, screenshots, listing (Bangla/English), data-safety sheet, privacy draft |
| #116 | Students can ask to become a teacher |
| #117 | Class and test share links open in the app; "Join with a link" |
| #118 | IELTS Reading highlights and notes |
| #119 | `mocktail` removed (unused) |
| #120 | Join links: an "already a member" page and a focused link field (found on build 137) |
| #121 | This update: report, status, more screenshots |

### 2.2 Skipped, cut down or left on the web

| From SCREENS.md | In the app | Why |
| --- | --- | --- |
| ~~Join a class or test by link~~ | **Done (#117).** Links open the app's pages; Android opens them by itself once the website serves `assetlinks.json` (tes-taker#361); iPhone links wait for the Apple account | |
| ~~Discussions: editing a post, deleting a comment~~ | **Done (#113)** for your own posts and comments | |
| ~~IELTS Reading highlights and notes~~ | **Done (#118)** | |
| ~~Account extras: notification channels, "become a teacher"~~ | **Done (#114, #116)** | |
| Account: profile photo | Not built | The API has no endpoint for it |
| Chat: teachers deleting other people's comments | On the web | Moderation is rare on a phone; the web has the fuller view |
| Help | "Use the website for now" | The web's Help is long reading with screenshots; better on a big screen |
| Learning (`/learning`) | Left out | The web sends it to Classes |
| Live classes and recordings | Left out | Server side not deployed (owner: stays out) |
| Platform admin, report-card printing, payment pages, public report link | Web only | By design |
| Calendar week/day views, adding events | Month view only | Kept small for phones |
| Timetable editing | Read only | Owner's decision (Stage 1) |
| Charts | Figures and lists | Would need a chart package; the figures carry the same information |
| Printing (report cards, registers, band report, question paper) | Web | Phones print poorly; needs a PDF package |
| CSV imports and sheets | Web | Owner's decision (Stage 3 §7) |
| Rich text (bold, links, tables, maths) | Plain paragraphs; formatted content opens read-only with "Edit on the website" | So nothing made on the web is damaged |
| Homework photos combined into one PDF | Each photo uploaded separately | Needs a PDF package |
| Tests: import/export, dictation, passage media, matching images, option reordering | Web | Stage 4 plan §7 |
| Strict proctoring | "Use a computer" | Needs the web's camera and screen checks |
| IELTS mocks on phones | Tablets only (practice sets work on phones) | Same rule as the web (IEL-08) |
| Push notifications, Google sign-in | Not built | Server work comes later (owner) |

## 3. What each role can do

| Role | In the app | Still on the web |
| --- | --- | --- |
| **Student** | Today; check-in; my attendance; leave; timetable; homework; classes and discussions (edit own posts/comments); join a class or test by link; calendar; tests (Off and Light proctoring); results; resources; chat; account (notifications, become a teacher) | Strict tests; printing; calendar week/day; Help |
| **Teacher / class teacher** | Dashboard; class attendance; reports; paper register; leave approvals (class teacher); classes; discussions; homework and plagiarism; tests (list, monitor, integrity, marking, create and edit); paper-exam marks; behaviour; performance; report cards; chat; resources; calendar | Formatted or media tests; CSV sheets; printing; charts |
| **Owner / admin / staff** | All of the above their role allows, plus overview, setup, people, subjects and classes, who teaches what, sessions, attendance settings, holidays, branches, class setup, settings, grading scale, chat review, logs, plan (view only), reports | CSV imports; buying plans (no buy buttons or links, owner's rule) |
| **Branch manager** | Today and their branch's IELTS courses (the server closes the rest) | **Not checked on beta:** no demo account (tes-taker#360) |
| **IELTS staff** | Overview; courses; students; tests and builder (Listening recordings play in the app); band tables; openings and results; Writing and Speaking marking; Speaking examiner with recording; progress; band report; Writing plagiarism | Printing the band report; formatted passages |
| **IELTS student** | Overview; my courses; my tests: Listening, Reading (highlights, notes), Writing, Speaking practice; results; profile; progress | Mocks on a phone (tablet or computer) |

## 4. Quality

### Tests (run on 24 Nov 2026)

| Kind | Count |
| --- | --- |
| All automated tests | **771**, all passing (738 on 23 Nov) |
| Widget tests written | 549 |
| Unit tests written | 203 |
| Test files | 103 |
| End-to-end flows (fake server) | 17 in 5 files |
| `flutter analyze` | No issues |

**CI:** every PR ran format, analyze and tests, plus an unsigned iOS build. Every merge into `develop` built a signed Android release APK, with release lint on since #108. The release PR into `main` was green on all of these (§6).

### Where it was checked (24 Nov)

| Where | What |
| --- | --- |
| **Release build on the emulator** (test build 137, Pixel 8, Android 16), against beta | **Every menu page** for demo.student1 (15), demo.teacher1 (21, a class teacher), demo.owner (40, the full menu), demo.admin (20, the first two screens of its menu; the rest are the owner's pages), demo.staff and demo.solo: no error views. Pages that need a computer say so, by design. |
| IELTS on beta (Bright Path IELTS), phone and tablet | **ielts.teacher1:** overview, tests, builder, openings, results, Writing and Speaking marking, band tables, students. **ielts.student09:** Mock 2 Listening (audio played, answer saved, handed in, result 1/40, band 1.0) and the Reading practice (split view, handed in, answers shown). **Speaking:** teacher1 recorded student 09's Part 1 through the microphone; it uploaded and played back. No marks saved; students 03, 04 and 07 untouched. |
| New 24 Nov features on the release build | Build 137, demo.student1: the Notifications card loads the real settings; "Become a teacher" shows (no request sent); a pasted Class 6 link opens its page (that check found #120). ielts.student10: Reading highlight on a phone. ielts.teacher1: overview headings on one line. |
| **Real Android phone** | **Not yet** (owner) |
| **iPhone** | Only CI's unsigned build. **Not yet on Jubaer's Mac.** |

### Known bugs and gaps

| Severity | What | State |
| --- | --- | --- |
| High | Never run on a real phone or iPhone (camera, GPS, microphone, notch and keyboard on real hardware) | Owner and Jubaer (§8) |
| Medium | Branch manager not checked on beta | tes-taker#360 |
| Medium | Share links open the app by themselves only after `assetlinks.json` is live; until then people pick the app or paste the link | tes-taker#361 |
| Low | Twice on 23–24 Nov, one widget test (a different one each time) was reported "did not complete" in a local full run while the computer was busy with the emulator. Neither failed again (5 and 4 reruns); CI has not failed once in its last 100 runs | Watch it; not a code fault found |
| Low | ielts.teacher1 sees no courses and an empty teacher home on beta: the demo courses have no module teachers (seed data, not the app) | Backend, optional |
| ~~Critical~~ | ~~No INTERNET permission in test builds up to 117~~ | Fixed (#105), checked in builds 119+ |
| ~~Low~~ | ~~Every 403 read as "not published"~~ | Fixed (#107) |
| ~~Low~~ | ~~Flaky plagiarism test~~ | Not reproduced in 45 runs; made deterministic (#109) |
| ~~Low~~ | ~~Release lint off~~ | On again (#108) |

## 5. Backend dependencies

| Issue (tes-taker) | What | State |
| --- | --- | --- |
| #345, #349 | Sign-up error codes; homework uploads | Closed 17 Nov |
| #351, #352, #353 | Result codes; IELTS demo accounts; true/false name | Closed 24 Nov, used by the app |
| **#358** | **Account deletion** (deactivate and anonymise, keep the school's history, password/OTP check, owners hand over first) | **Open: needed for both stores.** The app's screen comes once it's on beta |
| **#359** | **Privacy policy and account-deletion web pages** | **Open: needed for both stores** |
| #360 | Branch-manager demo account | Open |
| #361 | `assetlinks.json` for share links | Open |

Later, by the owner's plan: push notifications, Google sign-in, live classes.

## 6. Builds and release readiness

### Installing a test build

1. On the phone, open [Releases](https://github.com/Sadiquzzaman/instructor-app/releases) and take the newest "Instructor 0.1.0 test build N" (about 76 MB).
2. Allow installs from the browser or Files when Android asks, and install. It installs over earlier test builds and talks to beta.
3. Sign in with a demo account (the password isn't in this repository).

### The app

| | Android | iOS |
| --- | --- | --- |
| App id | `academy.instructor.app` | `academy.instructor.app` |
| Version | 0.1.0; test builds use the CI run number, store builds 10000 + run | 0.1.0 |
| Minimum | Android 7.0 (API 24), targets 36 | iOS 15.0 |
| Languages | Bangla, English (permission texts too) | Same (#111) |

### Signing

- **Test key** (GitHub test builds): outside the repo, in Actions secrets.
- **Play upload key:** **made on 24 Nov**, outside the repo (`.local-secrets/android-upload-signing`). **The owner backs it up and adds its four GitHub secrets** (RELEASING §2; I wasn't allowed to store secrets in GitHub myself).
- **iOS:** needs the owner's Apple Developer account; nothing to do until then.

### What the stores need

| Item | State |
| --- | --- |
| Developer accounts (Play $25 once; Apple yearly) | **Owner** |
| 512 px Play icon, iOS 1024 px icon | Done (#115, #18) |
| Screenshots | Phone and tablet, from the emulator (`docs/store/screenshots`); iPhone ones on Jubaer's Mac |
| Listing texts, Bangla and English | Drafted (`docs/store/listing.md`), **owner approves** |
| Data safety / App Privacy | Answer sheet ready (`docs/store/data-safety.md`); **owner decides the target age** |
| Privacy policy | Draft (`docs/PRIVACY-DRAFT.md`), **owner approves**; web page: tes-taker#359 |
| Account deletion | **Waits for tes-taker#358**, then the app's screen |
| Upload key, signed `.aab` | Key made; workflow ready (`store-release.yml`); needs the owner's secrets |
| Production | Switch ready (`APP_ENV`); off until production is live |
| Review accounts | **Owner:** demo accounts on production for the reviewers |
| Payments | Nothing sold, no links to buy (owner's rule) |

## 7. Packages

All free and open source. Nothing was added on 24 Nov; `mocktail` was removed.

| Package | Version | Licence | Why |
| --- | --- | --- | --- |
| dio | 5.11.1 | MIT | API |
| flutter_riverpod | 3.5.0 | MIT | State |
| go_router | 18.1.4 | BSD-3 | Pages and links |
| flutter_secure_storage | 11.2.0 | BSD-3 | Sign-in storage |
| shared_preferences | 2.5.6 | BSD-3 | Settings, drafts, notes |
| intl | 0.20.3 | BSD-3 | Languages, dates |
| package_info_plus | 10.2.2 | BSD-3 | App version |
| device_info_plus | 13.3.0 | BSD-3 | Device name for "your devices" |
| url_launcher | 6.3.3 | BSD-3 | Links, files |
| material_ui | 1.11.1 | BSD-3 | Material widgets |
| cupertino_ui | 1.1.7 | BSD-3 | iOS widgets |
| image_picker | 1.2.4 | Apache-2.0/BSD-3 | Camera, photos |
| file_picker | 13.4.0 | MIT | Files |
| geolocator | 14.1.2 | MIT | Check-in |
| socket_io_client | 3.1.6 | MIT | Live tests, chat |
| just_audio | 0.10.6 | MIT/Apache-2.0 | IELTS audio (**approved 24 Nov**) |
| record | 7.2.0 | BSD-3 | IELTS Speaking (**approved 24 Nov**) |
| *Dev:* flutter_lints, flutter_launcher_icons, flutter_native_splash | | BSD-3/MIT | Lint, icon, splash |

GitHub Actions added on 24 Nov: `actions/upload-artifact` v7.0.2 (MIT), for the store bundle.

## 8. Steps left for people

**Owner**
1. Create the Google Play Console and Apple Developer accounts.
2. Back up the upload key and add its four GitHub secrets (RELEASING §2).
3. Approve or edit `docs/PRIVACY-DRAFT.md` (fill in the blanks), the listing texts, and the target-age choice in `docs/store/data-safety.md` §4.
4. Install the newest test build on a real Android phone and walk each role (camera, check-in, a test, chat, IELTS Listening and Speaking).
5. When production is live, set `APP_ENV=production`, and make reviewer demo accounts on production.

**Jubaer (Mac)**
1. `flutter build ios`, then run on an iPhone set to Bangla. Check the permission prompts (camera, location, microphone, photos), the Bangla text menus, IELTS audio and recording.
2. Take iPhone screenshots for the App Store.

**Backend**
1. #358 account deletion, then #359 the two web pages. Then the app adds its Delete account screen.
2. #361 `assetlinks.json`; #360 a branch-manager demo account.
