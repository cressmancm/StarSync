<p align="center"><img src="docs/logo.svg" width="110" alt=""></p>

# StarSync

**A free Mac app that copies your Lightroom star ratings into Apple Photos.**

## Why I made this

When I shoot with my big camera, everything goes into Lightroom first. After triaging and editing, I aim to end up with 10 to 20 photos from a shoot. Star ratings are how I stay honest with myself about whether I've really cut it down to the best shots, so I spend time getting every rating right before I export to Apple Photos.

Apple dropped star ratings when it discontinued iPhoto in 2015, so I was so excited when they came back to Photos in 2026. I hoped Photos would pick up the ratings I'd already given in Lightroom. It didn't, so I built StarSync.

I care a lot about privacy, and I build everything with that in mind. StarSync has no analytics, no tracking, and no data collection.

Built with [Claude Code](https://claude.com/claude-code). More of my work at [chipcressman.photo](https://chipcressman.photo).

## What it does

- **Reads your Lightroom library directly.** You don't need to export anything or install a plugin. Choose your `.lrlibrary` and StarSync reads the ratings from it.
- **Syncs everything or one album.** Choose the whole catalog or a single album. Each album shows how many of its photos are rated, so you know what you'll get before you start.
- **Fills in missing ratings.** If a photo has no rating in Photos, it gets the one from Lightroom.
- **Asks before changing a rating you already set.** If a photo has three stars in Photos and five in Lightroom, StarSync shows you both and lets you pick. You can go one at a time, or take them all from Lightroom or keep them all from Photos.
- **Shows you every change first.** The review list has a thumbnail for each photo, its rating in Lightroom, its rating in Photos, and what StarSync plans to write. You can change any row, and nothing is written until you click Write.
- **Hides albums with no rated photos.** They would have nothing to sync. You can show them again with one click.
- **Can be undone.** StarSync saves the old ratings before each sync, so Revert puts them all back.
- **Skips photos you haven't rated.** No stars in Lightroom usually means you haven't gotten to that photo yet, so StarSync leaves it alone. It won't clear a rating you set in Photos.

## Privacy

I build everything with privacy in mind.

- **No tracking or data collection.** StarSync makes no network connections. There are no accounts, no analytics, and no crash reporting.
- **Your Lightroom library isn't changed.** StarSync opens it read-only and works from a temporary copy, so a sync is safe even while Lightroom is open.
- **Star ratings are the only thing it writes.** Titles, captions, keywords, dates, locations, albums, and the photos themselves stay as they are.
- **Every sync can be reverted**, and nothing is written until you've reviewed the list.

## Requirements

- **macOS 27 or later.** Earlier versions of Photos don't have a star rating that an app can set.
- **Adobe Lightroom**, the cloud-based version, with a `Lightroom Library.lrlibrary` in your Pictures folder.
- Exports that keep the original camera filenames (`DSCF4087.jpg`), which is Lightroom's default. StarSync uses the filename to pair photos up.

**Lightroom Classic is not supported.** Classic stores its ratings in a different format, and I don't use it, so StarSync won't find a Classic catalog.

## Installing

> **No release yet.** The first signed build isn't out. Until it is, you can [build it yourself](#building-it-yourself).

Once there is one: download the latest `StarSync.dmg` from [Releases](../../releases), open it, and drag StarSync to your Applications folder. It's signed and notarized, so it opens without any warnings.

The first time you run it, StarSync asks for access to your Photos library, then asks you to choose your Lightroom library. It remembers both.

### Building it yourself

```bash
git clone https://github.com/cressmancm/StarSync.git
cd StarSync
open StarSync.xcodeproj
```

Needs Xcode 27 or later. Set your own team under Signing & Capabilities and press Run.

## How photos get paired up

Lightroom exports keep the camera's filename, so `DSCF4087.RAF` in Lightroom and `DSCF4087.jpg` in Photos are the same photo. Sometimes several photos share a filename, like virtual copies or two cameras that reached the same number. When that happens, StarSync compares capture time, then pixel dimensions. If it still can't tell which photo is which, it lists the photo as ambiguous and doesn't write anything to it.

Most people don't export every raw file. Those photos show up as not in Photos, which is expected.

## License

MIT. See [LICENSE](LICENSE).
