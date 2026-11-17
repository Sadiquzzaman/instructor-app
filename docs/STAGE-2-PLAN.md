# Stage 2 plan: teachers

**Waiting for the owner's approval.** Nothing in this plan is built until the owner answers §7.

Stage 2 ([HANDOVER.md](HANDOVER.md) §4) gives teachers the app they use every day. They can:
- see their day and check in (the student screens already do this for teachers too);
- take attendance for their classes and approve their section's leave;
- set homework, see hand-ins and mark them;
- follow their tests: results, the live monitor, the integrity report, and marking written answers;
- enter paper-exam marks and behaviour (Academic);
- see performance and report cards for their sections (Academic);
- chat with their classes and share resources.

Written 18 Nov 2026 against tes-taker `develop` `31f14b0` and beta. I read the web's teacher pages and the backend's controllers, and called the main teacher endpoints on beta as demo.teacher1 (Rina, Maths in Class 6). The calls were read-only, and the account was signed out afterwards.

## 1. Screens, web pages and API

Each screen copies the web page named here: the same wording, rules and order. Every endpoint is one the web already uses (API guide §8). "Beta" marks the ones I called on 18 Nov; the rest are checked as each PR is built.

| Screen | Web | API |
| --- | --- | --- |
| **Dashboard** | `/dashboard` | `GET /dashboard/teacher` (beta: to mark, live tests, students summary, upcoming tests, classes, top students, a calendar of test days, activity) |
| **Today, My attendance** | `/today`, `/my-attendance` | Built in Stage 1; teachers already get "You teach" and their own check-in. Substitutions and cancellations come with class attendance (PR 2) |
| **Class attendance** | `/attendance` | `GET /attendance/sessions?date` (beta: the day's classes with counts and `can_correct`, `can_cancel`, `can_restore`, `can_change`); `GET /attendance/sessions/:slotId/:date` (the roll); `PUT …/records/:personId` (mark or correct one student); `POST …/cancel`, `…/restore`, `…/change` (cancel a class, take it back, a substitute or room change) |
| **Paper register** | `/attendance-register` | `GET /attendance/register/sections` (beta), `GET /attendance/register/sections/:id?month`; `POST …/preview` and `…/import` take the register as JSON (header and rows), which the web reads from a CSV (§7.3) |
| **Attendance reports** | `/attendance-reports` | `GET /attendance/reports/daily`, `GET /attendance/reports/sections/:id/month` (what a teacher may see; the teachers' report is for owners, Stage 3) |
| **Leave approvals** | `/leave` (Approvals tab) | `GET /attendance/leave/approvals` (beta: empty for demo.teacher1), `GET /attendance/leave/:id`, `POST …/approve`, `POST …/reject` (with a reason) |
| **Classes** | `/classes`, `/classes/details/[slug]`, `/classes/create` | `GET /classes`, `GET /classes/:id`, `GET /classes/:id/students`, approve a student who asked to join (`POST …/students/:studentId/approve`), add or remove students, `GET /classes/:id/subjects`; create a class (personal workspaces, as on the web). Discussions: Stage 1's screen, with a teacher's rights (pin, delete others' posts) |
| **Homework** | `/homework`, `/homework/[id]` | `GET /homework` (beta), `GET /homework/subject-classes`, `POST /homework` and `PATCH /homework/:id` (set or change), `POST …/publish`, `POST …/cancel`; hand-ins `GET …/submissions`, `GET …/submissions/:submissionId`, `GET …/grid`; marking `PUT …/scores`, `POST …/submissions/:id/return`, `POST …/publish-scores`; `POST …/remind-missing` |
| **Plagiarism** | `/homework/[id]/similarity`, `/integrity/matches/[id]` | `GET /integrity/checks/latest`, `POST /integrity/checks`, `GET /integrity/matches/:id`, `PUT …/review`. The two texts side by side on a tablet, one above the other on a phone |
| **Tests** | `/tests`, `/tests/[id]` | `GET /exams` (beta), `GET /exams/:id`, `PATCH /exams/:id/status` (start, stop), `PATCH …/excluded-students`. Creating a test stays on the web until Stage 4 |
| **Test results** | `/tests/[id]/results` | `GET /exams/grading/:examId/roster`, `GET /exams/grading/:examId/submissions/:submissionId` |
| **Live monitor** | `/tests/[id]/monitor` | `GET /exams/:examId/proctoring/sessions` (status, time left, flags), a student's `…/timeline`, `POST …/warn`, `POST …/end`; Socket.IO: a teacher's `exam:join` joins the monitors' room and gets `monitor:state` (the same test connection Stage 1 uses for students) |
| **Integrity report** | `/tests/[id]/integrity` | `GET /exams/:examId/proctoring/integrity`, a student's `…/report`, `POST …/review` |
| **Marking** | `/grading`, `/grading/details/[slug]` | `GET /exams/grading/list` (beta: empty now), `GET /exams/grading/:examId`, `PATCH …/submissions/:submissionId` (marks and comments per written answer), `POST …/publish` |
| **Paper-exam marks** (Academic) | `/marks`, `/marks/[id]` | `GET /offline-exams` (beta), `GET /offline-exams/subject-classes`, create, change or delete one; `GET` and `PUT /offline-exams/:id/marks`; `POST …/publish` |
| **Behaviour** (Academic) | `/behaviour` | `GET /behaviour/criteria`, `GET` and `PUT /behaviour/grid` |
| **Performance** (Academic) | `/performance`, `/performance/students/[id]` | `GET /scores/sections` (beta), `GET /scores/sections/:id`, `GET /scores/students/:id`. Setting the weights is Stage 3 |
| **Report cards** (Academic) | `/report-cards`, `/report-cards/[id]` | Stage 1's screens with the section's cards; printing stays on the web |
| **Calendar, timetable** | `/calendar`, `/routine` | Built in Stage 1 (they already show a teacher's classes) |
| **Chat** | `/chat` | Stage 1's screens with a teacher's rights: post in announcement-only chats, pin, delete others' messages |
| **Resources** | `/resources` | `GET /resources`, `GET /resources/subject-classes`, folders (`GET`, `POST`, `PATCH`, `DELETE /resources/folders`), `POST /resources` (a file with purpose `RESOURCE`, or a link, shared with classes), `PATCH` and `DELETE /resources/:id`, `GET /resources/:id/insights` (who opened it) |

**Not in Stage 2:**
- creating tests (`/tests/create`, Stage 4);
- the owner's settings (homework, performance, plagiarism, grading scale; Stage 3);
- IELTS teacher pages (`/ielts/*`, Stage 5).

## 2. Pull requests, in order

Small PRs into `develop`, one at a time, each merged when CI is green and it has been checked on the emulator against beta. Every PR:
- adds its screen to `AppRoutes.built`;
- replaces the "use the website" message that teachers see on the Stage 1 screens;
- keeps the plan's feature switches and the Academic/IELTS rules;
- covers loading, empty and error states, Bangla and English, Dhaka time, and phones from 360 px to tablets.

| # | PR | What |
| --- | --- | --- |
| 1 | **feat: teacher dashboard** | The dashboard (to mark, live tests, students summary, upcoming tests, classes, top students). For teachers it becomes home, as on the web; Today stays one tap away |
| 2 | **feat: class attendance** | The day's classes with their counts; a class's roll: mark present, late or absent, correct a record (with the trail the server keeps); cancel or restore a class, a substitute or room change. Uses Stage 1's read-only cache for the day's list |
| 3 | **feat: leave approvals** | The Approvals tab: pending requests of my section, approve, or reject with a reason; the person's earlier leave |
| 4 | **feat: attendance reports and the paper register** | The daily and month reports; the paper register (§7.3) |
| 5 | **feat: classes for teachers** | My classes, students (approve, add, remove), subjects, create a class (personal workspace); discussions with a teacher's rights |
| 6 | **feat: homework: set and change** | Set homework (title, instructions §7.1, type, marks, due date, classes or chosen students, files), publish now or later, change, cancel |
| 7 | **feat: homework: hand-ins and marking** | Who handed in and who didn't, each hand-in with its files, marks and comments, return for another try, publish the scores, remind the missing ones |
| 8 | **feat: plagiarism results** | Run a check, the matches, the two texts side by side (tablet) or stacked (phone), mark as reviewed |
| 9 | **feat: tests for teachers** | My tests and their status, start or stop, exclude students, results by student and each answer |
| 10 | **feat: live monitor and integrity** | Who is writing, submitted or lost, time left, flags; a student's timeline, warn, end; the integrity report and review. Live through the test connection (§7.4) |
| 11 | **feat: marking written answers** | Tests waiting to be marked, each written answer with marks and a comment, publish |
| 12 | **feat: paper-exam marks and behaviour** (Academic) | Paper exams (create, enter marks in a grid, publish); the behaviour grid |
| 13 | **feat: performance and report cards for teachers** (Academic) | A section's results and a student's page; the section's report cards |
| 14 | **feat: chat and resources for teachers** | A teacher's rights in chat; resources: upload, add a link, folders, share with classes, archive |
| 15 | **test: teacher flows** | Integration tests (take attendance, approve leave, set and mark homework, mark a test) against the fake API; the end-of-stage check on a 360 px phone, a tablet and iOS |

PRs 1–3 give teachers a useful app on their own; if time is short, they ship first.

## 3. Packages

**None expected.** Grids (marks, behaviour, attendance) and the side-by-side view are our own widgets; files, location and live connections reuse Stage 1's packages. If a PR turns out to need one (for example, reading a CSV file for the paper register, §7.3), I'll ask first with its name, version, licence and reason.

**No new permissions.**

## 4. Tests and checks

- **Each PR:** unit and widget tests against the fake API, for every state, both languages, and the codes the screen can meet (`FEATURE_NOT_IN_PLAN`, `PLAN_LIMIT_REACHED`, `NOT_IN_IELTS`, and that screen's refusals).
- **Beta checks** by hand on the emulator as demo.teacher1, signing out afterwards. Changes to beta only with the test accounts and only what the check needs: marking one test student present, approving a test student's leave, setting one homework for Class 6 and marking demo.student1's hand-in, marking the essay in the Stage 1 test exam (§7.5).
- **Gaps on beta:** demo.teacher1 has nothing to mark, no paper exams and no leave to approve today, so those screens are checked on beta for their empty state unless §7.5 is approved.

## 5. Backend

Nothing known blocks Stage 2: every endpoint above is on beta, and the main lists answered as expected on 18 Nov. If a screen meets a gap, I'll open a `mobile-api` issue in tes-taker instead of working around it. tes-taker#351 (a code for "result not published yet") is low priority and doesn't block anything.

Push (PM-04) would help teachers most: a leave request, a hand-in, a test to mark. Until then the bell polls every minute.

## 6. Rough size

About 15 PRs. Homework (PRs 6–7), the live monitor (PR 10) and the marks grids (PR 12) are the largest; leave approvals and the dashboard are small.

## 7. Decisions needed from the owner

1. **Homework instructions.** The web writes them with a rich-text editor (HTML). I suggest a plain text box in the app, sent as simple paragraphs and lists, which the web shows correctly; changing a homework set on the web keeps its formatting only if it is changed on the web. A rich editor would need a package (later, if wanted). OK?
2. **Teacher home.** Show the dashboard as a teacher's home, as on the web, with Today one tap away? Or keep Today as home for everyone?
3. **Paper register.** The server takes the register as rows the web reads from a CSV file. I suggest the app shows the month's register and lets a teacher fill it in a grid, sending the same rows. The other choice is choosing a CSV file on the phone, as the web does, which may need a CSV package. Grid, file, or both?
4. **Live monitor on phones.** I suggest the full monitor (watch, warn, end) on phones and tablets, with a wider layout on tablets. OK, or tablets only?
5. **Beta data for the checks.** May I, as demo.teacher1, mark one class's attendance, approve a leave request from demo.student1 (who would ask for it), set one homework for Class 6, mark demo.student1's hand-in, and mark the essay in the Stage 1 test exam? Otherwise these are checked against the fake API only.
6. **Classes:** include creating classes and adding or removing students (as the web lets teachers in personal workspaces), or leave changes to classes for the web?
