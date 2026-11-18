<p align="center"><img src="docs/logo.svg" width="110" alt=""></p>

# StarSync

**A lightweight Mac app that copies your star ratings from Lightroom into Apple Photos. Free and open source.**

## How it works

Apple brought star ratings back to Photos, but it doesn't pick up the ratings from your Lightroom exports. StarSync reads your Lightroom library, finds the same photos in Photos, and copies the stars over.

1. **Choose photos.** Pick your Lightroom library, then sync one album or your whole catalog.
2. **Review.** StarSync lists every change before it's made. If a photo already has a different rating in Photos, you choose which one to keep.
3. **Write.** Click Write and the stars show up in Photos. If you change your mind, Revert puts every rating back.

I run it as the last step of my export. You can also run it every so often if you're still changing ratings in Lightroom.

## Good to know

- Star ratings are the only thing StarSync writes. Your Lightroom library is opened read-only.
- Photos you haven't rated in Lightroom are skipped.
- Photos are matched by filename, so if you rename files on export it will not work.
- If several photos share a filename, StarSync compares capture time and size. If it still can't tell them apart, it skips them and tells you.

## Why I made this

When I shoot with my big camera, everything goes into Lightroom first. After triaging and editing, I aim to end up with 10 to 20 photos from a shoot. Star ratings are how I stay honest with myself about whether I've really cut it down to the best shots, so I spend time getting every rating right before I export to Apple Photos.

Apple dropped star ratings when it discontinued iPhoto in 2015, so I was so excited when they came back to Photos in 2026. I hoped Photos would pick up the ratings I'd already given in Lightroom. It didn't, so I built StarSync.

I'm Chip Cressman, an engineering leader in Seattle and a lifelong photographer. More of my work is at [chipcressman.com](https://chipcressman.com) and [chipcressman.photo](https://chipcressman.photo).

## Privacy

I care a lot about privacy, and I build everything with that in mind. StarSync has no analytics, no tracking, no data collection, and no account. It makes no network connections.

It runs in the macOS sandbox, so it can only open the Lightroom library you choose and, once you allow it, your Photos library. The code is all here under the MIT license if you want to check for yourself.

[Read the privacy policy](https://chipcressman.com/starsync/privacy)

## Requirements

- macOS 27 or later.
- Adobe Lightroom, the cloud-based version, with a `Lightroom Library.lrlibrary` in your Pictures folder.
- Lightroom Classic isn't supported.

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

## Support

If something isn't working, or a photo was paired with the wrong one, please let me know by [opening an issue](../../issues). It helps to include your macOS version, the photo's filename in Lightroom and in Photos, and any other helpful information.

## Built with

Swift 6, SwiftUI, PhotoKit, SQLite, and [Claude Code](https://claude.com/claude-code).

## License

MIT. See [LICENSE](LICENSE).
