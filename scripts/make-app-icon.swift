#!/usr/bin/env swift
// scripts/make-app-icon.swift — draws the app icon. Run: `swift scripts/make-app-icon.swift [output.png]`.
// The design lives here so it can be tuned in code: the accent (`Tokens.accent`, #FF7A1A, spec
// §2.4.2) as the ground, three white bars for a block of text, a play triangle for the speech.
// Deterministic: the same pixels every run, so the committed PNG is reproducible.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no bitmap context")
}
// Core Graphics' origin is bottom-left; flip so the geometry below reads top-down like a design file.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

let accent = CGColor(colorSpace: space, components: [0xFF / 255.0, 0x7A / 255.0, 0x1A / 255.0, 1])!
let white = CGColor(colorSpace: space, components: [1, 1, 1, 1])!
context.setFillColor(accent)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

context.setFillColor(white)
for (centerY, width) in [(356, 560), (476, 440), (596, 320)] {
    let bar = CGRect(x: 232, y: centerY - 36, width: width, height: 72)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: 36, cornerHeight: 36, transform: nil))
    context.fillPath()
}
let triangle = CGMutablePath()
triangle.move(to: CGPoint(x: 632, y: 560))
triangle.addLine(to: CGPoint(x: 632, y: 720))
triangle.addLine(to: CGPoint(x: 792, y: 640))
triangle.closeSubpath()
context.addPath(triangle)
context.fillPath()

guard let image = context.makeImage() else { fatalError("no image") }
let defaultOutput = "App/T2SReader/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? defaultOutput)
try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("cannot write \(output.path)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG encoding failed") }
print("wrote \(output.path)")
