// Renders the Scheduled app icon at an arbitrary pixel size using CoreGraphics.
// No external tooling required — used by scripts/make-icons.sh to produce the
// macOS .icns and the iOS asset-catalog image.
//
//   swiftc scripts/GenerateIcon.swift -o /tmp/genicon
//   /tmp/genicon <out.png> <pixelSize> <ios|macos>
//
// Design: a white calendar card with an indigo header and a bold checkmark,
// on an indigo→violet gradient. iOS style is full-bleed (the OS masks corners);
// macOS style draws the rounded "squircle" with a margin.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4, let px = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: GenerateIcon <out.png> <size> <ios|macos>\n".utf8))
    exit(2)
}
let outPath = args[1]
let isMac = (args[3] == "macos")
let S = CGFloat(px)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// Background squircle + gradient.
let inset: CGFloat = isMac ? S * 0.09 : 0
let bg = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let bgRadius: CGFloat = isMac ? bg.width * 0.235 : 0
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: bg, cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil))
ctx.clip()
let grad = CGGradient(colorsSpace: space,
                      colors: [rgb(0.36, 0.34, 1.0), rgb(0.56, 0.30, 0.96)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Calendar card.
let cardW = bg.width * 0.60
let cardH = bg.height * 0.56
let card = CGRect(x: bg.midX - cardW / 2,
                  y: bg.midY - cardH / 2 - bg.height * 0.02,
                  width: cardW, height: cardH)
let cardRadius = cardW * 0.11
let cardPath = CGPath(roundedRect: card, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.008), blur: S * 0.03, color: rgb(0, 0, 0, 0.18))
ctx.addPath(cardPath)
ctx.setFillColor(rgb(1, 1, 1))
ctx.fillPath()
ctx.restoreGState()

// Indigo header band, clipped to the card's rounded top.
let headerH = cardH * 0.26
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
ctx.setFillColor(rgb(0.36, 0.34, 1.0))
ctx.fill(CGRect(x: card.minX, y: card.maxY - headerH, width: cardW, height: headerH))
ctx.restoreGState()

// Two binding tabs straddling the top edge.
let tabW = cardW * 0.07
let tabH = cardH * 0.12
for frac in [0.30, 0.70] {
    let r = CGRect(x: card.minX + cardW * CGFloat(frac) - tabW / 2,
                   y: card.maxY - tabH * 0.55, width: tabW, height: tabH)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: tabW / 2, cornerHeight: tabW / 2, transform: nil))
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
}

// Bold checkmark in the body.
let c = CGPoint(x: card.midX, y: card.minY + (cardH - headerH) * 0.46)
let m = cardW * 0.30
ctx.setStrokeColor(rgb(0.40, 0.34, 0.98))
ctx.setLineWidth(cardW * 0.11)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: c.x - m * 0.58, y: c.y))
ctx.addLine(to: CGPoint(x: c.x - m * 0.12, y: c.y - m * 0.42))
ctx.addLine(to: CGPoint(x: c.x + m * 0.62, y: c.y + m * 0.46))
ctx.strokePath()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
