# Stage 4 plan: authoring on tablets

**Status: waiting for the owner's answers to §7** (questions 1 and 2 decide which packages, if any, the stage uses). Written 21 Nov 2026 against tes-taker `develop` `31f14b0` and beta.

Stage 4 ([HANDOVER.md](HANDOVER.md) §4) lets teachers and owners build things on a tablet that today need the website:
- **create and edit a test**: the web's five-step wizard with its question types;
- **the academic setup wizard**: a school's names, session, classes and subjects, and sections.

The IELTS test builder, openings and band tables stay with Stage 5. They come after the backend's P12, as HANDOVER §4 and SCREENS.md say.

I read the web's wizard (`component/Tests/Create`, `lib/features/create-test`), its setup wizard (`component/Academics/setup`) and the backend's exam DTOs. I also called the main GET endpoints on beta as demo.owner; the calls were read-only, and the account was signed out afterwards.

## 1. What the web does

### Create a test (`/tests/create`, `/tests/create?examId=` to edit)

The wizard has five steps, and the test is saved once at the end. There are no drafts on the server.

| Step | What | API |
| --- | --- | --- |
| **Basic info** | Name, category, duration, passing score, model test, negative marking (and how much), proctoring level, the checks that are off, auto-disqualify and alerts (what the plan allows) | `GET /exams/proctoring-options` (beta) |
| **Questions** | One or more subjects (a subject class's subjects, `GET /classes/:id/subjects/assigned`). Each holds questions: **graded** (auto-scored), **ungraded** (marked by hand) or **passage** blocks with child questions. Each question has text, an instruction, points, options, an image, and the answer | Images upload with purpose `EXAM` (the uploader from Stage 1) |
| **Review** | Every question with its problems (no answer, no text, too few options), fixed in place | — |
| **Reorder** | Drag questions within and across subjects; one global order | — |
| **Publish** | Now or at a time, the end, the audience (a class, a subject class or chosen students), excluded students; save | `POST /exams` (`CreateExamWizardDto`: `formState`, `subjects`, `questionOrder`, `publishState`); editing `GET /exams/:id`, `PUT /exams/:id` |

**Question types**, from the backend's `question.enums.ts`:
- **Graded, auto-scored:**
  - choice: multiple choice, multiple response;
  - true/false, true/false/not given, yes/no/not given;
  - completion: fill in the blanks, sentence, summary or table completion;
  - diagram label, short answer, answer box, matching/ordering.
- **Ungraded, marked by hand:** true/false, essay, fill in the gaps.
- **Passage:** a passage (text, an optional image or audio, an instruction in Bangla or English) with child questions of any auto-scored type, or an essay (Bangladesh's creative questions, CQ).

**Plan gates:**
- `allow_passage_questions` turns passage blocks on;
- `allow_question_images` turns question images on;
- `PLAN_LIMIT_REACHED` comes back when the plan's test limit is reached.

**Rich text.** On the web, question text, instructions and passages are written in a rich-text editor: tiptap, with KaTeX and MathLive for maths. The API stores them as HTML. This is the main decision of the stage (§7.1).

### Academic setup wizard (`/organization/setup`)

Five steps. Each one saves as it goes, so it can be left and picked up again.

| Step | What | API |
| --- | --- | --- |
| **Basics** | What the levels are called (Class/Section, Course/Batch, or custom) and the organisation's languages | `GET`/`PATCH /workspace/level-labels`, `PATCH /organizations/:id/settings` (Stage 3) |
| **Session** | The first session and its dates | `/sessions` (Stage 3) |
| **Classes** | Classes and each class's subjects from the catalogue | `GET`/`POST /classes`, `POST /classes/:id/subjects`, `/organizations/:id/subjects` |
| **Sections** | Each class's sections | `/classes/:id/sections` (Stage 3) |
| **Summary** | Per class: subjects, sections, students, subjects without a teacher, a missing check-in pin; Finish | `GET /setup` (beta), `POST /setup/complete` |

## 2. Pull requests, in order

| # | PR | What |
| --- | --- | --- |
| 1 | **feat: setup wizard** | The five steps and Finish, reusing Stage 3's screens and data. The overview's "Open on the website" becomes "Continue setup" |
| 2 | **feat: create a test: basics and publishing** | Steps 1 and 5 with one simple question type, so a whole test can be made and published end to end; the draft kept on the device (§7.4) |
| 3 | **feat: questions: choice and true/false** | Multiple choice and multiple response, the three true/false kinds, points, instruction, image; options added, removed and reordered |
| 4 | **feat: questions: completion, short answer and matching** | Fill in the blanks and the completion types, short answer, answer box, diagram label, matching/ordering |
| 5 | **feat: ungraded questions and passages** | Essay and fill in the gaps; passage blocks with their children (CQ) |
| 6 | **feat: subjects, review and reorder** | Several subjects per test, the review step's problems, drag to reorder (tablet), move up/down (phone) |
| 7 | **feat: edit a test** | Open an existing test in the wizard (`GET`, `PUT /exams/:id`), with the rich-text rule (§7.1) |
| 8 | **test: authoring flows** | Integration tests (set up a school, create and publish a test, edit one) against the fake API; the end-of-stage check on a tablet, a 360 px phone and iOS |

PR 1 is small and useful at once. PRs 2–3 already let a teacher make a multiple-choice test, which is what most use.

## 3. Packages

**None in the plan as written** (§7.1 option A, recommended).
- Drag to reorder uses Flutter's own `ReorderableListView`.
- The draft uses `shared_preferences`, which the app already has.
- Images use Stage 1's uploader.

If the owner picks §7.1 option B, two packages would be needed. I'll confirm each one's version and licence before asking:
- a rich-text editor (for example `flutter_quill`), whose HTML must round-trip with tiptap's;
- a maths renderer (for example `flutter_math_fork`).

## 4. Tests and checks

- **Each PR:** unit tests for building the wizard body and reading it back (every question type, matching the backend's DTO). Also widget tests for every step, both languages, the plan gates, `PLAN_LIMIT_REACHED`, and the web's validation messages.
- **Beta checks** on the emulator as demo.teacher1 and demo.owner. Changes to beta only with the demo accounts:
  - one test made and published to the demo class, then switched off;
  - the setup wizard walked on a demo organisation without finishing it, unless the owner says otherwise (§7.5).

## 5. Backend

Nothing known blocks Stage 4: the wizard DTO and every endpoint above are on beta.

One gap to raise if it matters: the server has no drafts (§7.4). If the owner wants drafts shared with the web, that's a `mobile-api` issue in tes-taker, not an app trick.

## 6. Rough size

About 8 PRs. The question editors (PRs 3–5) and editing a test (PR 7) are the largest; the setup wizard is mostly Stage 3's screens put in order.

## 7. Questions for the owner

1. **Rich text and maths.** The web stores questions as HTML from a rich-text editor with maths, and the app can't edit that faithfully without new packages.
   - **A (recommended to start):** new questions made in the app are plain text, saved as simple HTML paragraphs as homework does. A test with formatting or maths opens in the app read-only, with "Edit on the website". Nothing made on the web is ever damaged. No packages.
   - **B:** add a rich-text editor and a maths renderer, so the app edits everything the web makes. This needs two packages (§3) and more testing.

   My suggestion is A now, and B later if teachers ask for it.
2. **Phones.** The stage is called "on tablets". **Suggestion:** it works on phones too, in one column, and uses two panes (steps beside the question) on tablets.
3. **Left on the web:** importing questions from a file (`allow_question_import_export`), dictating a question by voice, and downloading the question paper. **Suggestion:** keep these on the web.
4. **Drafts.** The web keeps the wizard only in the browser tab. **Suggestion:** the app keeps the unsaved test on the device, so an app restart or a phone call doesn't lose it. It's cleared when the test is saved, and per-workspace, as CLAUDE.md requires.
5. **Beta.** Is it all right to walk the setup wizard on the demo organisation (already set up, so its summary would just show again) and to publish one test to the demo class, then switch it off? **Suggestion:** yes, with the demo accounts only.
