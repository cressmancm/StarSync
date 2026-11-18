# StarSync 1.0

Draft, for the GitHub release. Nothing is published yet.

---

**StarSync is a lightweight app that copies your star ratings from Lightroom into Apple Photos.**

Apple brought star ratings back to Photos, but it doesn't pick up the ratings from your Lightroom exports. StarSync reads your Lightroom library, finds the same photos in Apple Photos, and copies the stars over.

This is the first release.

## What you can do with it

- **Sync everything or one album.** Choose the whole catalog or a single album. Each album shows how many of its photos are rated, so you know what you'll get before you start.
- **Fill in missing ratings.** If a photo has no rating in Photos, it gets the one from Lightroom.
- **Choose when ratings differ.** If a photo has a different rating on each side, StarSync shows you both and lets you pick. You can go one at a time, or take them all from Lightroom or keep them all from Photos.
- **Review every change first.** The review list has a thumbnail for each photo, its rating in Lightroom, its rating in Photos, and what StarSync plans to write. You can change any row before you click Write.
- **Undo a sync.** StarSync saves the old ratings before each sync, so Revert puts them all back.

## Privacy and your libraries

- I build everything with privacy in mind. StarSync has no analytics, no tracking, no data collection, and no account, and it makes no network connections.
- Your Lightroom library is opened read-only, from a temporary copy, so a sync is safe even while Lightroom is open.
- Star ratings are the only thing StarSync writes. Titles, captions, keywords, dates, locations, and albums stay as they are.
- Nothing is written until you've reviewed the list and clicked Write.
- Photos with no stars in Lightroom are skipped, so StarSync won't clear a rating you set in Photos.
- StarSync checks each rating in Photos again right before it writes. If you rate a photo in Photos while the review list is open, that rating is kept.

## You'll need

- **macOS 27 or later.** Earlier versions of Photos don't have a star rating that an app can set.
- **Adobe Lightroom**, the cloud-based version, with a `Lightroom Library.lrlibrary` in your Pictures folder.
- Exports that keep the camera's filename, which is Lightroom's default. StarSync uses the filename to pair photos up.

**Lightroom Classic is not supported.** It stores ratings in a different format.

## Good to know

- Sometimes several photos share a filename, like virtual copies or two cameras that reached the same number. StarSync tells them apart by capture time, then pixel dimensions. If it still can't tell, it lists the photo as ambiguous and doesn't write anything to it.
- Raw files you never exported show up as not in Photos. That's expected.
- Photos in a shared library can't be changed by an app, so StarSync lists those as read-only.

## Install

Download the DMG below, open it, and drag StarSync to your Applications folder. It's signed and notarized.

The first time you run it, StarSync asks for access to your Photos library, then asks you to choose your Lightroom library. It remembers both.

MIT licensed. Source at https://github.com/cressmancm/StarSync.
