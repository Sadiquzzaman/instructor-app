# Screens — what to build, mapped to the web

Every screen of the web app, grouped by stage ([HANDOVER.md](HANDOVER.md) §4). The web route is the working example: its page is `frontend/app/<route>/page.tsx` and its components are in `frontend/component/` in [tes-taker](https://github.com/Sadiquzzaman/tes-taker). Which role sees each page is in `frontend/utils/sidebarList.tsx`; the app follows the same rules, plus the plan's switches (`GET /me/entitlements`) and the workspace type (Academic or IELTS).

The routes reflect the web on 16 Nov 2026. When the backend adds screens (for example P12's courses and live classes), they appear here in a later update.

## Stage 0 — everyone

| Screen | Web route | Notes |
| --- | --- | --- |
| Log in (phone or email, password) | `/login` | Organisation login is `POST /auth/login/organization` |
| Sign up, OTP | `/signup`, `/signup/organization` | Student, teacher or organisation; Academic or IELTS for organisations |
| Forgot password | `/forgot-password` | OTP, then a new password |
| Choose a workspace | `/select-context` | Also a switcher from the menu |
| Join a class or test by link or code | `/join/class/[classId]`, `/join/test/[testId]` | Open these links in the app too (deep links), later |
| Notifications inbox | the bell in the header | `GET` inbox with `meta.unread` |
| Account and profile | `/account` | Name, photo, language, password |
| Locked features | `/features` | What the plan lacks, "Request this feature" |

## Stage 1 — students

| Screen | Web route | Notes |
| --- | --- | --- |
| Today | `/today` | Today's classes, check-in, what's due |
| Check-in | from Today | Branch radius by GPS for in-person classes; online classes from anywhere (spec ATT-15, ATT-16) |
| My attendance | `/my-attendance` | Calendar and totals |
| Leave requests | `/leave` | Ask for leave with an optional file (purpose `LEAVE`) |
| Classes | `/classes`, `/classes/details/[slug]` | My classes, subjects, discussions |
| Homework | `/homework`, `/homework/[id]` | See, hand in (text, photos, files), see the score |
| Tests | `/tests`, `/test` | Take a test; proctoring decision in HANDOVER §6 |
| Results | `/marks`, `/marks/[id]`, `/performance`, `/report-cards` | Marks, performance, report cards (Academic only) |
| Calendar and timetable | `/calendar`, `/routine` | Events, holidays, the weekly timetable |
| Chat | `/chat` | Class groups with post threads, private chat with teachers (Socket.IO `/chat`) |
| Resources | `/resources` | Files and links shared with the class |
| Learning | `/learning` | Syllabus progress |

## Stage 2 — teachers

| Screen | Web route | Notes |
| --- | --- | --- |
| Dashboard | `/dashboard` | |
| Today | `/today` | Their classes, substitutions, cancellations |
| Classes | `/classes`, `/classes/details/[slug]`, `/classes/create` | Sections, students, subject classes |
| Attendance | `/attendance`, `/attendance-register`, `/attendance-reports` | Class attendance, paper register upload, reports |
| Leave approvals | `/leave` | Class teachers approve their section's leave |
| Homework | `/homework`, `/homework/[id]` | Create, see hand-ins, mark |
| Tests | `/tests`, `/tests/[id]`, `/tests/[id]/results`, `/tests/[id]/monitor`, `/tests/[id]/integrity` | List, results, live monitor, integrity report; creating is stage 4 |
| Grading | `/grading`, `/grading/details/[slug]` | Mark written answers |
| Marks and behaviour | `/marks`, `/behaviour` | Academic only |
| Performance and report cards | `/performance`, `/performance/students/[id]`, `/report-cards`, `/report-cards/[id]` | Academic only; printing stays on the web |
| Plagiarism results | `/homework/[id]/similarity`, `/integrity/matches/[id]` | Side-by-side view needs a tablet layout |
| Calendar, timetable | `/calendar`, `/routine` | |
| Chat, resources | `/chat`, `/resources` | |
| My attendance (teachers) | `/my-attendance` | Teachers check in too |

## Stage 3 — owners, admins, assistants, branch managers

| Screen | Web route | Notes |
| --- | --- | --- |
| Organisation overview | `/organization` | |
| Teachers, assistants, students | `/organization/teachers`, `/organization/assistants`, `/organization/students`, `/organization/pending` | Invitations and approvals |
| Classes, subjects, assignments | `/organization/classes`, `/organization/subjects`, `/organization/assignments` | Academic only |
| Sessions | `/sessions` | Academic only |
| Attendance setup and settings | `/attendance-setup`, `/attendance-settings`, `/attendance-branches`, `/holidays` | Branches move to Organisation → Branches with P12 |
| Homework, performance, plagiarism settings | `/homework-settings`, `/performance-settings`, `/plagiarism-settings`, `/grading-scale` | |
| Chat admin | `/chat-admin` | Reports, mutes, access log |
| Activity and message logs | `/activity-log`, `/message-log` | |
| Plan and billing | `/billing` | View only in the app (HANDOVER §6) |

## Stage 4 — authoring on tablets

| Screen | Web route | Notes |
| --- | --- | --- |
| Create a test | `/tests/create` | The wizard with every question type |
| Academic setup wizard | `/organization/setup` | |
| IELTS test builder, openings, band tables | `/ielts/tests`, `/ielts/tests/[id]`, `/ielts/tests/[id]/openings`, `/ielts/band-tables` | With stage 5 |

## Stage 5 — IELTS (after the backend's P12)

| Screen | Web route | Notes |
| --- | --- | --- |
| IELTS overview | `/ielts/overview` | Staff and students |
| IELTS students and profiles | `/ielts/students`, `/ielts/me` | |
| My IELTS tests and the test screen | `/ielts/my`, `/ielts/attempts/[id]` | Mocks need a tablet or computer (spec IEL-08) |
| Marking, Speaking examiner | `/ielts/marking`, `/ielts/marking/[attemptId]`, `/ielts/speaking/[attemptId]` | Recording with the microphone |
| Progress and band report | `/ielts/progress`, `/ielts/progress/[studentId]`, `/ielts/report/[assignmentId]/[studentId]` | |
| Plagiarism for IELTS Writing | `/ielts/assignments/[id]/similarity` | |
| Courses, live classes, recordings | (P12, not built yet) | Spec IEL-13–15 |

## Web only

`/admin/*` (platform admin), `/report-cards/print`, `/dev/ui`, payment result pages (`/payment/*`), the public report link `/r/[token]`.
