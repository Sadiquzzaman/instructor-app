# Stage 3 plan: owners, admins and branch managers

**Status: started on the owner's standing instruction of 19 Nov 2026** ("do not wait for me, go with your recommendations"). The answers in §7 are my recommendations. The owner can change any of them, and the PRs follow the change.

Stage 3 ([HANDOVER.md](HANDOVER.md) §4) gives the people who run a school what they do on the web's Organisation and Settings pages:
- the organisation's details;
- its people (teachers, assistants, students), adding and removing them;
- classes, subjects, and who teaches what;
- sessions and terms;
- attendance settings, branches, holidays and class times;
- homework, performance, plagiarism and grading settings;
- the chat review, the activity log and the message log;
- the plan and its limits (view only).

Written 19 Nov 2026 against tes-taker `develop` `31f14b0` and beta. I read the web's Organisation and Settings pages and the backend's controllers, and called the main GET endpoints on beta as demo.owner. The calls were read-only, and the account was signed out afterwards.

## 1. Screens, web pages and API

Each screen copies the web page named here: the same wording, rules and order. Every endpoint is one the web already uses. "Beta" marks the ones I called on 19 Nov; the rest are checked as each PR is built.

| Screen | Web | API |
| --- | --- | --- |
| **Organisation** | `/organization`, `/organization/pending` | `GET /organizations/mine` (beta), `GET /organizations/:id`, `GET` and `PATCH /organizations/:id/settings`; the pending page explains a school that waits for approval |
| **People** | `/organization/teachers`, `/assistants`, `/students` | `GET /organizations/:id/members`, `GET …/members/lookup` (find a person by phone or email), `POST …/members` (add), `PATCH …/members/:memberId` (role), `DELETE …/members/:memberId`; students into a section with `POST /sections/:id/enrolments`. Importing a list (`…/members/import`) stays on the web (§7.3) |
| **Classes** (Academic) | `/organization/classes` | `GET /classes` (beta), `GET /classes/:classId/sections`, `POST`, `PATCH`, `DELETE` sections |
| **Subjects** | `/organization/subjects` | `GET`, `POST`, `PATCH`, `DELETE /organizations/:id/subjects` |
| **Who teaches what** (Academic) | `/organization/assignments` | `GET /offerings`, `GET /classes/:id/subjects`, `PUT /offerings/:id/teachers`, `GET /organizations/:id/assignable-teachers`, `GET /sections`, `GET /sessions` |
| **Sessions and terms** (Academic) | `/sessions` | `GET /sessions` (beta), `POST`, `PATCH`, `POST …/default`, `…/close`, `…/reopen`; terms `GET`, `POST /sessions/:id/terms`, `PATCH`, `DELETE /terms/:id` |
| **Attendance settings** | `/attendance-settings`, `/attendance-branches` | `GET` (beta) and `PATCH /attendance/settings` (late grace, weekly days off, guardian SMS, repeated absence); branches `GET` (beta), `POST`, `PATCH`, `DELETE /attendance/branches` (the check-in place and radius) |
| **Holidays** | `/holidays` | `GET` (beta), `POST`, `PATCH`, `DELETE /holidays` |
| **Class times** | `/attendance-setup` | `GET /attendance/setup`, `PATCH /attendance/setup/sections/:id`, `PUT …/sections/:id/slots`, `POST /attendance/setup/apply`. The CSV import stays on the web (§7.3) |
| **Homework settings** | `/homework-settings` | `GET` (beta) and `PATCH /homework/settings` |
| **Performance settings** (Academic) | `/performance-settings` | `GET` (beta) and `PATCH /scores/settings`, `GET` and `PUT /scores/weights` |
| **Plagiarism settings** | `/plagiarism-settings` | `GET` (beta) and `PATCH /integrity/settings` |
| **Grading scale** | `/grading-scale` | `GET` (beta), `PUT`, `DELETE /grading-scale` (back to the default) |
| **Chat review** | `/chat-admin` | `GET /chat/admin/chats`, `…/reports` (beta), `…/access-log`; open a chat (`POST …/open`, with a reason, logged), its messages, delete one, mute someone, close a chat, resolve a report |
| **Activity log, message log** | `/activity-log`, `/message-log` | `GET /audit-logs` (beta), `GET /notifications/log` (beta) |
| **Plan and usage** | `/billing` | `GET /me/entitlements` and the subscription; view only (CLAUDE.md: no buying, no links to buy) |
| **Owner reports** | `/attendance-reports`, `/performance` | The parts Stage 2 left for owners: the teachers' attendance report and the whole-school performance view |

## 2. Pull requests, in order

| # | PR | What |
| --- | --- | --- |
| 1 | **feat: organisation overview** | The organisation's details and status (and the pending page); the owners' menu entries open their screens |
| 2 | **feat: people** | Teachers, assistants, students: lists with search, add by phone or email, change role, remove (asked first); a student into a section |
| 3 | **feat: subjects and classes** | Subjects (add, rename, delete); classes and their sections |
| 4 | **feat: who teaches what** | A section's subject classes and their teachers |
| 5 | **feat: sessions and terms** | Add and change sessions, the default, close and reopen (asked first); terms |
| 6 | **feat: attendance settings, branches and holidays** | The settings form; branches with the check-in radius; holidays |
| 7 | **feat: class times** | Each section's weekly slots, apply to the timetable |
| 8 | **feat: homework, performance, plagiarism and grading settings** | Four short forms; weights and the at-risk rules; the grading bands |
| 9 | **feat: chat review** | Chats, reports, the access log; open with a reason, delete, mute, close, resolve |
| 10 | **feat: activity and message logs** | Both logs with their filters |
| 11 | **feat: plan and usage** | The current plan, its limits and what's used; no buying |
| 12 | **feat: owner reports** | The teachers' attendance report; whole-school performance |
| 13 | **test: owner flows** | Integration tests (add a teacher, set who teaches what, change a setting, close a session) against the fake API; the end-of-stage check on a 360 px phone, a tablet and iOS |

PRs 1–2 and 6 are what owners use most; if time is short, they ship first.

## 3. Packages

**None expected.** Everything is lists and forms. Imports from CSV files stay on the web (§7.3), so no file-parsing package is needed.

## 4. Tests and checks

- **Each PR:** unit and widget tests against the fake API, for every state, both languages, the plan codes (`FEATURE_NOT_IN_PLAN`, `PLAN_LIMIT_REACHED`) and that screen's refusals.
- **Beta checks** on the emulator as demo.owner. Changes to beta only with the demo accounts, and every setting I change is set back afterwards (§7.5).

## 5. Backend

Nothing known blocks Stage 3: the GETs above answered on beta. If a screen meets a gap, I'll open a `mobile-api` issue in tes-taker instead of working around it.

## 6. Rough size

About 13 PRs. People (PR 2), who teaches what (PR 4), class times (PR 7) and the chat review (PR 9) are the largest; the settings forms are small.

## 7. Questions, with the answers I'm going with

1. **Home for owners.** The app keeps the current home: the teacher dashboard for staff. The organisation overview is one tap away in the menu, as on the web.
2. **Who sees what.** Menu entries follow the web's menu (member role, workspace type and plan), as they already do; owners and admins get everything here, assistants and branch managers what the web gives them.
3. **Imports from files** (members, students, class times) stay on the web for now. They need a CSV reader (a new package) and are rare, desk-side jobs. Each screen says "use the website" where the web has Import.
4. **Asking first.** Removing a person, deleting a subject, section or branch, closing a session and opening a chat to read it all ask first, with the web's wording.
5. **Beta changes.** Only as demo.owner, only what a check needs, and set back afterwards (a test holiday added and deleted; a setting changed and changed back).
6. **Phones and tablets.** Everything works on a 360 px phone. Wide tables (logs, who teaches what) become cards on phones and tables on tablets.
