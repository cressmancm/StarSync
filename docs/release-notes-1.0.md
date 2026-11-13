# StarSync 1.0

Draft, for the GitHub release. Nothing is published yet.

---

**StarSync carries your Lightroom star ratings into Apple Photos.**

Rate your photos in Lightroom, export the JPEGs, import them into Photos — and the ratings don't come with them. StarSync reads the ratings straight out of your Lightroom catalog, pairs each photo with its copy in Apple Photos, and writes the stars across.

This is the first release.

## What you can do with it

- **Sync everything, or one album.** Pick the whole catalog or any one of your albums. Each one tells you how many of its photos are rated before you commit to anything.
- **Fills in blanks, asks about disagreements.** A photo with no rating in Photos gets Lightroom's. Where both sides disagree, StarSync holds it back and asks — one at a time, or all at once.
- **Decide photo by photo.** The review list shows a thumbnail, what Lightroom says, what Photos says, and what's about to happen — and you can change any row before writing.
- **Undo a run.** Every sync is recorded before the first rating is written. One button puts them all back.

## What it won't do to your library

- Your Lightroom catalog is opened strictly read-only, from a temporary copy, so a sync can't disturb Lightroom even while it's running.
- The rating is the only thing ever written. Not titles, captions, keywords, dates, locations or albums.
- Nothing is written until you've seen the full list and pressed the button.
- A photo at zero stars in Lightroom is left alone. Zero means "haven't got to it yet", not "zero stars", so it never clears a rating you set in Photos.
- Ratings are checked against Photos again in the moment before each one is written, so a rating you add in Photos while the preview is open won't be overwritten by a stale comparison.
- No network calls at all. No analytics, no accounts, no crash reporting.

## You'll need

- **macOS 27 or later.** This is the first version of Photos with a real star rating that can be set from code. There's no way to make it work on anything earlier.
- **Adobe Lightroom** — the cloud one, with a `Lightroom Library.lrlibrary` in your Pictures folder.
- Exports that keep the camera's filename, which is Lightroom's default. That's how photos get paired up.

**Lightroom Classic is not supported.** It stores ratings in an entirely different format.

## Worth knowing

- Photos that share a filename — virtual copies, or two camera bodies whose counters have met — are separated by capture time and then pixel dimensions. Anything still ambiguous is reported and left alone rather than guessed at.
- Raw files you never exported simply show as not in Photos. That's normal.
- Photos in a shared library can't have their properties changed, so those are reported as read-only.

## Install

Download the DMG below, open it, and drag StarSync to your Applications folder. It's signed and notarized.

The first run asks for access to your Photos library, then asks you to pick your Lightroom library. It remembers both.

MIT licensed. Source at https://github.com/cressmancm/StarSync.
