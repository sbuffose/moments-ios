#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    print("Failed to create context")
    exit(1)
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Draw dark gradient background
let gradientColors = [
    CGColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0),
    CGColor(red: 0.12, green: 0.10, blue: 0.20, alpha: 1.0),
    CGColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1.0)
]

guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors as CFArray,
    locations: [0.0, 0.5, 1.0]
) else {
    print("Failed to create gradient")
    exit(1)
}

context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size), y: 0),
    options: []
)

// Draw subtle glow in center
let glowCenter = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
let glowRadius = CGFloat(size) * 0.4

let glowColors = [
    CGColor(red: 0.4, green: 0.3, blue: 0.8, alpha: 0.3),
    CGColor(red: 0.3, green: 0.2, blue: 0.6, alpha: 0.0)
]

if let glowGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: glowColors as CFArray,
    locations: [0.0, 1.0]
) {
    context.drawRadialGradient(
        glowGradient,
        startCenter: glowCenter,
        startRadius: 0,
        endCenter: glowCenter,
        endRadius: glowRadius,
        options: []
    )
}

// Draw stylized photo frame
let frameSize = CGFloat(size) * 0.5
let frameX = (CGFloat(size) - frameSize) / 2 - 40
let frameY = (CGFloat(size) - frameSize) / 2 - 40
let cornerRadius: CGFloat = 60

let framePath = CGPath(
    roundedRect: CGRect(x: frameX, y: frameY, width: frameSize, height: frameSize),
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

context.setFillColor(CGColor(red: 0.2, green: 0.15, blue: 0.35, alpha: 0.8))
context.addPath(framePath)
context.fillPath()

context.setStrokeColor(CGColor(red: 0.5, green: 0.4, blue: 0.8, alpha: 0.6))
context.setLineWidth(4)
context.addPath(framePath)
context.strokePath()

// Draw second frame (offset)
let frame2Size = CGFloat(size) * 0.45
let frame2X = (CGFloat(size) - frame2Size) / 2 + 50
let frame2Y = (CGFloat(size) - frame2Size) / 2 + 50

let frame2Path = CGPath(
    roundedRect: CGRect(x: frame2X, y: frame2Y, width: frame2Size, height: frame2Size),
    cornerWidth: cornerRadius * 0.9,
    cornerHeight: cornerRadius * 0.9,
    transform: nil
)

context.setFillColor(CGColor(red: 0.15, green: 0.12, blue: 0.28, alpha: 0.9))
context.addPath(frame2Path)
context.fillPath()

context.setStrokeColor(CGColor(red: 0.6, green: 0.5, blue: 0.9, alpha: 0.7))
context.setLineWidth(3)
context.addPath(frame2Path)
context.strokePath()

// Draw sparkle/star marks
func drawSparkle(at center: CGPoint, size sparkleSize: CGFloat, color: CGColor) {
    let points = 4
    let innerRadius = sparkleSize * 0.3
    let outerRadius = sparkleSize
    
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    
    let path = CGMutablePath()
    for i in 0..<(points * 2) {
        let radius = i % 2 == 0 ? outerRadius : innerRadius
        let angle = CGFloat(i) * .pi / CGFloat(points)
        let x = radius * cos(angle - .pi / 2)
        let y = radius * sin(angle - .pi / 2)
        
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    
    context.setFillColor(color)
    context.addPath(path)
    context.fillPath()
    
    context.restoreGState()
}

// Main sparkle
drawSparkle(
    at: CGPoint(x: CGFloat(size) * 0.75, y: CGFloat(size) * 0.25),
    size: 80,
    color: CGColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1.0)
)

// Small sparkles
drawSparkle(
    at: CGPoint(x: CGFloat(size) * 0.85, y: CGFloat(size) * 0.35),
    size: 35,
    color: CGColor(red: 0.9, green: 0.8, blue: 1.0, alpha: 0.8)
)

drawSparkle(
    at: CGPoint(x: CGFloat(size) * 0.20, y: CGFloat(size) * 0.80),
    size: 45,
    color: CGColor(red: 0.7, green: 0.6, blue: 1.0, alpha: 0.7)
)

// Save the image
guard let cgImage = context.makeImage() else {
    print("Failed to create image")
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("Failed to create destination")
    exit(1)
}

CGImageDestinationAddImage(destination, cgImage, nil)

if CGImageDestinationFinalize(destination) {
    print("App icon generated: \(outputPath)")
} else {
    print("Failed to write image")
    exit(1)
}
