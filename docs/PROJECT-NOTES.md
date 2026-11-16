# Project notes — the mobile developer's summary

My own summary of what I read on 17 Nov 2026: this repo's `HANDOVER.md`, `CLAUDE.md` and `SCREENS.md`, and tes-taker on `develop` (commit `179517c`): `docs/mobile/api.md`, `api-changelog.md`, `spec.md`, `design.md` §1, §4, §8, `ui/design-system.md`, `frontend/app/tokens.css`, `frontend/utils/sidebarList.tsx`, `frontend/lib/axios.ts`, `authSession.ts`, `workspace.ts`, `frontend/messages/*.json`, `plan.md` (P4, PM, P12) and the beta login and sign-up pages. Where this file and those documents disagree, those documents win; the last section lists what I found unclear.

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
2. **Log in:** `POST /auth/login` with phone or email and password → user with `access_token` (30 minutes) and `refresh_token` (30 days).
3. **Choose a workspace:** `GET /auth/contexts` lists organisations, the teacher's own workspace (`personal_teacher`) and teachers the student learns from (`individual_teacher`); each has `actionable`. `POST /auth/select-context` returns new tokens for that workspace (`session_mode`, `organization`, `member_role`). With no workspace the web falls back to a plain "individual" session. Everyone opens on Today.
4. **Every request:** `Authorization: Bearer …`; in an organisation workspace also `X-Organization-Id` (only an id the API gave us).
5. **401:** refresh once with `POST /auth/refresh {refreshToken, organization_id?}`, one refresh at a time shared by all waiting requests (as the web's `refreshAuthSession`), retry; if refresh fails, sign out.
6. **Switching workspace:** clear everything cached for the old one.
7. **Language at sign-in:** the user's saved `locale` wins, else the organisation's `default_locale`, else the device's choice, which is then saved with `PATCH /user/me/locale`.
8. **Plan:** `GET /me/entitlements` hides what is off; a 403 with `FEATURE_NOT_IN_PLAN` or `PLAN_LIMIT_REACHED` shows the locked-feature message by role (owner/admin: "one upgrade away"; others: "ask your admin"). In the app, no buying and no "buy elsewhere" links (CLAUDE.md).

**Known gaps until the server's PM work ships:** one refresh token per user, so the app and the web log each other out (PM-01; part 1, the table, is merged on `develop` but not on beta or in the changelog yet); no Google sign-in in the app (PM-02); no version check (PM-03); no push (PM-04); no `openapi.json` (PM-05).

## API habits

- Answers: `{ statusCode, message, payload, meta?, error: false }`; lists page with `?page=&limit=` and `meta {page, limit, total, total_pages}`.
- Errors: `{ statusCode, error: true, timestamp, path, message, code?, feature?, limit?, details? }`. Act on `code`, never on `message` (English, for logs). Checked on beta: an unauthenticated `GET /auth/profile` answers exactly this shape.
- Times are UTC ISO 8601; school days are `YYYY-MM-DD` in the organisation's time zone (default `Asia/Dhaka`); show times in that zone, not the phone's.
- Files: presign → `PUT` → complete → send the file id; show with `GET /files/:id/content` (a 1-hour redirect, never cached).
- Socket.IO with `auth: { token }`; reconnect after a refresh.

## Design and wording

- Tokens (`tokens.css`, generated from `frontend/design/tokens.json`): primary `#49734F`, canvas `#F6F5F1`, ink `#232A25`, status colours with soft backgrounds; type scale 12/14/16/20/24/32; line height 1.5 Latin, 1.7 Bangla; radius 6/10/16; two shadows; motion 150/250 ms. Fonts: Instrument Sans, Hind Siliguri for Bangla. Light only today.
- Wording: `frontend/messages/en.json` and `bn.json`, 73 namespaces and 4,959 strings each, none missing in Bangla. They use ICU `plural` and `select` (Flutter's `gen-l10n` supports them), rich tags such as `<highlight>…</highlight>` (it does not), and level-label tokens such as `[[Classes]]` that the web replaces from the organisation's labels. Bangla shows Bangla digits and 24-hour time in the organisation's time zone.

## Unclear or contradicting

1. **Access token lifetime:** api.md §3 says 30 minutes; design §8.2 says 15 minutes for Flutter. The app should not depend on either (refresh on 401), but which is true?
2. **Workspace in the token or in the header?** api.md §3 and the web: `select-context` returns new tokens that carry `organization_id`, and refresh takes `organization_id`. design §8.2: "Organisation is not in the JWT … switching workspace needs no new token." I will follow api.md and the web.
3. **Proctoring socket namespace:** api.md §7 says the default namespace; design §8.4 says `/proctoring`.
4. **Live notifications:** design §8.4 describes a `/notify` socket for the bell, but P2-08 built polling (`GET /me/notifications/unread-count` every minute) and lists the socket in TODO. I will poll like the web until the changelog says otherwise.
5. **API client "generated from OpenAPI"** (plan P4-01) needs `openapi.json`, which is PM-05 and not there yet. Until then: hand-written models per feature.
6. **Dark mode:** HANDOVER §3 asks for light and dark; the design system has no dark values ("can be added later"). Owner to decide: light only first, or a dark palette proposed here and mirrored in the web's tokens.
7. **Offline writes:** plan P4-04 says teacher attendance corrections work offline; HANDOVER §6 suggests no offline writes except perhaps a queued check-in. Owner to decide.
8. **Check-in by location and selfie:** spec FND-17 says it is mobile-only; SCREENS.md and ATT-15/16 put GPS check-in on the web's Today as well. Are the rules the same endpoint for both, and is the selfie (`attendance.selfie`) app-only?
9. **Entitlements for students:** the web loads `/me/entitlements` for teachers only. Does a student's call answer, and should a student's menu hide features the plan lacks?
10. **IELTS users before stage 5:** Bright Path IELTS already has IELTS screens on the web, but the app leaves IELTS out until after P12. What does an IELTS member see in the app meanwhile — a "use the web for now" screen?
11. **Proctored tests on phones** (HANDOVER §6.1) and IELTS mocks ("phones are told to use a computer or tablet", IEL-08) need one consistent rule in the app.
12. **Minimum versions:** HANDOVER suggests Android 7.0 (API 24) and iOS 13; to confirm against what Flutter 3.50 and the packages we pick require (Stage 0 plan).
13. **Message keys that differ only by capitals** (`logIn` and `login`) are valid but must be kept apart when the web's messages are converted to ARB.
