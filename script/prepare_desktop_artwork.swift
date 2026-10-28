// SPDX-License-Identifier: GPL-3.0-only
import AppKit

// Crop official source photographs to the chassis used by StorageDesktopProfile.
// Usage: swift script/prepare_desktop_artwork.swift <download-directory> <asset-catalog>
let inputs = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = URL(fileURLWithPath: CommandLine.arguments[2])

func export(_ source: String, crop: CGRect, asset: String, name: String,
            hideExtraSockets: Bool = false) throws {
    let data = try Data(contentsOf: inputs.appendingPathComponent(source))
    guard let original = NSBitmapImageRep(data: data)?.cgImage,
          let cropped = original.cropping(to: crop) else { fatalError("Invalid source: \(source)") }
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cropped.width,
        pixelsHigh: cropped.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        .draw(in: NSRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
    NSGraphicsContext.restoreGraphicsState()
    let transparent = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
    if asset.hasPrefix("MacMini") || asset == "MacStudioTop" {
        let width = CGFloat(cropped.width)
        let height = CGFloat(cropped.height)
        let radius = width * 0.17
        for y in 0..<cropped.height {
            for x in 0..<cropped.width {
                let px = CGFloat(x) + 0.5
                let py = CGFloat(y) + 0.5
                let cx = min(width - radius, max(radius, px))
                let cy = min(height - radius, max(radius, py))
                if hypot(px - cx, py - cy) > radius {
                    image.setColor(transparent, atX: x, y: y)
                }
            }
        }
    } else {
        for y in 215..<cropped.height {
            for x in 0..<cropped.width where x < 119 || x > 194 {
                image.setColor(transparent, atX: x, y: y)
            }
        }
    }
    if hideExtraSockets {
        // The two-port enclosure has the same back panel. Remove the two unused
        // openings using adjacent panel pixels; this is a derived diagram asset.
        for y in 193...207 {
            for x in 43...61 {
                image.setColor(image.colorAt(x: 85, y: y)!, atX: x, y: y)
            }
        }
    }
    let folder = assets.appendingPathComponent("\(asset).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let png = image.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: folder.appendingPathComponent(name), options: .atomic)
}

try export("mini-top.jpg", crop: CGRect(x: 2, y: 2, width: 365, height: 365),
           asset: "MacMiniTop", name: "mac-mini-top.png")
try export("mini-classic-top.png", crop: CGRect(x: 108, y: 78, width: 497, height: 497),
           asset: "MacMiniClassicTop", name: "mac-mini-classic-top.png")
try export("studio-top.jpg", crop: CGRect(x: 2, y: 2, width: 558, height: 558),
           asset: "MacStudioTop", name: "mac-studio-top.png")
try export("imac-color.jpg", crop: CGRect(x: 321, y: 2, width: 314, height: 265),
           asset: "iMacBack", name: "imac-back.png")
try export("imac-color.jpg", crop: CGRect(x: 321, y: 2, width: 314, height: 265),
           asset: "iMacBackTwoPorts", name: "imac-back-two.png", hideExtraSockets: true)
