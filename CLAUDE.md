# Instructor app — rules for Claude Code

These rules apply to every task in this repository. If a rule and a request conflict, stop and ask. Read [docs/HANDOVER.md](docs/HANDOVER.md) first.

## How to work

1. **Read first.** Before proposing anything, read the files involved, `docs/HANDOVER.md`, `docs/SCREENS.md`, and the backend's [API guide](https://github.com/Sadiquzzaman/tes-taker/blob/develop/docs/mobile/api.md).
2. **Show the plan.** Present a short plan (screens, files, packages, API calls, tests) and wait for the owner's approval before changing code.
3. **Ask before deleting** files, branches or data.
4. **No secrets, ever. This repository is public.** Never commit or print keystores, `key.properties`, signing certificates, provisioning profiles, `google-services.json`, `GoogleService-Info.plist`, API keys, tokens, passwords or real phone numbers. Use `*.example` files and GitHub Actions secrets. Test accounts' passwords are not repeated anywhere in this repo.
5. **Match existing code.** Follow the structure, naming and style already in the module you change.
6. **Ask before adding packages** (pub.dev or GitHub Actions). Name the package, version, licence and why it is needed; wait for approval.
7. **One change at a time.** One task, one branch, one pull request.
8. **Write tests** for every behaviour you add or fix (widget or unit tests; integration tests for sign-in and the main flows).
9. **Run `flutter analyze` and `flutter test`** before saying a task is done. CI runs them too.
10. **Do not fake a test pass.** Never skip, delete, weaken or mock away a failing test to make it green. Report it.
11. **Todos for later** go in `docs/TODO.md` with a one-line reason.
12. **Commit every change** with clear messages (`feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`).
13. **Ask when unsure** about requirements, data or design.
14. **Say what changed:** end every task with files changed, how it was tested (Android, iOS), and anything left undone.
15. **Do not flatter or agree by default.** Point out mistakes, risks and better options plainly.

## Branches and releases

16. `main` is the release branch, `develop` is for testing. New work starts from `develop` until the first release, then from `main`: `git checkout -b <type>/<short-task-name> origin/develop`. Types: `feature/`, `task/`, `fix/`, `hotfix/`.
17. Pull requests go into `develop`. **Ask the owner before anything goes to `main`.** Never push directly to `develop` or `main`, never force-push them.

## Project rules

- **One codebase for Android and iOS** (Flutter). Every screen works on both, on phones from 360 px wide and on tablets.
- **The backend is not ours to change.** It lives in [Sadiquzzaman/tes-taker](https://github.com/Sadiquzzaman/tes-taker). When the app needs something the API does not have, or finds a server bug, open an issue there with the label `mobile-api` (see the API guide §10). Never work around a missing endpoint with tricks, scraping the web app, or guessing.
- **Multi-tenancy:** only use organisation ids the API returned; clear cached data when the workspace changes.
- **Feature switches:** hide what `GET /me/entitlements` switches off; handle `FEATURE_NOT_IN_PLAN` and `PLAN_LIMIT_REACHED`.
- **Text:** every user-facing string in Bangla and English (ARB files), using the web's wording where it exists. No hard-coded text in widgets.
- **Design:** use the shared theme built from the web's design tokens; no hard-coded colours or font sizes in widgets.
- **Times:** show times in the organisation's time zone (default `Asia/Dhaka`), not the phone's.
- **Payments:** no buying plans inside the app, and no buttons or links that send people to buy elsewhere, until the owner decides (Apple and Google have rules on selling digital subscriptions in apps). Billing screens show the current plan and its limits only.
