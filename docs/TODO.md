# To do later

Each item: what, and why it waits.

- **Turn Android lint's release check back on** (`android/app/build.gradle.kts`, `lint { checkReleaseBuilds = false }`): lint in AGP 9.3.1 crashes (NoSuchMethodError in its Java parser) on url_launcher_android's source. Remove the setting when Flutter's template moves to a fixed AGP and a release build passes with it.
- **iOS-style text menus in Bangla on iOS** are covered by `cupertino_ui`; check them on Jubaer's Mac at the end of Stage 0 (they cannot be seen on Android).
- **The rest of the web's account page** (notification channels, "become a teacher" request, plan and billing summary, level-labels card, profile photo): Stage 0 PR 12 covers the profile, password and devices only; the others come with the stages that need them (billing shows the plan only, per the owner).
