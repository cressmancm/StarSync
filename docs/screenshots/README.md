# Screenshots

**None have been taken yet.** This file is the shot list, so whoever takes them gets a consistent set.

Screen Recording was the first thing in the way; Chip granted it on 2026-11-12 and capture works now. Two things are left:

1. **Nobody is at the Mac.** A capture of a locked Mac is the login window, not the app. Only Chip can unlock it.
2. **No Accessibility permission.** Taking this set means driving the app through all four steps, and clicking from a script needs System Settings → Privacy & Security → Accessibility. Without it `osascript` gets *"not allowed assistive access"*, so the app can be launched but not used. Granting it hands any script on this Mac the ability to click and type anywhere, which is a bigger thing to hand over than screen capture was — Chip taking the five shots himself is both faster and less to give away.

## What's needed

Capture the main window only (⌘⇧4 then Space, or `screencapture -o -w`), on a Retina display, at the window's natural size. `-o` leaves out the drop shadow, which keeps the files small and lets the page place its own.

| File | Step | Appearance | What should be on screen |
|---|---|---|---|
| `preview-dark.png` | Review | Dark | The money shot. A real album with a mix: a few **New rating** rows, at least one **Conflict** awaiting a decision, and the Lightroom → Photos star columns clearly readable. "All photos" selected. |
| `preview-light.png` | Review | Light | The same album and scroll position, so the pair can be shown side by side. |
| `source-dark.png` | Choose photos | Dark | A library chosen and an album list visible, with the "N photos, M rated" summary line. |
| `mode-dark.png` | Choose what to sync | Dark | All three modes, with Review conflicts selected. |
| `apply-dark.png` | Done | Dark | A finished run — "Wrote N ratings to Photos." with Revert enabled. |

Worth having if the chance comes up, since both show behaviour nothing else does:

- `preview-stale-dark.png` — the Review step with the orange "Ratings in Photos have changed" banner and its Rebuild button. Produce it by rating a photo in Photos.app while the preview is open.
- `apply-skipped-dark.png` — the Done screen listing rows left alone because Photos moved on after the preview.

## Before publishing

These show real photographs from Chip's library as thumbnails. The repo is public and the shots also go on chipcressman.com/starsync, so that's a decision for Chip to make deliberately rather than something to assume. An album of landscape work is the safe kind to pick.

## Keeping them honest

Retake the set when the UI changes enough that a shot misrepresents it. A screenshot of a version that no longer exists is worse than none.
