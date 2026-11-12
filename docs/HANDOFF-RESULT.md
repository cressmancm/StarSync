# Hand-off result

Branch **`release-prep`**, cut from `main` at `6628a22`. Nothing pushed, nothing merged, no tags, no release. Worked through on 2026-11-12 from `~/.claude/plans/starsync-handoff.md`.

## Done

**App icon.** `icon/starsync-icon.svg` plus `icon/make-icon.sh`, rendering all ten macOS sizes into `StarSync/Assets.xcassets/AppIcon.appiconset`, with `ASSETCATALOG_COMPILER_APPICON_NAME` set on both configurations. Verified by rendering the built bundle through `NSWorkspace.icon(forFile:)`: macOS applies the squircle, inset and shadow itself, exactly once.

The sources sit in `icon/` rather than `StarSync/` because that folder is a synchronised group — anything inside it compiles into the bundle, and an SVG and a shell script would have shipped inside the `.app`.

**One deviation from the specified palette.** The faint star is `#4f5f7d`, not `#364156`. At `#364156` it measures 1.35:1 against the navy and disappears completely at 16px, which loses the half of the idea that says a rating was left behind. `#4f5f7d` is 2.16:1 — readable at 16px, still 5.4:1 below the solid star, same hue and saturation with lightness at 40%. The hand-off pre-authorised nudging the slate lighter. Five candidates were rendered at 16px and compared before picking.

**README logo.** `docs/logo.svg` redrawn flat to match, gradient retired, `rx="27"` kept.

**Release readiness.** 80 Core tests pass. The fixture content-check passes. The Release configuration builds clean. The catalog oracle reproduces the rating histogram exactly — 4,174 photos, 35/109/237/166/67, 614 rated. Version stays at 1.0, build 1, which is right for a first release. The app launches, stays up, and logs no errors. Release notes drafted at `docs/release-notes-1.0.md`.

## Blocked on Chip

**Screenshots — nothing captured.** Screen Recording was granted later the same day and capture works, but the Mac was locked, so every frame is the login window. Driving the app through its four steps also needs Accessibility, which is not granted — `osascript` gets "not allowed assistive access". `docs/screenshots/README.md` is the shot list: which steps, which appearances, what should be on screen in each, and what is still needed to take them.

There's a second question underneath the permission. The shots show real photographs from the library as thumbnails, the repo is public, and they'd also go on chipcressman.com/starsync. That's a decision to make deliberately, not one to assume.

**The light and dark check was done statically, not visually** — same permission. What a code audit can establish, it does: there is not one literal colour or one `colorScheme` branch anywhere in the app. Every surface uses `.primary`/`.secondary`/`.tertiary`/`.quaternary`, and every brand-coloured element uses `.tint` or `Color.accentColor`. Nothing is hard-coded to blue, so the accent is respected throughout and dark mode can't be wrong by construction. It still wants eyes on it before release.

One thing that audit did turn up, **not** fixed: with the system accent set to orange, the "New rating" badge (accent) and the "Conflict" badge (fixed orange) become the same colour; with it set to red, "New rating" and "Read-only" (fixed red) collide. No information is lost — every badge carries its own text, so colour is reinforcement and never the only channel — and fixing it would mean either restyling or theming, both of which this hand-off rules out. Noted rather than touched.

**Clean-state run-through (RELEASING.md step 3) not done.** It needs `tccutil reset Photos`, which revokes the app's access to the Photos library, and then a human to go through granting access, picking the library, and writing and reverting a sync. Resetting that while Chip is away would leave the app in a state he didn't ask for.

**Everything from RELEASING.md step 4 on** — push, CI, archive, export, notarize, DMG, GitHub release — left alone as instructed.

## Worth knowing

- **There is no app test target.** Only `StarSyncCore` has tests. RELEASING.md step 2 says "run the tests", which today means `swift test` in `StarSyncCore` and nothing else. The app layer — `PhotosWriter`, `UndoLog`, `SyncController` — has no automated coverage at all. Not something to fix during a release, but it's the gap.
- **Album memberships read 4,489, where 2026-11-10 read 4,563.** The photo count and every rating figure are identical, so this is the catalog moving under us as albums get reorganised, not a decoder problem. Worth re-reading rather than treating 4,563 as fixed. CONTRIBUTING.md already says to compare against Lightroom itself rather than a recorded number, which is why nothing there needed changing.
- **The README still says there is no release yet** and points people at building from source. That paragraph comes out when the DMG ships.

## Commits on this branch

```
0ad13c5  Draft the 1.0 release notes
6da512c  Write down which screenshots are still needed
1145f4c  Redraw the README logo to match the icon
218150a  Give StarSync an app icon
```
