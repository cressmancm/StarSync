# Releasing StarSync

Releases are a signed, notarized `.dmg` attached to a GitHub release. Only the maintainer can make one.

## Once

- **Developer ID Application certificate** in your keychain, from your Apple Developer account. This is the certificate for distributing outside the App Store — not the Apple Development one Xcode uses to run builds locally.
- **A notarytool credential profile**, so notarization doesn't prompt every time:

  ```bash
  xcrun notarytool store-credentials StarSync-Notary --apple-id <your-apple-id> --team-id <your-team-id>
  ```

  It asks for an app-specific password, which you make at [appleid.apple.com](https://appleid.apple.com) under App-Specific Passwords. Don't use your account password.

  Your team ID is on the [Membership page](https://developer.apple.com/account) of your Apple Developer account, and `security find-identity -v -p codesigning` prints it alongside the certificate names you can sign with.

- **Signing** is automatic, with the team set on the StarSync target. For the release build, Xcode picks the Developer ID certificate when you export for Developer ID distribution.

## Each release

1. **Bump the version** on the StarSync target's General tab: Version (`MARKETING_VERSION`, like `1.1`) and Build (`CURRENT_PROJECT_VERSION`, one more than last time).

2. **Run the tests** and check the reader against your real catalog:

   ```bash
   cd StarSyncCore && swift test && swift run starsync-catalog
   ```

   The histogram should match what Lightroom shows for each star rating.

3. **Try it from a clean state.** Delete `~/Library/Application Support/StarSync`, reset the Photos permission with `tccutil reset Photos com.chipcressman.starsync`, then run the app and go through the whole thing: granting access, picking the library, one album in Review conflicts, writing a few ratings, checking them in Photos' Info panel, and Revert.

4. **Commit** as `StarSync <version>`, push, and wait for CI.

5. **Archive:** Product › Archive, with My Mac as the destination.

6. **Export:** in the Organizer, Distribute App › Direct Distribution. Xcode signs with your Developer ID and notarizes it. Wait for it to come back approved, then export the `.app`.

   To do it by hand instead:

   ```bash
   xcrun notarytool submit StarSync.zip --keychain-profile StarSync-Notary --wait
   xcrun stapler staple StarSync.app
   ```

7. **Build the DMG:**

   ```bash
   mkdir -p dmg && cp -R StarSync.app dmg/
   ln -s /Applications dmg/Applications
   hdiutil create -volname StarSync -srcfolder dmg -ov -format UDZO StarSync-<version>.dmg
   rm -rf dmg
   ```

8. **Sign and notarize the DMG too**, so Gatekeeper is happy with the thing people actually download:

   ```bash
   codesign --sign "Developer ID Application: <your name> (<your-team-id>)" --timestamp StarSync-<version>.dmg
   xcrun notarytool submit StarSync-<version>.dmg --keychain-profile StarSync-Notary --wait
   xcrun stapler staple StarSync-<version>.dmg
   ```

9. **Check it the way a stranger would:**

   ```bash
   spctl -a -vvv -t install StarSync-<version>.dmg
   ```

   It should say `accepted` and `source=Notarized Developer ID`. Best of all, test it from another user account on the Mac — that catches anything that only works because your own keychain is unlocked.

10. **Tag and publish:**

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
