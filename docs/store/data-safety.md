# Data safety (Google Play) and App Privacy (App Store) answers

A draft answer sheet, made from what the app's code does on 24 Nov 2026. The owner checks it, then fills in Play Console's "Data safety" form and App Store Connect's "App Privacy". Anything the app can't know (how long the server keeps data, the hosting company) is marked **Owner / backend to confirm**.

## 1. What the app does and does not do

- **No ads, no analytics, no crash reporting** services. The packages are listed in APP-REPORT §7; none of them sends data to a third party.
- **No tracking** across other companies' apps or websites (App Store "Tracking": No).
- Everything goes only to the Instructor server (`api.instructor.academy`; `api-beta…` for tests), over **HTTPS**.
- Sign-in tokens are kept in the phone's secure storage (Android Keystore / iOS Keychain). The password is never stored.
- **Location** is read once, only when the person taps "Check in" for an in-person class. It is never read in the background.
- The **microphone** is used only while an IELTS Speaking answer is being recorded.
- The **camera and photos** are used only when the person chooses to take or pick a photo.
- **Android permissions:** INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, RECORD_AUDIO. The camera and photo picker use the system pickers, so the app needs no camera or storage permission.

## 2. Google Play: data types

For each type: collected, shared, optional or required, and why. "Shared" means sent to another company. The answer is **No** for every type; the school that owns the workspace is the same service, not a third party.

| Play category → type | Collected? | Optional? | Why (Play's purposes) | Notes |
|---|---|---|---|---|
| Personal info → Name | Yes | Required | App functionality, Account management | Shown to the school and classmates/teachers |
| Personal info → Email address | Yes | Required for email sign-in | Account management | Phone or email is used to sign in |
| Personal info → Phone number | Yes | Required for phone sign-in | Account management | |
| Personal info → User IDs | Yes | Required | App functionality, Account management | The account's id |
| Location → Precise location | Yes | Optional (only for check-in) | App functionality | Once per check-in, to confirm the student is at school; not in the background |
| Messages → Other in-app messages | Yes | Optional | App functionality | Class chat and discussions |
| Photos and videos → Photos | Yes | Optional | App functionality | Only photos the person chooses (homework, leave, chat) |
| Audio → Voice or sound recordings | Yes | Optional | App functionality | IELTS Speaking answers |
| Files and docs → Files and docs | Yes | Optional | App functionality | Homework hand-ins and attachments the person chooses |
| App activity → Other user-generated content | Yes | Required for students in a test | App functionality | Test answers, homework text, leave reasons |
| App info and performance → Diagnostics | **No** | | | No crash reporting |
| Device or other IDs | Yes | Required | Account management, Fraud prevention and security | The phone's make and model and the app version, shown in "Your devices" so a person can sign out a lost phone. No advertising id. |

**Security practices (Play):**
- Data is encrypted in transit: **Yes** (HTTPS only).
- You can request that data is deleted: **Yes, once the deletion endpoint exists** ([tes-taker#358](https://github.com/Sadiquzzaman/tes-taker/issues/358)). Play also asks for a web link for deletion. **Don't submit the form until #358 and its web page are live.**
- Independent security review: No.
- Committed to Play Families policy: see §4.

## 3. App Store: App Privacy

"Data linked to you": every type below is linked to the person's account. "Used for tracking": **No** for all.

| Apple category | Types | Purpose |
|---|---|---|
| Contact Info | Name, Email Address, Phone Number | App Functionality |
| Location | Precise Location | App Functionality |
| User Content | Photos or Videos, Audio Data, Other User Content (answers, homework, messages) | App Functionality |
| Identifiers | User ID, Device ID (make and model only) | App Functionality |
| Diagnostics | None | |
| Usage Data | None | |

## 4. Children: owner decision needed

Students in Bangladeshi schools can be under 13. Both stores have extra rules for apps whose audience includes children:
- **Google Play** asks for the target age groups. Choosing ages under 13 brings the Families policy (teacher-approved content, no ads, extra review).
- **Apple:** an app for schools that children use is normally listed in Education, not the Kids category. Apple still expects a privacy policy that covers children's data and parental consent through the school.

**Recommendation:** list the app for ages **13 and over**. Say in the listing and the privacy policy that schools create accounts for younger students and are responsible for parental consent. This is the usual setup for school systems. If the owner wants a "Designed for families" listing, the privacy policy needs a children's section reviewed by a lawyer. **Owner decides.**

## 5. Owner / backend to confirm

- How long the server keeps data after an account is deleted or a school leaves.
- The hosting company and the country where data is stored (for the privacy policy).
- The public support email for both stores.
- Whether the web app uses any analytics (the web privacy page covers both).
