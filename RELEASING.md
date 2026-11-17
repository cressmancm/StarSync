# Releasing StarSync

StarSync ships two ways: through the **Mac App Store**, and as a signed, notarized `.dmg` attached to a GitHub release. Both start from the same archive, and only the maintainer can make either.

## Once, for the App Store

- **An app record in App Store Connect.** Apps › + › New App: platform macOS, name StarSync, bundle ID `com.chipcressman.starsync` (register it under Certificates, IDs & Profiles first if it isn't offered), SKU `starsync`. If the name is taken, [`docs/app-store/listing.md`](docs/app-store/listing.md) has a fallback.
- **The listing**, copied from [`docs/app-store/listing.md`](docs/app-store/listing.md) — every field App Store Connect asks for, in the order it asks. Run `docs/app-store/check-listing.sh` after editing it; it counts the fields that have limits.
- **The privacy policy, published** at `https://chipcressman.com/starsync/privacy`, from [`docs/app-store/privacy-policy.md`](docs/app-store/privacy-policy.md). App Store Connect won't accept a submission until that URL loads, and the support URL has to load too.
- **Certificates.** Distributing to the App Store needs an Apple Distribution certificate and a Mac Installer Distribution certificate. With automatic signing, Xcode offers to create both the first time you upload.

## Once, for direct download

- **Developer ID Application certificate** in your keychain, from your Apple Developer account. This is the certificate for distributing outside the App Store — not the Apple Development one Xcode uses to run builds locally.
- **A notarytool credential profile**, so notarization doesn't prompt every time:

  ```bash
  xcrun notarytool store-credentials StarSync-Notary --apple-id <your-apple-id> --team-id <your-team-id>
  ```

  It asks for an app-specific password, which you make at [appleid.apple.com](https://appleid.apple.com) under App-Specific Passwords. Don't use your account password.

  Your team ID is on the [Membership page](https://developer.apple.com/account) of your Apple Developer account, and `security find-identity -v -p codesigning` prints it alongside the certificate names you can sign with.

- **Signing** is automatic, with the team set in `Signing.local.xcconfig` — copy it from `Signing.local.xcconfig.example`; git ignores it, so no team ID is in the repository. For the release build, Xcode picks the Developer ID certificate when you export for Developer ID distribution.

## Each release

1. **Bump the version** on the StarSync target's General tab: Version (`MARKETING_VERSION`, like `1.1`) and Build (`CURRENT_PROJECT_VERSION`, one more than last time).

2. **Run the tests** and check the reader against your real catalog:

   ```bash
   cd StarSyncCore && swift test && swift run starsync-catalog
   ```

   The histogram should match what Lightroom shows for each star rating.

3. **Try it from a clean state.** Quit the app, delete `~/Library/Containers/com.chipcressman.starsync` — StarSync is sandboxed, so its undo log and its saved library bookmark both live in there, never in `~/Library/Application Support` — reset the Photos permission with `tccutil reset Photos com.chipcressman.starsync`, then run the app and go through the whole thing: granting access, picking the library, one album in Review conflicts, writing a few ratings, checking them in Photos' Info panel, and Revert.

4. **Commit** as `StarSync <version>`, push, and wait for CI.

5. **Archive:** Product › Archive, with My Mac as the destination.

Then one or both of the next two sections.

### To the App Store

1. **Rebuild what the store shows, if it changed.** If any of `docs/screenshots` was retaken, regenerate the store set; if the reader or the catalog format changed, rebuild the review kit and try it:

   ```bash
   swift docs/app-store/make-screenshots.swift
   swift docs/app-store/review-kit/make-review-kit.swift
   ```

2. **Upload:** in the Organizer, Distribute App › App Store Connect › Upload. Xcode re-signs with your Apple Distribution certificate. Every upload needs a build number it hasn't seen — including one for a build that was rejected — so bump `CURRENT_PROJECT_VERSION` before trying again.

3. **Wait for processing.** App Store Connect emails when the build is ready, usually within the hour. If it emails a problem instead, it's most often the privacy manifest: `StarSync/PrivacyInfo.xcprivacy` has to declare every required-reason API the app calls, with a reason. A new `UserDefaults`, file-date or disk-space call needs a line there.

4. **Submit:** on the version page, choose the build, fill in What's New (not on 1.0), and under App Review Information attach `build/StarSync Review Kit.zip` and paste the notes from `listing.md`. Then Add for Review.

   Review won't have Lightroom. Without the kit, StarSync stops at its first screen for them, and that comes back as a guideline 2.1 rejection.

5. **When it's approved,** tag it as in step 5 of the next section, whether or not there's a `.dmg` to go with it.

### As a direct download

1. **Export:** in the Organizer, Distribute App › Direct Distribution. Xcode signs with your Developer ID and notarizes it. Wait for it to come back approved, then export the `.app`.

   To do it by hand instead:

   ```bash
   xcrun notarytool submit StarSync.zip --keychain-profile StarSync-Notary --wait
   xcrun stapler staple StarSync.app
   ```

2. **Build the DMG:**

   ```bash
   mkdir -p dmg && cp -R StarSync.app dmg/
   ln -s /Applications dmg/Applications
   hdiutil create -volname StarSync -srcfolder dmg -ov -format UDZO StarSync-<version>.dmg
   rm -rf dmg
   ```

3. **Sign and notarize the DMG too**, so Gatekeeper is happy with the thing people actually download:

   ```bash
   codesign --sign "Developer ID Application: <your name> (<your-team-id>)" --timestamp StarSync-<version>.dmg
   xcrun notarytool submit StarSync-<version>.dmg --keychain-profile StarSync-Notary --wait
   xcrun stapler staple StarSync-<version>.dmg
   ```

4. **Check it the way a stranger would:**

   ```bash
   spctl -a -vvv -t install StarSync-<version>.dmg
   ```

   It should say `accepted` and `source=Notarized Developer ID`. Best of all, test it from another user account on the Mac — that catches anything that only works because your own keychain is unlocked.

5. **Tag and publish:**

   ```bash
   git tag -a v<version> -m "StarSync <version>"
   git push origin v<version>
   ```

   Then create the GitHub release from the tag and attach the `.dmg`.

## If notarization is rejected

```bash
xcrun notarytool log <submission-id> --keychain-profile StarSync-Notary
```

The usual causes are a missing Hardened Runtime (it's on in the project; don't turn it off) or an unsigned nested binary. The `StarSyncCore` package is statically linked into the app, so there shouldn't be one.
