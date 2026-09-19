#!/usr/bin/env swift
// scripts/flatten-app-icon.swift — turns a Figma screenshot of an icon (from
// scripts/fetch-app-icons.sh) into the pixels the catalog wants.
//
//   swift scripts/flatten-app-icon.swift <in.png> <icon-1024.png> [preview-256.png] [mark-512.png]
//
// The screenshot is the icon's rounded rectangle standing on the section's grey canvas with a
// margin round it, so it is cropped to the rectangle first. iOS masks the icon itself, so its
// corners never show on the phone; but App Store Connect rejects an icon with an alpha channel
// (ITMS-90717), and a corner left as canvas grey would show on any surface that draws the raw
// square. So the crop is masked to its own corner radius (measured off the top row), drawn once at
// 1.6× behind itself — which puts its corners outside the frame and its border colours under the
// corners — and then once at 1:1 on top, into an opaque RGB square. The preview and the mark are
// the same square at 256 and 512, for the Appearance grid and the Import hub's ring; both clip to
// a squircle when drawn.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: flatten-app-icon.swift <in.png> <icon-1024.png> [preview-256.png] [mark-512.png]\n".data(using: .utf8)!)
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Read the pixels in one known layout (RGBA8, top row first)

let width = image.width, height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
do {
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Core Graphics draws bottom-up; flip so row 0 of `pixels` is the top of the picture.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}
func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * width + x) * 4
    return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
}
/// Whether a pixel is the canvas: within a few levels of the top-left corner's colour, or clear.
let canvas = pixel(1, 1)
func isCanvas(_ x: Int, _ y: Int) -> Bool {
    let p = pixel(x, y)
    if p.3 < 8 { return true }
    return abs(Int(p.0) - Int(canvas.0)) < 12 && abs(Int(p.1) - Int(canvas.1)) < 12 && abs(Int(p.2) - Int(canvas.2)) < 12
}

// MARK: - The icon's bounds, and its corner radius off the top row

var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where !isCanvas(x, y) {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else { FileHandle.standardError.write("no icon found on the canvas\n".data(using: .utf8)!); exit(1) }
let side = max(maxX - minX + 1, maxY - minY + 1)
let firstOnTopRow = (minX...maxX).first { !isCanvas($0, minY) } ?? minX
let radiusFraction = Double(firstOnTopRow - minX) / Double(side)
print("icon: \(side)×\(side) at (\(minX), \(minY)) of \(width)×\(height); corner ≈ \(Int(radiusFraction * 1000) / 10)% of the side (iOS masks at 22.4%)")

// MARK: - The crop, its corners cut away along its own outline

// Not a drawn arc: Figma's corner is a smoothed curve, not a circle, and a circle wide enough to
// clear the canvas at the edge would bite into the picture along the diagonal. Each row keeps the
// span between its first and last non-canvas pixel and loses the rest, which follows the curve
// exactly, to the anti-aliased pixel.
let masked: CGImage = {
    var out = [UInt8](repeating: 0, count: side * side * 4)
    for y in 0..<side {
        let row = minY + y
        guard let left = (minX..<minX + side).first(where: { !isCanvas($0, row) }),
              let right = (minX..<minX + side).last(where: { !isCanvas($0, row) }) else { continue }
        for x in left...right {
            let src = (row * width + minX + (x - minX)) * 4
            let dst = (y * side + (x - minX)) * 4
            out[dst] = pixels[src]; out[dst + 1] = pixels[src + 1]; out[dst + 2] = pixels[src + 2]; out[dst + 3] = 255
        }
    }
    let context = CGContext(data: &out, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // `pixels` is top row first, Core Graphics' image is bottom row first: flip it back.
    let upsideDown = context.makeImage()!
    let flip = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    flip.translateBy(x: 0, y: CGFloat(side))
    flip.scaleBy(x: 1, y: -1)
    flip.draw(upsideDown, in: CGRect(x: 0, y: 0, width: side, height: side))
    return flip.makeImage()!
}()

// MARK: - Opaque squares

func flattened(_ size: Int) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    let s = CGFloat(size)
    let big = s * 1.6
    context.draw(masked, in: CGRect(x: (s - big) / 2, y: (s - big) / 2, width: big, height: big))
    context.draw(masked, in: CGRect(x: 0, y: 0, width: s, height: s))
    return context.makeImage()!
}

func write(_ cgImage: CGImage, to path: String) {
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write("cannot write \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    print("wrote \(path) \(cgImage.width)×\(cgImage.height)")
}

write(flattened(1024), to: args[2])
if args.count > 3 { write(flattened(256), to: args[3]) }
if args.count > 4 { write(flattened(512), to: args[4]) }
