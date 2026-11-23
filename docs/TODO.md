# To do later

Each item: what, and why it waits.

- **iOS-style text menus in Bangla on iOS** are covered by `cupertino_ui`; check them on Jubaer's Mac at the end of Stage 0 (they cannot be seen on Android).
- **The rest of the web's account page** (notification channels, "become a teacher" request, plan and billing summary, level-labels card, profile photo): Stage 0 PR 12 covers the profile, password and devices only; the others come with the stages that need them (billing shows the plan only, per the owner).
- Rich text: homework instructions (and later resource notes, discussions) come from the web editor as HTML; the app shows them as plain paragraphs and lists (`core/text/html_text.dart`). Bold, links and tables need an HTML renderer package (owner's approval).
- Homework photos: the web combines several photos into one PDF before handing in; the app uploads each photo (up to the homework's file limit). Combining needs a PDF package (owner's approval).
- Class discussions: a teacher-side view (start a conversation with a student) comes with Stage 2. (Editing posts and comments, and deleting comments, are in the app since 24 Nov.)
- Chat: teachers deleting other people's comments inside a post's thread is on the web only; it waits for a second pass on chat after Stage 2.
- Test authoring: tests made with the IELTS category in the academic wizard still open read-only for editing ("Edit on the website"); the IELTS builder is the main way to make IELTS tests.
- Test authoring: passage images and audio, images on matching items, and option reordering are on the web only; a test that has them opens with "Edit on the website" so nothing is lost.
- IELTS Reading: highlighting text in the passage and notes kept on the device (the web has both) are not in the app's test screen yet; the passage is selectable text.
- iOS microphone text: `NSMicrophoneUsageDescription` is in English only; a Bangla `bn.lproj/InfoPlist.strings` needs the Xcode project changed on Jubaer's Mac.
