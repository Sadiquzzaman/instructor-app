# Status

Updated in every pull request, so the owner and the backend session can see where the app is.

**Last updated:** 17 Nov 2026

## Current stage

**Before Stage 0:** setup and reading done; the Stage 0 plan is next and waits for the owner's approval before any app code.

## Done

- Development computer set up (Windows 11): Flutter 3.50.0 stable, Dart 3.14.0, Java 17 (Temurin), Android SDK 36 and an Android 16 Pixel 8 emulator; `flutter doctor` green for Flutter and Android; a test app ran on the emulator.
- Read the handover, rules, screen map and the backend's docs; summary and the owner's decisions in [PROJECT-NOTES.md](PROJECT-NOTES.md).
- Read the API changelog up to 17 Nov 2026 (PM-01, signed-in devices).

## In progress

- The Stage 0 plan: packages, folder structure, state and routing, tokens, Bangla/English, theme, CI, and the list of PRs.

## Open `mobile-api` issues

None. Not blocked.

## Waiting on the backend (planned, no issue needed)

| Item | Effect on the app until then |
| --- | --- |
| PM-02 Google sign-in for apps | No "Continue with Google" in the app |
| PM-03 App version check | No forced update |
| PM-04 Push notifications | The bell polls; no push |
| PM-05 `openapi.json` | Models are written by hand |

## Decisions needed from the owner

None right now. The Stage 0 plan will ask for package approvals.
