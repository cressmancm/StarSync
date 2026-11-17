// Builds the Mac App Store screenshots from the window captures in
// docs/screenshots.
//
//     swift docs/app-store/make-screenshots.swift
//
// The App Store takes exactly four sizes for a Mac app — 1280×800, 1440×900,
// 2560×1600 and 2880×1800 — and the captures are 1640×1184, the window at 2×.
// So each one is placed, unscaled, on a 2560×1600 canvas with a caption above
// it. Unscaled matters: these are already Retina pixels, and enlarging them to
// fill the frame would soften every line of text in the shot.
//
// Re-run it whenever docs/screenshots changes. It reads nothing else.

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("docs/screenshots")
let output = root.appendingPathComponent("docs/app-store/screenshots")

let canvas = CGSize(width: 2560, height: 1600)

struct Shot {
    let file: String
    let out: String
    let caption: String
    let light: Bool
}

// Ordered as the store shows them. The first is the one most people see, and
// Review is the screen that explains what the app is for.
let shots = [
    Shot(file: "preview-dark.png", out: "1-review.png",
         caption: "See every change before anything is written", light: false),
    Shot(file: "source-dark.png", out: "2-choose.png",
         caption: "Sync one album, or the whole catalog", light: false),
    Shot(file: "apply-dark.png", out: "3-done.png",
         caption: "One click puts every rating back", light: false),
    Shot(file: "preview-light.png", out: "4-review-light.png",
         caption: "You settle every disagreement", light: true),
]

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

// The icon's own slate, so the set reads as one thing with the app tile next
// to it on the store page.
let darkTop = color(0x364156), darkBottom = color(0x212D40)
let lightTop = color(0xF4F6FA), lightBottom = color(0xE1E6EF)

for shot in shots {
    guard let image = NSImage(contentsOf: source.appendingPathComponent(shot.file)),
          let window = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fatalError("could not read \(shot.file)") }

    let size = CGSize(width: window.width, height: window.height)
    guard size.width <= canvas.width, size.height <= canvas.height - 300 else {
        fatalError("\(shot.file) is \(Int(size.width))×\(Int(size.height)); too big for the canvas")
    }

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Background. CoreGraphics' origin is bottom-left, so top is height.
    let gradient = CGGradient(
        colorsSpace: space,
        colors: (shot.light ? [lightTop, lightBottom] : [darkTop, darkBottom]) as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvas.height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // The window: centred across, sitting near the bottom, so the caption
    // gets the band above it. The capture was taken without its shadow, so
    // one is drawn here, following the window's rounded corners.
    let bottomMargin: CGFloat = 96
    let frame = CGRect(
        x: ((canvas.width - size.width) / 2).rounded(),
        y: bottomMargin,
        width: size.width, height: size.height
    )
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -20),
        blur: 70,
        color: CGColor(gray: 0, alpha: shot.light ? 0.22 : 0.5)
    )
    ctx.draw(window, in: frame)
    ctx.restoreGState()

    // Caption, centred in the band above the window.
    let band = CGRect(x: 0, y: frame.maxY, width: canvas.width, height: canvas.height - frame.maxY)
    let font = NSFont.systemFont(ofSize: 76, weight: .semibold)
    let text = NSAttributedString(string: shot.caption, attributes: [
        .font: font,
        .foregroundColor: shot.light
            ? NSColor(cgColor: color(0x212D40))!
            : NSColor(cgColor: color(0xE8ECF3))!,
        .kern: -0.6,
    ])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(
        x: ((canvas.width - bounds.width) / 2 - bounds.minX).rounded(),
        y: (band.midY - bounds.height / 2 - bounds.minY + 6).rounded()
    )
    CTLineDraw(line, ctx)

    // Written opaque. App Store Connect refuses screenshots with an alpha
    // channel, and a gradient canvas has nothing transparent in it anyway.
    let rendered = ctx.makeImage()!
    let opaque = CGContext(
        data: nil, width: rendered.width, height: rendered.height,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    opaque.draw(rendered, in: CGRect(origin: .zero, size: canvas))

    let rep = NSBitmapImageRep(cgImage: opaque.makeImage()!)
    let png = rep.representation(using: .png, properties: [:])!
    let url = output.appendingPathComponent(shot.out)
    try png.write(to: url)
    print("wrote \(shot.out)")
}
