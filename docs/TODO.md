# To do later

Each item: what, and why it waits.

- **Turn Android lint's release check back on** (`android/app/build.gradle.kts`, `lint { checkReleaseBuilds = false }`): lint in AGP 9.3.1 crashes (NoSuchMethodError in its Java parser) on url_launcher_android's source. Remove the setting when Flutter's template moves to a fixed AGP and a release build passes with it.
- **iOS-style text menus in Bangla on iOS** are covered by `cupertino_ui`; check them on Jubaer's Mac at the end of Stage 0 (they cannot be seen on Android).
- **The rest of the web's account page** (notification channels, "become a teacher" request, plan and billing summary, level-labels card, profile photo): Stage 0 PR 12 covers the profile, password and devices only; the others come with the stages that need them (billing shows the plan only, per the owner).
- Rich text: homework instructions (and later resource notes, discussions) come from the web editor as HTML; the app shows them as plain paragraphs and lists (`core/text/html_text.dart`). Bold, links and tables need an HTML renderer package (owner's approval).
- Homework photos: the web combines several photos into one PDF before handing in; the app uploads each photo (up to the homework's file limit). Combining needs a PDF package (owner's approval).
- Class discussions: editing a post or deleting a comment (the web has both) is not in the app yet; a teacher-side view (start a conversation with a student) comes with Stage 2.
- Chat: teachers deleting other people's comments inside a post's thread is on the web only; it waits for a second pass on chat after Stage 2.
