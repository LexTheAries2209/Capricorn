// SPDX-License-Identifier: GPL-3.0-only
import AppKit

// Crop official source photographs to the chassis used by StorageDesktopProfile.
// Usage: swift script/prepare_desktop_artwork.swift <download-directory> <asset-catalog>
let inputs = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = URL(fileURLWithPath: CommandLine.arguments[2])

struct Pixel {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var whiteDistance: Double { 3 - red - green - blue }
}

func removeWhiteMatte(from image: NSBitmapImageRep, isIMac: Bool) {
    let width = image.pixelsWide
    let height = image.pixelsHigh
    let source: [Pixel] = (0..<height).flatMap { y in
        (0..<width).map { x in
            let color = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            return Pixel(red: color.redComponent, green: color.greenComponent,
                         blue: color.blueComponent, alpha: color.alphaComponent)
        }
    }
    var coverage = source.map(\.alpha)

    func scan(_ indices: [Int]) {
        guard !indices.isEmpty else { return }
        // Find a sustained departure from the white backdrop, then sample
        // locally. A distant reference can mistake the logo for the chassis
        // color or cut into a pale metal surface with a lighting gradient.
        guard let edge = indices.indices.dropLast(2).first(where: { position in
            (0..<3).allSatisfy { source[indices[position + $0]].whiteDistance > 0.045 }
        }) else {
            for index in indices { coverage[index] = 0 }
            return
        }
        let samples = (3...6).map { source[indices[min(edge + $0, indices.count - 1)]].whiteDistance }
        let foreground = samples.reduce(0, +) / Double(samples.count)
        for position in 0..<min(edge + 3, indices.count) {
            let index = indices[position]
            let alpha = position < edge - 3 ? 0 :
                min(1, max(0, source[index].whiteDistance / max(foreground, 0.001)))
            coverage[index] = min(coverage[index], alpha < 0.06 ? 0 : alpha)
        }
    }

    for y in 0..<height {
        let range = isIMac && y >= 215 ? 119..<195 : 0..<width
        let indices = range.map { y * width + $0 }
        scan(indices)
        scan(indices.reversed())
        if isIMac && y >= 215 {
            for x in 0..<width where !range.contains(x) { coverage[y * width + x] = 0 }
        }
    }
    for x in 0..<width {
        let end = isIMac && (x < 119 || x >= 195) ? 215 : height
        let indices = (0..<end).map { $0 * width + x }
        scan(indices)
        scan(indices.reversed())
    }
    // JPEG ringing can leave isolated translucent specks outside the chassis.
    // Every real part of these cutouts connects to the center of the panel.
    let center = (height / 2) * width + width / 2
    var connected = [Bool](repeating: false, count: source.count)
    var queue = [center]
    connected[center] = true
    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let x = index % width
        let y = index / width
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && nx < width && ny >= 0 && ny < height {
            let neighbor = ny * width + nx
            if !connected[neighbor] && coverage[neighbor] > 0.06 {
                connected[neighbor] = true
                queue.append(neighbor)
            }
        }
    }
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            let pixel = source[index]
            let alpha = connected[index] ? coverage[index] : 0
            // JPEG edge colors already contain white. Removing it before PNG
            // encoding prevents a bright halo on dark topology backgrounds.
            func unmatte(_ channel: Double) -> Double {
                alpha == 0 ? 0 : min(1, max(0, 1 - (1 - channel) / alpha))
            }
            image.setColor(NSColor(deviceRed: unmatte(pixel.red),
                                   green: unmatte(pixel.green),
                                   blue: unmatte(pixel.blue), alpha: alpha),
                           atX: x, y: y)
        }
    }
}

func removeStudioShadow(from image: NSBitmapImageRep) {
    let width = Double(image.pixelsWide)
    let height = Double(image.pixelsHigh)
    let radius = width * 0.17
    for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide {
            let px = Double(x) + 0.5
            let py = Double(y) + 0.5
            let cx = min(width - radius - 0.6, max(radius + 0.6, px))
            let cy = min(height - radius - 0.6, max(radius + 0.6, py))
            let coverage = min(1, max(0, radius + 0.5 - hypot(px - cx, py - cy)))
            let color = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            image.setColor(NSColor(deviceRed: color.redComponent, green: color.greenComponent,
                                   blue: color.blueComponent,
                                   alpha: color.alphaComponent * coverage), atX: x, y: y)
        }
    }
}

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
    // Keep the official PNG's native alpha; the JPEGs need their white matte
    // removed. Canvas sizes stay fixed so existing port anchors do not move.
    if source.hasSuffix(".jpg") {
        removeWhiteMatte(from: image, isIMac: asset.hasPrefix("iMac"))
        if asset == "MacStudioTop" { removeStudioShadow(from: image) }
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
