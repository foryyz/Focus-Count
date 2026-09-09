import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Keep the supplied artwork intact; only resize and convert to opaque PNG.
let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("assets/app-icon.jpg")
let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
let original = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high
context.draw(original, in: CGRect(x: 0, y: 0, width: size, height: size))
let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
    UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output))
