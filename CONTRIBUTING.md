# Contributing

## Building

```bash
open StarSync.xcodeproj
```

Xcode 27 or later, macOS 27 or later. Set your own team under Signing & Capabilities, then Run.

The app is sandboxed, so it has no standing access to `~/Pictures`. You grant it by choosing your `.lrlibrary` in the open panel; a security-scoped bookmark keeps that across launches.

## Running the tests

All the logic worth testing lives in `StarSyncCore`, which has no PhotoKit dependency:

```bash
cd StarSyncCore
swift test
```

That's 63 tests against a committed fixture, in well under a second. No photo library involved and no permission prompts.

To regenerate the fixture after changing what it needs to cover:

```bash
cd StarSyncCore/Tests/StarSyncCoreTests/Fixtures
python3 make-fixture.py
```

It's standard library only — no pip install.

## CI covers Core, not the app

GitHub's hosted macOS runners don't ship Xcode 27 yet, so the app target can't be built there. `tests.yml` builds and tests `StarSyncCore`; the app is verified locally. When the runners catch up, add an app build step.

## Checking against a real catalog

The fixture proves the reader handles each record shape. It can't prove it handles a real 4,000-photo catalog. There's a small CLI for that:

```bash
cd StarSyncCore
swift run starsync-catalog                              # defaults to ~/Pictures/Lightroom Library.lrlibrary
swift run starsync-catalog /path/to/Your.lrlibrary --albums
```

It prints the photo count, the rating histogram and the album counts. Compare those against what Lightroom itself shows you — filter by each star rating in Lightroom's own grid and check the counts line up. If they don't, the decoder or the query is wrong, and you've found it before anything got written.

This is the one check that would catch Adobe changing the catalog format in an update.

## Before changing the write path

`PhotosWriter` is the only code that modifies anything. Four rules hold it together:

1. **Rating only.** Never add a write for another property.
2. **Record before writing.** The undo log is saved before the first change, so an interrupted run is still reversible.
3. **Preview first.** Nothing writes without the person having seen the plan.
4. **Zero stars never clears.** Unrated in Lightroom means not yet triaged, so it must not wipe a rating set in Photos. There's a test for this in every mode; keep it passing.

Test on a two- or three-photo album before anything larger, and check the Revert button on the way back out.

## Style

- Swift 6 language mode, strict concurrency.
- No third-party dependencies. The MessagePack decoder and the SQLite wrapper are hand-written on purpose — both are small, and neither is worth a supply chain.
- Comments explain *why*, especially where the code works around something undocumented in the Lightroom catalog or in PhotoKit. Those are the parts no one can re-derive by reading the code.
