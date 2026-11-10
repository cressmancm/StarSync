# Architecture

StarSync is two pieces: a pure-Swift package that does the thinking, and a thin SwiftUI app that talks to Apple Photos.

```
StarSyncCore (no PhotoKit)          StarSync (the app)
┌──────────────────────┐            ┌──────────────────────┐
│ MessagePack          │            │ PhotosLibrary  (read)│
│ CatalogReader        │            │ PhotosWriter  (write)│
│ Matcher              │            │ UndoLog              │
│ SyncPlan             │            │ CatalogBookmark      │
│ Models               │            │ SyncController       │
└──────────────────────┘            │ Views/               │
                                    └──────────────────────┘
```

Flow: `CatalogReader` and `PhotosLibrary` each produce plain structs → `Matcher` pairs them → `SyncPlanner` turns the pairs into a plan → the person reviews it → `PhotosWriter` applies it.

## Why Core is a separate package

Two reasons, and the second is the one that mattered.

**It makes the logic testable.** The MessagePack decoder, the catalog reader, the matcher and the plan rules have nothing to do with Photos. As their own package they can be tested against a committed fixture, with no photo library and no permission prompts. That's 63 tests that run in a hundredth of a second.

**It makes CI possible at all.** The app needs the macOS 27 SDK for `PHAsset.rating`, and GitHub's hosted runners don't ship Xcode 27 yet, so the app target can't be built in CI. Core targets macOS 14 and builds anywhere, so the interesting half is covered from day one. The app is verified locally until the runners catch up.

The app converts `PHAsset` into `StarSyncCore.PhotoAsset` at the boundary. Core never imports Photos.

## Reading the Lightroom catalog

Lightroom CC keeps its catalog at `Lightroom Library.lrlibrary/<uuid>/Managed Catalog.mcat`. It's SQLite, but not a schema you can read with SQL alone: there are three tables (`docs`, `revs`, `labels`) holding a document store, and every record is a **MessagePack** blob in `revs.content`.

So `CatalogReader` runs one query —

```sql
SELECT d.fullDocId, d.type, d.subtype, r.content
FROM docs d JOIN revs r ON r.sequence = d.winningRevSequence
WHERE d.deleted = 0 AND d.type IN ('asset', 'album', 'album_asset')
```

— and decodes each blob itself. `MessagePack.swift` is about 250 lines and covers every type tag the format defines; there's no dependency.

Things worth knowing if you touch this code:

- **`content` must be read as a blob.** It isn't valid UTF-8. Reading it as text mangles the record or throws.
- **Follow `winningRevSequence`.** Records accumulate revisions; the winning one is the current state.
- **The catalog is copied before it's opened.** Lightroom may be running and holding the write-ahead log, and a read-only SQLite handle can't create the shared-memory file it would need to see those pages. Copying the `.mcat` and its `-wal`/`-shm` sidecars to a temp directory sidesteps that entirely, and guarantees StarSync can't disturb a live catalog. It's about 430 MB and takes a couple of seconds.
- **`develop` is skipped while decoding.** It carries kilobytes of Camera Raw XMP per photo that nothing here needs. `decodeMap(skippingKeys:)` steps over it without building it.
- **Nothing is hardcoded.** The catalog folder is named with a per-install UUID, and ratings are keyed by Lightroom account id. Both are discovered.

Where the fields live:

| What | Path in the record |
|---|---|
| Star rating | `ratings.<accountId>.rating` (0–5) |
| Pick / reject | `reviews.<accountId>.flag` |
| Original filename | `importSource.fileName` |
| Capture time | `captureDate` (local wall clock, no zone) |
| Checksum | `importSource.sha256` |
| Album name / parent | `name`, `parent.id` |
| Album membership | `album.id` + `asset.id` on an `album_asset` doc |

Only `asset`/`image` records are photos. `person`, `preset`, `stack`, `task`, `video` and `deleted_image` all share the `asset` type and are filtered out.

## Reading and writing Apple Photos

macOS 27 added `PHAsset.rating` (read) and `PHAssetChangeRequest.rating` (write). **AppleScript still has no rating property** — Photos' scripting dictionary exposes `favorite` and nothing else — so tools built on AppleScript, osxphotos included, can't do this. PhotoKit is the only route, which is why StarSync is a native app rather than a script.

Two details carry their weight:

- **`PHFetchOptions.prefetchAssetExtendedMetadata`** loads every original filename in one pass. `extendedMetadata.originalFilename` is also new in macOS 27; without the prefetch, PhotoKit fetches them one asset at a time and a large library takes minutes instead of seconds. Assets that come back with no extended metadata fall back to the resource list.
- **`canPerform(.properties)`** says in advance whether a write will be allowed. Assets from a shared library aren't, and those are reported rather than queued up to fail.

Writes go through `PHPhotoLibrary.performChanges` in batches of 200. If a batch is rejected, StarSync retries that batch one asset at a time, so a single unwritable photo costs itself and not the other 199.

## Matching

Lightroom exports keep the camera filename, so the lowercased stem (`dscf4087`) is the key. When one stem has several candidates:

1. **Capture time.** Lightroom stores local wall-clock with no zone; Photos stores an absolute instant. The Lightroom string is read in the current zone, compared within 2 seconds, then within an hour to absorb a zone or daylight-saving shift.
2. **Pixel dimensions**, allowing for a 90° rotation.
3. **Still unsure → ambiguous**, reported and skipped. Virtual copies land here, and a wrong guess would put someone's rating on the wrong picture.

Derived files (`DSCF3438-Edit.tiff`) are indexed under both their full stem and their base, so an edit on either side still finds its counterpart. Trailing counters are only stripped when they're short, so `DSCF4087` keeps its number.

## Safety

The rules the design holds to, in order of how much they matter:

1. The Lightroom catalog is read-only, from a copy.
2. The rating is the only field ever written.
3. Nothing is written before the person has seen the plan.
4. Every run is recorded to `~/Library/Application Support/StarSync/runs/` **before** the first write, so an interrupted run is still reversible.
5. A photo unrated in Lightroom never clears a rating in Photos.
6. Every row is rechecked against the live rating in Photos immediately before it's written.

### Why rule 6 exists

A plan is built from a snapshot, and Photos keeps changing afterwards — someone can rate a photo in Photos.app while the preview is on screen, or while a long run is still writing. Acting on the snapshot alone meant two things could go wrong:

- **A mode could break its own promise.** "Add only" means *write where Photos has no rating*. If the snapshot said unrated and Photos had since been rated, the write landed on top of it.
- **The undo log recorded the wrong value.** `oldRating` came from the snapshot, so reverting restored the stale rating rather than the one that was actually overwritten — the edit was unrecoverable through the one button meant to recover it.

So `PhotosWriter` reads each asset's current rating immediately before writing it and calls `SyncPlanner.recheck`. If Photos still holds what the preview showed, the row is written. If not, the decision is made again: `lightroomWins` still writes (a newer differing rating is still a differing rating), `addOnly` and `reviewConflicts` leave it alone and report it, and a rating the person set by hand is always honoured — they said what they wanted, and the comparison they were shown going stale doesn't withdraw the instruction. `oldRating` is always the live value, so a revert puts back what was really there.

Two cheaper layers sit in front of it: `buildPlan` re-reads the ratings of just the matched photos before deciding anything, and `PhotosChangeWatcher` sets a flag so a stale preview says so and offers to rebuild. Neither can close the window on its own — the preview can go stale the instant after it's drawn, and a run can take minutes — which is why the write-time check is the one that counts.

## The test fixture

The real catalog is 430 MB of personal photographs, so CI gets `Tests/StarSyncCoreTests/Fixtures/tiny.mcat` instead: a real SQLite file with the real schema and MessagePack records, built by `make-fixture.py`. It covers every rating, a record with no `ratings` key, two photos sharing a stem, a derived file, superseded revisions, unusual MessagePack widths, and each record shape the reader has to exclude.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the check that runs against a real catalog.
