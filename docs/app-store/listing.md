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
| Name (30) | StarSync |
| Subtitle (30) | Copy star ratings into Photos |
| Bundle ID | com.chipcressman.starsync |
| SKU | starsync |
| Primary category | Photography |
| Secondary category | Utilities |
| Content rights | Does not contain, show or access third-party content |
| Age rating | Every question answered None, which gives 4+ |

If the name is taken when you create the record, use **StarSync: Ratings to
Photos** — still under 30.

## Pricing and Availability

Free, in every territory.

## App Privacy

**Data Not Collected.** StarSync makes no network connections, has no account,
and collects nothing. The privacy manifest in the app says the same.

Privacy Policy URL: `https://chipcressman.com/starsync/privacy`, publishing
[`privacy-policy.md`](privacy-policy.md). It has to be live before you submit.

## Version 1.0

### Promotional text (170)

```
Your Lightroom star ratings, in Apple Photos. StarSync shows you every change before it writes one, and puts everything back in one click if you change your mind.
```

### Description (4000)

```
StarSync copies the star ratings you give your photos in Lightroom into Apple Photos, so the photos you've already picked out are picked out in Photos too.

macOS 27 is what made this possible: it's the first version of Photos with a real star rating that another app can set. StarSync reads your Lightroom library, finds each photo's match in your Photos library, and writes the rating across.

NOTHING HAPPENS UNTIL YOU'VE SEEN IT
Before anything is written, StarSync lists every change it's about to make: what Lightroom says, what Photos says now, and what it will write. Change any of them, one at a time or all at once.

WHERE THE TWO DISAGREE, YOU DECIDE
If a photo already has a different rating in Photos, StarSync doesn't pick a winner. It asks you, and writes nothing for that photo until you've answered.

UNRATED NEVER MEANS ERASE
A photo you haven't rated in Lightroom yet is left alone. StarSync never clears a rating you set in Photos just because Lightroom has none.

ONE CLICK PUTS IT ALL BACK
Every sync is recorded before its first write, so Revert puts every rating back the way it was.

CAREFUL WITH YOUR LIBRARIES
• Your Lightroom library is opened read-only and is never changed.
• The star rating is the only thing StarSync ever writes to Photos.
• StarSync checks both libraries again just before it writes. A photo that changed after you reviewed it is left alone and listed at the end, unless you chose its rating yourself.
• Nothing leaves your Mac. No account, no network, no data collected.

Sync your whole catalog, or one album at a time.

Requires macOS 27 and a Lightroom library on your Mac — the cloud-based Lightroom, whose library is a .lrlibrary file in your Pictures folder. Lightroom Classic catalogs aren't supported.

StarSync is not affiliated with or endorsed by Adobe. Adobe and Lightroom are trademarks of Adobe Inc.
```

### Keywords (100)

```
star,stars,rating,ratings,sync,photo,library,catalog,photographer,culling,raw,organize,favorites
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
