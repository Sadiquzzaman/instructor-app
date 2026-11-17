# Status

Updated in every pull request, so the owner and the backend session can see where the app is.

**Last updated:** 17 Nov 2026

## Current stage

**Stage 0:** the plan ([STAGE-0-PLAN.md](STAGE-0-PLAN.md)) is approved; the first PR (Flutter project and CI) is next.

## Done

- Development computer set up (Windows 11): Flutter 3.50.0 stable, Dart 3.14.0, Java 17 (Temurin), Android SDK 36 and an Android 16 Pixel 8 emulator; `flutter doctor` green for Flutter and Android; a test app ran on the emulator.
- Read the handover, rules, screen map and the backend's docs; summary and the owner's decisions in [PROJECT-NOTES.md](PROJECT-NOTES.md).
- Read the API changelog up to 17 Nov 2026: PM-01 (devices), PM-03 (version check), PM-05 (openapi.json), IELTS courses and branch managers (P12-01 to P12-05).
- Looked at beta through the API, read-only, as a student, teacher, owner, IELTS student, IELTS owner and solo teacher.
- Wrote the Stage 0 plan.

## In progress

- PR 1: the Flutter project, lints, folder skeleton, `ci.yml` and `ios-build.yml`.

## Open `mobile-api` issues

None. Not blocked.

## Waiting on the backend (planned, no issue needed)

| Item | Effect on the app until then |
| --- | --- |
| PM-02 Google sign-in for apps | No "Continue with Google" in the app |
| PM-04 Push notifications | The bell polls; no push |

Live classes are postponed by the owner and left out of every stage.

## Decisions needed from the owner

Who creates the Android test signing key (STAGE-0-PLAN.md §12.3); needed before PR 2.
