# Stage 5 plan: IELTS

**Started 21 Nov 2026 on the owner's standing instruction** ("do not wait for my approval"); each §7 answer is my recommendation and is followed unless the owner says otherwise. Written against tes-taker `develop` `31f14b0` (17 Nov 2026, still the latest) and beta.

Stage 5 ([HANDOVER.md](HANDOVER.md) §4) brings the IELTS workspace to the app: everything an IELTS centre's staff and students do on the web. Until now IELTS-only pages show "Use the website for IELTS for now" (PROJECT-NOTES decision 6). It also takes the IELTS test builder and band tables, which Stage 4 left here.

I read the web's IELTS pages (`frontend/app/ielts/*`, `frontend/component/Ielts`, about 5,000 lines), the backend's `ielts` module (`ielts.controller.ts`, `ielts-courses.controller.ts`, `question-groups.ts`, `scoring.ts`, `bands.ts`) and design.md's P10-01 to P10-07 and P12 notes.

## 1. What the web has

Every IELTS route answers only in IELTS workspaces (403 `IELTS_ONLY_CENTRES`) and needs the plan's `ielts` feature. The menu (`sidebarList.tsx`) shows these items, with `workspaces: ["IELTS"]` and `feature: "ielts"`.

| Screen | Who | Web route | API |
| --- | --- | --- | --- |
| **Overview** | Staff; students | `/ielts/overview` | `GET /ielts/dashboard`, `GET /ielts/dashboard/me` |
| **Courses** | Staff and branch managers; students (my courses) | `/ielts/courses`, `/ielts/my-courses` | `GET`/`POST`/`PATCH`/`DELETE /ielts/courses(/:id)` |
| **Students and profiles** | Staff; a student's own | `/ielts/students`, `/ielts/me` | `GET /ielts/profiles`, `GET`/`PUT /ielts/profiles/:studentId`, `GET /ielts/profiles/me` |
| **Tests and the builder** | Staff (the maker, owners and admins change them) | `/ielts/tests`, `/ielts/tests/[id]` | `GET`/`POST`/`PATCH`/`DELETE /ielts/tests(/:id)`, parts, question groups (16 types), order, `publish`, `unpublish`, `archive`, `duplicate`; old academic exams converted (`/ielts/old-exams`) |
| **Openings and results** | Staff | `/ielts/tests/[id]/openings` | `GET`/`POST /ielts/tests/:id/assignments`, `PATCH`/`DELETE /ielts/assignments/:id`, `GET …/results` |
| **Band tables** | Staff read; owners and admins change | `/ielts/band-tables` | `GET`/`PUT /ielts/band-tables`, `POST …/reset` |
| **My tests and the test screen** | Students | `/ielts/my`, `/ielts/attempts/[id]` | `GET /ielts/my/assignments`, `POST …/modules/:module/start`, `GET`/`PUT …/my/attempts/:id(/answers)`, `POST …/submit` |
| **Speaking** | Students (practice recordings); staff (live examiner) | in the test screen, `/ielts/speaking/[attemptId]` | `PUT /ielts/my/attempts/:id/recordings`, `POST /ielts/assignments/:id/speaking`, `PUT /ielts/marking/:attemptId/recordings` |
| **Marking** | Staff | `/ielts/marking`, `/ielts/marking/[attemptId]` | `GET /ielts/marking`, `GET`/`PUT /ielts/marking/:attemptId/(writing|speaking)` |
| **Progress and band report** | Staff; a student's own | `/ielts/progress(/[studentId])`, `/ielts/report/[assignmentId]/[studentId]` | `GET /ielts/progress/:studentId|me`, `GET /ielts/report/…` |
| **Writing plagiarism** | Staff | `/ielts/assignments/[id]/similarity` | the Stage 2 plagiarism endpoints, IELTS scope |

**The test screen** works like the computer-delivered test. The timer runs from the server's clock, answers save as they change, and the module is handed in at 0:00.
- **Listening:** each part's recording plays once, with no pause or seeking.
- **Reading:** the passage sits beside its questions.
- **Writing:** the task beside an answer box with a live word count.
- **Speaking:** practice recordings per part, with Part 2's 1-minute preparation and 2-minute talk timers.

The web shows "use a computer or tablet" for mocks below 768 px (IEL-08).

**Not built on the server yet:** live classes and their recordings (IEL-14, IEL-15; `docs/LIVE-CLASSES-SERVER.md`: "Nothing here has been deployed yet"; switch `live_classes` off). They stay out of this stage.

## 2. Pull requests, in order

| # | PR | What |
| --- | --- | --- |
| 1 | **feat: IELTS menu and overview** | The IELTS menu from the web's rules (workspace type, roles, `ielts` feature, branch managers' courses only), the staff and student overviews; the "not yet" pages go as each screen lands |
| 2 | **feat: IELTS courses** | Staff: list, filter, create, change, delete (asked first); branch managers their branch's; students: my courses. `COURSE_FULL`/`SECTION_FULL` handled |
| 3 | **feat: IELTS students and profiles** | Staff: students with targets and test dates, change a profile (half bands); students: my profile |
| 4 | **feat: band tables and the tests list** | The three band tables (owners and admins edit, reset); the tests list with filters, new from a template, copy, archive, delete |
| 5 | **feat: IELTS test builder** | Tabs per module, parts (plain-text rule from Stage 4 §7.1 A, pictures and recordings as `IELTS` uploads), the 16 question-group types, order, publish with the server's problems listed; read-only when published or not theirs |
| 6 | **feat: openings and results** | Open a published test for a batch (times in the centre's zone), change, remove; results per student and module with the overall band |
| 7 | **feat: taking IELTS Reading and Writing** | My tests, start/continue, the test screen: server timer, autosave (and offline retry, as Stage 1's test screen), Reading side by side on tablets (stacked on phones for practice sets), every Listening/Reading question type, Writing with word count, hand-in, results |
| 8 | **feat: IELTS Listening** | The once-only player (needs an audio package, §3), the 2 minutes to check |
| 9 | **feat: IELTS Speaking** | Practice recording per part with the timers (needs a recording package, §3), upload, record again, hand in; the live examiner screen for staff |
| 10 | **feat: IELTS marking** | Writing (criteria per task, comments, feedback) and Speaking (four criteria, recordings) with the band worked out as on the web |
| 11 | **feat: progress, band report and Writing plagiarism** | Progress per module and question type, the one-page band report (shown, not printed), similarity for Writing |
| 12 | **feat: IELTS questions in the academic builder** | Stage 4's deferred IELTS types where the academic wizard offers them (exam category IELTS), so the Stage 4 read-only rule loosens for those tests |
| 13 | **test: IELTS flows** | Integration tests (staff: build, publish, open, mark; student: take Reading and Writing) on the fake API; the end-of-stage check |

## 3. Packages

Two packages are needed. CLAUDE.md rule 6 asks before adding any; the owner's standing permission covers them, but they're listed here so they can be refused.

| Package | Version | Licence | Why |
| --- | --- | --- | --- |
| `just_audio` | 0.10.6 | MIT / Apache-2.0 | Listening recordings (once-only playback, volume only) and staff playing Speaking recordings. Flutter has no audio player of its own |
| `record` | 7.2.0 | BSD-3-Clause | Speaking: recording the microphone to a file for upload (AAC on Android and iOS; the server allows any audio upload). Needs the microphone permission text in Bangla and English on iOS (`NSMicrophoneUsageDescription`) and `RECORD_AUDIO` on Android |

Each is added in the PR that first needs it (PR 8 and PR 9), with a test that fakes it behind a provider, as files and links already are.

## 4. Tests and checks

- **Each PR:** unit tests for reading and writing every body (question groups, answers, marks, the band rounding rules from `bands.ts`) and widget tests for every screen in both languages, at 360 px and on a tablet, with the plan gate and the IELTS error codes.
- **Beta:** no seeded demo account has an IELTS workspace (checked 21 Nov: demo.owner, demo.teacher1, demo.student1 and demo.solo are all Academic). I'll open a `mobile-api` issue asking for demo IELTS accounts (a centre owner, a teacher, two students, a batch, one published mock and one practice set). Until they exist, beta checks are read-only, and the IELTS mock is never started (owner's rule).
- **iOS:** the microphone and audio work needs a real iPhone check on Jubaer's Mac.

## 5. Backend

- **Needed:** demo IELTS accounts on beta (§4), as a `mobile-api` issue.
- **Not needed:** every endpoint above is on `develop`. Live classes wait for the server work the owner has not started.

## 6. Rough size

About 13 PRs. The builder (PR 5), the test screen (PR 7) and Speaking (PR 9) are the largest.

## 7. Questions for the owner (answered by my recommendation)

1. **Mocks on phones.** The web blocks mocks below 768 px. **Recommendation:** the same in the app: mocks on tablets only, practice sets on phones too.
2. **Rich text.** IELTS passages and tasks are rich text on the web. **Recommendation:** the Stage 4 rule: the app shows them, edits plain text only, and opens a part with formatting read-only with "Edit on the website".
3. **Packages** (§3): `just_audio` and `record`. **Recommendation:** add them in PRs 8 and 9.
4. **Band report.** The web prints it from the browser. **Recommendation:** show it in the app; sharing as a PDF waits for a PDF package (docs/TODO.md).
5. **Live classes.** **Recommendation:** leave them out until the server's live-class work is deployed.
6. **Demo accounts.** **Recommendation:** ask the backend for seeded IELTS demo accounts (§5); until then, check beta read-only.
