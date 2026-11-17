# Project notes — the mobile developer's summary

My own summary of what I read on 17 Nov 2026: this repo's `HANDOVER.md`, `CLAUDE.md` and `SCREENS.md`, and tes-taker on `develop` (commit `179517c`): `docs/mobile/api.md`, `api-changelog.md`, `spec.md`, `design.md` §1, §4, §8, `ui/design-system.md`, `frontend/app/tokens.css`, `frontend/utils/sidebarList.tsx`, `frontend/lib/axios.ts`, `authSession.ts`, `workspace.ts`, `frontend/messages/*.json`, `plan.md` (P4, PM, P12) and the beta login and sign-up pages. Updated the same day with the owner's decisions, the backend's answers and PM-01. Where this file and those documents disagree, those documents win.

## The product

Instructor runs schools, coaching centres, IELTS centres and solo teachers in Bangladesh: attendance (self check-in, ZKTeco devices, leave), homework, online tests with proctoring, paper-exam marks, behaviour, performance and report cards, calendar and timetable, chat, resources, plagiarism checks, and an IELTS workspace with band scores. The web app (Next.js) and the API (NestJS) live in tes-taker; the app uses the same REST API and Socket.IO. Guardians have no login; they get SMS and report links.

## Workspace types

- **Academic:** schools, coaching centres, solo tutors. Sessions → classes → sections → subject classes; marks, GPA, report cards. The organisation can rename "Class / Section" (for example Course / Batch) in both languages (`GET /workspace/level-labels`).
- **IELTS:** IELTS centres and (from P12) solo IELTS trainers. Courses instead of sessions and sections, four modules, band scores. **No academic page is ever shown in an IELTS workspace**; guardians and leave are hidden.
- The type is fixed at sign-up. `GET /workspace/type` returns `kind` (SCHOOL, COACHING, IELTS_CENTRE, SOLO) and `workspace_type` (ACADEMIC, IELTS).
- **Every account is an organisation;** a solo teacher has an organisation of one (`kind = SOLO`).

## Roles

Two separate fields, easy to confuse:

| Field | Values | Meaning |
| --- | --- | --- |
| `role` (on the user) | STUDENT, TEACHER, ADMIN, SUPER_ADMIN | Account type. ADMIN and SUPER_ADMIN are **platform** admins (web only). School owners and admins are users with `role = TEACHER` |
| `member_role` (in an organisation) | OWNER, ADMIN, ASSISTANT, TEACHER, STUDENT; BRANCH_MANAGER with P12 | What the person may do in that organisation. A class teacher is a TEACHER who looks after one section |

The web's menu (`sidebarList.tsx`) filters each item by: `role`; `memberRoles` (organisation items); `personalWorkspaceOnly` (items for a teacher's own workspace); `workspaces` (ACADEMIC or IELTS); `feature` (hidden while the plan has it off). The app's menu will follow the same rules from the same data.

## Signing in and workspaces

1. **Sign up:** student or teacher `POST /auth/register` → SMS OTP `POST /auth/register/verify-otp`; organisation `POST /auth/register/organization` → the same OTP. Teachers and organisations then wait for a platform admin's approval (beta's sign-up page says so); an organisation still pending opens on a "pending" page.
2. **Log in:** `POST /auth/login` (or `/auth/login/organization`) with phone or email, password and `device: { platform: "ANDROID" | "IOS", name, app_version }` → user with `access_token` (30 minutes, carries `sid` = this device) and `refresh_token` (30 days). Every login is its own signed-in device, so the app and the web no longer sign each other out (PM-01, on beta 17 Nov).
3. **Choose a workspace:** With exactly one actionable workspace the login answer is already in it; with several, the login answer has `context_type: individual` and no workspace (`requires_context_selection` is always false), and the user picks one. `GET /auth/contexts` lists organisations, the teacher's own workspace (`personal_teacher`) and teachers the student learns from (`individual_teacher`); each has `actionable`. `POST /auth/select-context` returns new tokens for that workspace carrying `organization_id`, `member_role` and `session_mode`. With no workspace the web falls back to a plain "individual" session. Everyone opens on Today.
4. **Every request:** `Authorization: Bearer …`; in an organisation workspace also `X-Organization-Id` (only an id the API gave us). If the header and the token disagree the API answers 403 ("Organization context does not match this session"); personal sessions ignore the header.
5. **401:** refresh once with `POST /auth/refresh {refreshToken, organization_id?, device?}`, from one place in the app, one refresh at a time shared by all waiting requests (as the web's `refreshAuthSession`), then retry; if refresh fails, sign out.
   - **The refresh token rotates** on every refresh and workspace switch: always store the new one and drop the old. A replaced token works for 60 seconds; used after that it counts as stolen and signs the device out.
6. **Switching workspace:** store the new tokens and clear everything cached for the old workspace.
7. **Signing out:** `POST /auth/logout {refreshToken}` (always 200), then delete the tokens. Devices: `GET /auth/sessions`, `DELETE /auth/sessions/:id`, `POST /auth/sessions/revoke-others`. Changing the password signs out the other devices; a reset signs out all of them.
8. **Language at sign-in:** the user's saved `locale` wins, else the organisation's `default_locale`, else the device's choice, which is then saved with `PATCH /user/me/locale`.
9. **Plan:** `GET /me/entitlements` (any signed-in user, students included, once a workspace is chosen; 403 without one) hides what is off; a 403 with `FEATURE_NOT_IN_PLAN` or `PLAN_LIMIT_REACHED` shows the locked-feature message by role (owner/admin: "one upgrade away"; others: "ask your admin"). In the app, no buying and no "buy elsewhere" links (CLAUDE.md).

**Known gaps until the server's PM work ships:** no Google sign-in in the app (PM-02); no version check (PM-03); no push (PM-04); no `openapi.json` (PM-05). PM-01 (devices) is on beta since 17 Nov.

**Check-in** (same endpoint and rules as the web): `GET /attendance/me/today` lists today's classes with their check-in window; `POST /attendance/check-in` takes `latitude`, `longitude` and `accuracy_m` (100 m or better, inside the branch radius) for in-person classes and nothing for online ones. Open from 15 minutes before the start to the end, late after the start plus the grace minutes, once per class. No selfie (dropped on 5 Nov).

## API habits

- Answers: `{ statusCode, message, payload, meta?, error: false }`; lists page with `?page=&limit=` and `meta {page, limit, total, total_pages}`.
- Errors: `{ statusCode, error: true, timestamp, path, message, code?, feature?, limit?, details? }`. Act on `code`, never on `message` (English, for logs). Checked on beta: an unauthenticated `GET /auth/profile` answers exactly this shape. For validation errors `message` is the whole Nest error object (`{ message: [...], error, statusCode }`), and the sign-in endpoints send no `code` (a wrong password is a bare 401); the app handles both (`ApiException`).
- Times are UTC ISO 8601; school days are `YYYY-MM-DD` in the organisation's time zone (default `Asia/Dhaka`); show times in that zone, not the phone's.
- Files: presign → `PUT` → complete → send the file id; show with `GET /files/:id/content` (a 1-hour redirect, never cached).
- Socket.IO with `auth: { token }`; reconnect after a refresh. Chat is on `/chat`, live proctoring on the default namespace. There is no `/notify` socket: the bell polls `GET /me/notifications/unread-count` every minute, as the web does.

## Design and wording

- Tokens (`tokens.css`, generated from `frontend/design/tokens.json`): primary `#49734F`, canvas `#F6F5F1`, ink `#232A25`, status colours with soft backgrounds; type scale 12/14/16/20/24/32; line height 1.5 Latin, 1.7 Bangla; radius 6/10/16; two shadows; motion 150/250 ms. Fonts: Instrument Sans, Hind Siliguri for Bangla. The web has light colours only.
- Wording: `frontend/messages/en.json` and `bn.json`, 73 namespaces and 4,959 strings each, none missing in Bangla. They use ICU `plural` and `select` (Flutter's `gen-l10n` supports them), rich tags such as `<highlight>…</highlight>` (it does not), and level-label tokens such as `[[Classes]]` that the web replaces from the organisation's labels. Bangla shows Bangla digits and 24-hour time in the organisation's time zone.

## Owner's decisions (17 Nov 2026)

| # | Topic | Decision |
| --- | --- | --- |
| 1 | App id | `academy.instructor.app` |
| 2 | Minimum versions | Android 7.0 (API 24) and iOS 13, unless the Flutter or Firebase versions we pick need higher (then use theirs and tell the owner) |
| 3 | Name, icon, splash | "Instructor"; icon and splash from tes-taker `frontend/public/logo.png` for now, final icon later |
| 4 | Theme | Light only for now, built from the tokens by role so dark colours can be added later without touching screens |
| 5 | Offline | A read-only cache only (today's timetable, the last lists seen). No queued check-in (it must happen live at the class time and place) and no offline teacher corrections (plan.md P4-04 is out of date: roll call was dropped on 5 Nov) |
| 6 | IELTS before stage 5 | IELTS members see the shared features as they are built (homework, resources, chat, calendar, attendance, notifications, profile); IELTS-only screens show "Use the web for IELTS for now" |
| 7 | Proctoring | Tests with no or light proctoring in the app; strictly proctored tests say "Use a computer for this test" |
| 8 | Payments | No buying and no "buy elsewhere" links; Billing shows the plan and its limits only |
| 9 | Pull requests | Small PRs into `develop` |

## Questions answered by the backend (17 Nov 2026)

Where `design.md` and the code differ, the code (and `api.md`) is right; `design.md` is older.

1. **Access token:** 30 minutes. design §8.2's 15 minutes was the original plan.
2. **Organisation in the token:** yes, after `select-context` (`organization_id`, `member_role`, `session_mode`); send `X-Organization-Id` as well (see "Signing in" 4).
3. **Proctoring socket:** the default namespace. design §8.4's `/proctoring` was the plan.
4. **Entitlements for students:** any signed-in user once a workspace is chosen. The web calls it only for teachers because only their menus have locked items.
5. **Check-in:** one endpoint and one set of rules for web and app, no selfie (see "Check-in" above). design §1 is out of date.

## Still open

1. **API client "generated from OpenAPI"** (plan P4-01) needs `openapi.json` (PM-05), which does not exist yet: hand-written models per feature until then.
2. **Message conversion:** the web's messages use rich tags (`<highlight>…</highlight>`) and level-label tokens (`[[Classes]]`), and some keys differ only by capitals (`logIn` and `login`). The conversion to ARB has to handle all three; the Stage 0 plan describes how.
