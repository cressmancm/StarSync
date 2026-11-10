<p align="center"><img src="docs/logo.svg" width="110" alt=""></p>

# StarSync

**A free Mac app that carries your Lightroom star ratings into Apple Photos.**

## Why I made this

I rate everything in Lightroom. Triage a shoot, work the keepers up, and the ones worth anything end up at four or five stars. Then I export JPEGs, bring them into Apple Photos, and all of that is gone — Photos shows a few thousand pictures with nothing to tell them apart. The judgement was the slow part, and it didn't survive the export.

Ratings don't travel in a JPEG that Photos will read, so the only way across is to pair each photo up again on the other side. StarSync does that: it reads the ratings straight out of the Lightroom catalog, finds each photo's counterpart in Apple Photos, and writes the stars over.

macOS 27 is what made this possible. It's the first version of Photos with a real star rating you can set from code — before it, the best anyone could do was fake stars with keywords.

Built with [Claude Code](https://claude.com/claude-code). More of my work at [chipcressman.photo](https://chipcressman.photo).

## What it does

- **Reads your Lightroom catalog directly.** No exporting a sidecar, no plugin to install in Lightroom. Point it at your `.lrlibrary` and it reads the ratings out.
- **Syncs everything or just one album.** Pick the whole catalog or any one of your collections and projects. Each one shows how many of its photos are rated before you commit to anything.
- **Three ways to handle photos that are already rated.**
  - *Add only* — fill in the blanks, never touch a rating that's already there.
  - *Lightroom wins* — make Photos match Lightroom.
  - *Review conflicts* — fill in the blanks, and ask you about every disagreement.
- **Lets you decide photo by photo.** The review list shows a thumbnail, what Lightroom says, what Photos says, and what's about to happen. Change any row before you write, whichever mode you picked. Five stars against four is not a decision you should have to make from a filename.
- **Never writes without showing you first.** Nothing changes until you've seen the full list and pressed the button.
- **Can be undone.** Every run is recorded before the first write. One button puts every rating back.
- **Leaves unrated photos alone.** Zero stars in Lightroom means "haven't got to it yet", not "zero stars", so StarSync skips those. A rating you set in Photos is never wiped by a photo you simply haven't triaged.

## Requirements

- **macOS 27 or later.** Earlier versions of Photos have no star rating to write to, so there is no way to make this work on them.
- **Adobe Lightroom** — the cloud-based one, with a `Lightroom Library.lrlibrary` in your Pictures folder.
- Your exports should keep the original camera filenames (`DSCF4087.jpg`), which is Lightroom's default. That's how photos get paired up.

**Lightroom Classic is not supported.** Classic keeps its ratings in a completely different format, and I don't use it. If you're on Classic, this app won't find your catalog.

## Installing

Download the latest `StarSync.dmg` from [Releases](../../releases), open it, and drag StarSync to your Applications folder. It's signed and notarized, so it opens without any warnings.

The first time you run it, StarSync asks for access to your Photos library, then asks you to pick your Lightroom library. It remembers both.

### Building it yourself

```bash
git clone https://github.com/cressmancm/StarSync.git
cd StarSync
open StarSync.xcodeproj
```

Needs Xcode 27 or later. Set your own team under Signing & Capabilities and press Run.

## Privacy

- **Nothing leaves your Mac.** StarSync makes no network calls at all. No analytics, no accounts, no crash reporting, nothing about you or your photos goes anywhere.
- **Your Lightroom catalog is never modified.** It's opened strictly read-only, and from a temporary copy at that, so a sync can't disturb Lightroom even if it's running at the time.
- **The rating is the only thing StarSync ever writes.** It doesn't touch titles, captions, keywords, dates, locations, albums or the images themselves.
- **Every run is reversible**, and nothing is written until you've reviewed the list.

## How photos get paired up

Lightroom exports keep the camera's filename, so `DSCF4087.RAF` in Lightroom and `DSCF4087.jpg` in Photos are the same picture. When several photos share a name — virtual copies, or two camera bodies whose counters have met — StarSync falls back to capture time, then to pixel dimensions. Anything it still can't pin down is reported as ambiguous and left alone rather than guessed at.

Plenty of raw files are never exported. Those just show as not in Photos, which is normal and nothing to worry about.

## License

MIT — see [LICENSE](LICENSE).
