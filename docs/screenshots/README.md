# Screenshots

**None have been taken yet.** This file is the shot list, so whoever takes them gets a consistent set.

Permissions are no longer the problem. Chip granted Screen Recording and Accessibility on 2026-11-12, so a session can both capture the screen and drive the app. Two things are left, and both need him:

1. **Nobody is signed in.** A capture of a locked Mac is the login window, not the app. Only Chip can unlock it.
2. **The demo album needs to be an ordinary album, not a smart one.** See below.

### Why a smart album won't do

Chip made a Lightroom album called **StarSync Demo** on 2026-11-12 to supply safe, publishable photos for these shots. It was created as a *smart* album, and StarSync cannot read it. From the catalog directly:

- `fullDocId 9b0d6e3911604196948b40ca9b2d1c54`, subtype **`smart`** — the only smart album in the catalog.
- Its membership is a stored **predicate on `rating`**, not a list of photos.
- It has **zero** `album_asset` rows. The membership is computed by Lightroom and exists nowhere in the catalog file.

StarSync builds album membership from `album_asset`, and the chooser offers only `collection` albums. So a smart album never appears in the picker, and would read as 0 photos if it did.

**The fix is on Chip's side:** select the photos and make a plain New Album rather than a New Smart Album. Any name will do.

This is also worth knowing about the app itself, separately from the screenshots: anyone who organises Lightroom with smart albums will find them missing from StarSync's list with nothing on screen to say why. Either list them or say they aren't supported — a decision for after 1.0, not a release blocker.

## What's needed

Capture the main window only (⌘⇧4 then Space, or `screencapture -o -w`), on a Retina display, at the window's natural size. `-o` leaves out the drop shadow, which keeps the files small and lets the page place its own.

| File | Step | Appearance | What should be on screen |
|---|---|---|---|
| `preview-dark.png` | Review | Dark | The money shot. A real album with a mix: the **Needs your decision** section open with at least one conflict in it, **Will write** below it, and the Lightroom → Photos star columns clearly readable. |
| `preview-light.png` | Review | Light | The same album and scroll position, so the pair can be shown side by side. |
| `source-dark.png` | Choose photos | Dark | A library chosen and the album list visible, with the counts on each row and the "N albums with no rated photos hidden" footer. |
| `apply-dark.png` | Done | Dark | A finished run — "Wrote N ratings to Photos." with Revert enabled. |

Worth having if the chance comes up, since both show behaviour nothing else does:

- `preview-stale-dark.png` — the Review step with the orange "Ratings in Photos have changed" banner and its Rebuild button. Produce it by rating a photo in Photos.app while the preview is open.
- `apply-skipped-dark.png` — the Done screen listing rows left alone because Photos moved on after the preview.

## Before publishing

These show real photographs from Chip's library as thumbnails. The repo is public and the shots also go on chipcressman.com/starsync, so that's a decision for Chip to make deliberately rather than something to assume. An album of landscape work is the safe kind to pick.

## Keeping them honest

Retake the set when the UI changes enough that a shot misrepresents it. A screenshot of a version that no longer exists is worse than none.
