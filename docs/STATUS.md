# Status

Updated in every pull request, so the owner and the backend session can see where the app is.

**Last updated:** 17 Nov 2026

## Current stage

**Before Stage 0:** the Stage 0 plan ([STAGE-0-PLAN.md](STAGE-0-PLAN.md)) waits for the owner's approval; no app code yet.

## Done

- Development computer set up (Windows 11): Flutter 3.50.0 stable, Dart 3.14.0, Java 17 (Temurin), Android SDK 36 and an Android 16 Pixel 8 emulator; `flutter doctor` green for Flutter and Android; a test app ran on the emulator.
- Read the handover, rules, screen map and the backend's docs; summary and the owner's decisions in [PROJECT-NOTES.md](PROJECT-NOTES.md).
- Read the API changelog up to 17 Nov 2026: PM-01 (devices), PM-03 (version check), PM-05 (openapi.json), IELTS courses and branch managers (P12-01 to P12-05).
- Looked at beta through the API, read-only, as a student, teacher, owner, IELTS student, IELTS owner and solo teacher.
- Wrote the Stage 0 plan.

## In progress

- Nothing until the plan is approved.

## Open `mobile-api` issues

None. Not blocked.

## Waiting on the backend (planned, no issue needed)

| Item | Effect on the app until then |
| --- | --- |
| PM-02 Google sign-in for apps | No "Continue with Google" in the app |
| PM-04 Push notifications | The bell polls; no push |

Live classes are postponed by the owner and left out of every stage.

## Decisions needed from the owner

See [STAGE-0-PLAN.md](STAGE-0-PLAN.md) §12: packages and actions, iOS 15 minimum, the Android test signing key, integration tests against beta, and this plan as a PR.
