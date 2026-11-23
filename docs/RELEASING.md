# Releasing the app

How a store build is made, and the steps only the owner can do. Nothing here needs a secret in the repository. **This repository is public.**

## 1. Servers: beta now, production later

| Build | Server | How it is chosen |
|---|---|---|
| `flutter run`, tests | beta | the default in `lib/core/config/app_config.dart` |
| Test APKs (GitHub pre-releases from `develop`) | always beta | `--dart-define=APP_ENV=beta` in `android-prerelease.yml` |
| Store builds (`store-release.yml`) | beta until switched | the repository variable `APP_ENV` |

Production addresses: `https://api.instructor.academy/api/v1` and `https://instructor.academy`, as in the backend's docs. They didn't answer yet on 24 Nov 2026.

**To switch store builds to production** (only when the owner says production is live):
1. Check that `https://api.instructor.academy/api/v1` answers, and that a demo account can sign in on the production web.
2. On GitHub, open the repository's **Settings → Secrets and variables → Actions → Variables**. Add `APP_ENV` = `production`.
3. Run **Actions → Store release → Run workflow** on `main`. The run's log prints `Server: production`.

To go back, delete the variable (or set it to `beta`). Any other value also means beta, so a typo never reaches production.

## 2. The Android upload key

Google Play signs the app for phones with its own key ("Play App Signing"). We sign each upload with an **upload key**. If the upload key is lost, Google can reset it, but that takes days. If it leaks, someone could upload as us, though Google would still need our Play account.

The upload key was made on 24 Nov 2026 on the development computer, outside the repository:

```
E:\Instructor-academy\.local-secrets\android-upload-signing\
  instructor-upload.p12     the key (PKCS12, RSA 4096, valid about 27 years)
  keystore-password.txt     its password
  key-password.txt          the same password
  key-alias.txt             instructor-upload
  keystore-base64.txt       the key as text, for the GitHub secret
```

Its certificate's SHA-256 fingerprint is public, not a secret. Play shows it after the first upload, so compare the two:

`86:40:EC:31:13:CE:CC:E7:15:ED:15:FB:3C:FB:07:90:3E:DD:65:47:DC:32:B6:29:E5:06:19:B7:84:44:FD:BB`

**Owner's steps:**
1. **Keep two copies off this computer.** Copy the whole `android-upload-signing` folder to a password manager (as file attachments) or to an encrypted USB drive kept somewhere safe. Never put it in email, chat, Google Drive or the repository.
2. **Add it to GitHub** so `store-release.yml` can sign. Run these in PowerShell, in the `instructor-app` folder, signed in to `gh`:

   ```powershell
   $d = "E:\Instructor-academy\.local-secrets\android-upload-signing"
   Get-Content "$d\keystore-base64.txt" -Raw | gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64
   Get-Content "$d\keystore-password.txt" -Raw | gh secret set ANDROID_UPLOAD_KEYSTORE_PASSWORD
   Get-Content "$d\key-password.txt" -Raw | gh secret set ANDROID_UPLOAD_KEY_PASSWORD
   Get-Content "$d\key-alias.txt" -Raw | gh secret set ANDROID_UPLOAD_KEY_ALIAS
   ```

   Then `gh secret list` should show the four names (never the values).
3. When the Play app is created, turn on **Play App Signing** (the default), and upload the first `.aab` from a Store release run.

The test key in `.local-secrets\android-test-signing` is only for the GitHub test APKs. Never upload it to Play.

## 3. A store build, step by step

1. Merge `develop` into `main` (a pull request; CI must be green).
2. **Actions → Store release → Run workflow** on `main`. The workflow only runs from `main`, the default branch.
3. Download the artifact `instructor-<server>-<code>` from the run. It holds `app-release.aab`.
4. In Play Console, upload it to the **internal testing** track first.

The version name comes from `pubspec.yaml` (`version: 0.1.0+…`). The version code is 10000 plus the run number, so every store build is higher than the last one. Raise the version name in `pubspec.yaml` for each public release.

## 4. iOS

There is no signing on CI yet. It needs the owner's Apple Developer account ($99 a year), which only the owner can create.

Until then, Jubaer builds from his Mac:

```
flutter build ipa --release --dart-define=APP_ENV=beta
```

He opens `build/ios/archive/Runner.xcarchive` in Xcode, then uses **Distribute App → App Store Connect → TestFlight**. Use `APP_ENV=production` once production is live.

## 5. Store material in this repository

| What | Where |
|---|---|
| Listing texts (Bangla and English) | [store/listing.md](store/listing.md) |
| Data safety and App Privacy answers | [store/data-safety.md](store/data-safety.md) |
| Privacy policy (draft, for the owner to approve) | [PRIVACY-DRAFT.md](PRIVACY-DRAFT.md) |
| 512 px Play icon | `store/play-icon-512.png` |
| Screenshots | `store/screenshots/` |
