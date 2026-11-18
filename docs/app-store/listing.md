# App Store listing

Everything typed into App Store Connect for StarSync, in the order the pages ask
for it. Fields with a limit say what it is; `check-listing.sh` beside this file
counts them.

The screenshots are in [`screenshots/`](screenshots/), made by
`make-screenshots.swift` from the window captures in `docs/screenshots`. The
review kit is built by `review-kit/make-review-kit.swift`.

## Trademarks

"Lightroom" and "Adobe" stay out of the name, subtitle and keywords. Guideline
2.3.7 names trademarked terms in metadata as a reason to reject, and 5.2.1 asks
for permission to use them. The description has to say Lightroom — there is no
other way to explain what the app does — so it says so plainly, once, and says
StarSync isn't Adobe's.

## App Information

| Field | Value |
|---|---|
| Name (30) | StarSync: Ratings to Photos |
| Subtitle (30) | Copy star ratings into Photos |
| Bundle ID | com.chipcressman.starsync |
| SKU | starsync |
| Primary category | Photography |
| Secondary category | Utilities |
| Content rights | Does not contain, show or access third-party content |
| Age rating | Every question answered None, which gives 4+ |

Plain "StarSync" was already taken on the App Store when the record was
created, so the store name carries a tagline. The name under the icon in the
Dock and Finder is still StarSync — that comes from the bundle, not from here.

## Pricing and Availability

Free, in every territory.

## App Privacy

**Data Not Collected.** StarSync makes no network connections, has no account,
and collects nothing. The privacy manifest in the app says the same.

Privacy Policy URL: `https://chipcressman.com/starsync/privacy`, which
publishes [`privacy-policy.md`](privacy-policy.md). Live since 17 November 2026.

## Version 1.0

### Promotional text (170)

```
StarSync is a lightweight app that copies star ratings from Lightroom into Apple Photos. Review changes before they're made and undo any sync.
```

### Description (4000)

```
StarSync is a lightweight app that copies your star ratings from Lightroom into Apple Photos.

Apple brought star ratings back to Photos, but it doesn't pick up the ratings from your Lightroom exports. StarSync reads your Lightroom library, finds the same photos in your Photos library, and copies the stars over.

BUILT WITH PRIVACY IN MIND
No analytics, no tracking, no data collection, and no account. StarSync makes no network connections.

SEE EVERY CHANGE FIRST
Before anything is written, StarSync lists each photo with its rating in Lightroom, its rating in Photos, and what it plans to write. You can change any of them, one at a time or all at once.

YOU CHOOSE WHEN RATINGS DIFFER
If a photo already has a different rating in Photos, StarSync shows you both and waits for you to pick.

UNRATED PHOTOS ARE SKIPPED
If you haven't rated a photo in Lightroom yet, StarSync leaves it alone. It won't clear a rating you set in Photos.

UNDO ANY SYNC
StarSync saves the old ratings before each sync. Click Revert to put them back.

SAFE FOR YOUR LIBRARIES
• Your Lightroom library is opened read-only and isn't changed.
• Star ratings are the only thing StarSync writes to Photos.
• StarSync checks both libraries again right before it writes. If a photo changed after you reviewed it, StarSync skips it and lists it at the end, unless you chose its rating yourself.

You can sync your whole catalog or one album at a time.

Requires macOS 27 and a Lightroom library on your Mac. This is the cloud-based Lightroom, which keeps its library in a .lrlibrary file in your Pictures folder. Lightroom Classic catalogs aren't supported.

StarSync is not affiliated with or endorsed by Adobe. Adobe and Lightroom are trademarks of Adobe Inc.
```

### Keywords (100)

```
star,stars,rating,sync,photo,library,catalog,photographer,culling,raw,organize,favorites
```

### Support URL

`https://chipcressman.com/starsync`

### Marketing URL

`https://chipcressman.com/starsync`

### Copyright

`2026 Chip Cressman`

## App Review Information

**Sign-in required:** No.

**Attachment:** `build/StarSync Review Kit.zip`, from
`swift docs/app-store/review-kit/make-review-kit.swift`.

**Notes (4000):**

```
StarSync copies star ratings from an Adobe Lightroom library into Apple Photos. It relies on the writable star rating PhotoKit gained in macOS 27.

You don't need Lightroom to review it. The attached StarSync Review Kit has eight photos and a small Lightroom library that rates them. Its Read Me walks through the whole app in seven steps: import the photos into Photos, choose the demo library in StarSync, review the changes, write them, check a rating in the Photos Info panel, and revert. It also shows how to produce a conflict for StarSync to ask you about.

Photos access: StarSync asks for read and write access because it writes star ratings. The rating is the only property it ever changes, and nothing is written until every change has been shown on screen.

File access: the Lightroom library is chosen by the user in an open panel and opened read-only (com.apple.security.files.user-selected.read-only). A security-scoped bookmark keeps that access across launches.

StarSync makes no network connections, has no account, and collects no data.
```
