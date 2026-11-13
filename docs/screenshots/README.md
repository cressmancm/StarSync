# Screenshots

**None have been taken yet.** This file is the shot list, so whoever takes them gets a consistent set.

Everything that was blocking these is cleared. Screen Recording and Accessibility were granted on 2026-11-12, and **StarSync Demo** now exists as an ordinary Lightroom album with 14 rated photos. Shoot that album and nothing else: those photos are cleared for the public repo and for chipcressman.com/starsync, and no other album's are.

Smart albums are not listed in the chooser, deliberately — their membership is a stored predicate with no `album_asset` rows, so there is nothing to read — so don't expect one in a shot.

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
