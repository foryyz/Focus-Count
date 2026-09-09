import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let colors = [CGColor(red: 0.10, green: 0.35, blue: 0.33, alpha: 1), CGColor(red: 0.045, green: 0.13, blue: 0.17, alpha: 1)]
let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let mint = CGColor(red: 0.75, green: 0.95, blue: 0.85, alpha: 1)
context.setStrokeColor(mint); context.setFillColor(mint)
context.setLineWidth(24); context.setLineCap(.round)
context.addArc(center: CGPoint(x: 512, y: 494), radius: 276, startAngle: 80 * .pi / 180, endAngle: 410 * .pi / 180, clockwise: false)
context.strokePath()
context.setLineWidth(30); context.setLineJoin(.round)
context.move(to: CGPoint(x: 512, y: 664)); context.addLine(to: CGPoint(x: 512, y: 494)); context.addLine(to: CGPoint(x: 620, y: 418)); context.strokePath()
context.fillEllipse(in: CGRect(x: 633, y: 719, width: 56, height: 56))
let image = context.makeImage()!
let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, image, nil)
precondition(CGImageDestinationFinalize(output))
