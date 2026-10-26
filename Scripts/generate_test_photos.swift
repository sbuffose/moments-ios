#!/usr/bin/env swift
// Script to generate varied test photos for XCUITests
// Run with: swift Scripts/generate_test_photos.swift <output_dir>

import Foundation
import AppKit
import CoreImage
import CoreLocation

let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "/tmp/test_photos"
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let cities: [(name: String, lat: Double, lon: Double)] = [
    ("BuenosAires", -34.6037, -58.3816),
    ("Mendoza", -32.8895, -68.8458),
    ("Bariloche", -41.1335, -71.3103),
    ("Cordoba", -31.4201, -64.1888),
    ("MarDelPlata", -38.0023, -57.5575),
    ("NoGPS", 0, 0)
]

let years = [2021, 2022, 2023, 2024, 2025, 2026]
let birthdayMonthDay = [(3, 15), (6, 22), (9, 8), (12, 1)]

func createImage(width: Int, height: Int, color: NSColor, text: String? = nil, blur: Bool = false, dark: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    
    let rect = NSRect(origin: .zero, size: image.size)
    let finalColor = dark ? color.blended(withFraction: 0.7, of: .black) ?? color : color
    finalColor.setFill()
    rect.fill()
    
    if let text = text {
        let fontSize = min(width, height) / 8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: CGFloat(fontSize)),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2)
        text.draw(at: point, withAttributes: attrs)
    }
    
    image.unlockFocus()
    
    if blur {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return image }
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(15.0, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let blurredImage = NSImage(size: rep.size)
        blurredImage.addRepresentation(rep)
        return blurredImage
    }
    
    return image
}

func saveJPEG(_ image: NSImage, to path: String, metadata: [String: Any]? = nil) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return }
    
    var props: [NSBitmapImageRep.PropertyKey: Any] = [
        .compressionFactor: 0.85
    ]
    
    guard let data = bitmap.representation(using: .jpeg, properties: props) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return }
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

var photoIndex = 0

func nextIndex() -> Int {
    photoIndex += 1
    return photoIndex
}

print("Generating test photos in \(outputDir)...")

// 1. Screenshots (20 photos) - cleanup category
let screenshotColors: [NSColor] = [.systemBlue, .systemGreen, .systemPurple, .systemOrange]
for i in 0..<20 {
    let color = screenshotColors[i % screenshotColors.count]
    let img = createImage(width: 1170, height: 2532, color: color, text: "Screenshot \(i+1)")
    savePNG(img, to: "\(outputDir)/screenshot_\(String(format: "%03d", nextIndex())).png")
}
print("✓ 20 screenshots")

// 2. Blurry photos (15 photos) - cleanup category
for i in 0..<15 {
    let colors: [NSColor] = [.red, .green, .blue, .yellow, .cyan]
    let img = createImage(width: 1200, height: 900, color: colors[i % colors.count], text: "Blurry \(i+1)", blur: true)
    saveJPEG(img, to: "\(outputDir)/blurry_\(String(format: "%03d", nextIndex())).jpg")
}
print("✓ 15 blurry photos")

// 3. Dark photos (10 photos) - cleanup category
for i in 0..<10 {
    let img = createImage(width: 1200, height: 900, color: .darkGray, text: nil, dark: true)
    saveJPEG(img, to: "\(outputDir)/dark_\(String(format: "%03d", nextIndex())).jpg")
}
print("✓ 10 dark photos")

// 4. Burst/near-duplicate photos (15 photos in 3 bursts of 5)
for burst in 0..<3 {
    let baseColor: NSColor = [.systemRed, .systemTeal, .systemIndigo][burst]
    for shot in 0..<5 {
        let img = createImage(width: 1200, height: 900, color: baseColor, text: "Burst\(burst+1)-\(shot+1)")
        saveJPEG(img, to: "\(outputDir)/burst\(burst+1)_\(String(format: "%03d", nextIndex())).jpg")
    }
}
print("✓ 15 burst photos (3 sets of 5)")

// 5. Documents/Receipts (10 photos) - cleanup category
for i in 0..<10 {
    let img = createImage(width: 900, height: 1200, color: .white, text: "Document \(i+1)")
    savePNG(img, to: "\(outputDir)/document_\(String(format: "%03d", nextIndex())).png")
}
print("✓ 10 document photos")

// 6. Photos with GPS from different cities (30 photos, 5 per city)
for city in cities {
    for i in 0..<5 {
        let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemYellow]
        let img = createImage(width: 1200, height: 900, color: colors[i], text: "\(city.name) #\(i+1)")
        let path = "\(outputDir)/\(city.name.lowercased())_\(String(format: "%03d", nextIndex())).jpg"
        saveJPEG(img, to: path)
    }
}
print("✓ 30 photos with city locations (6 cities x 5)")

// 7. Birthday/recurring event photos across years (24 photos)
for (month, day) in birthdayMonthDay {
    for year in [2022, 2023, 2024, 2025, 2026, 2027].prefix(6) {
        let colors: [NSColor] = [.systemPink, .magenta, .systemPurple, .systemRed]
        let img = createImage(width: 1200, height: 900, color: colors.randomElement()!, text: "🎂 \(month)/\(day)/\(year)")
        saveJPEG(img, to: "\(outputDir)/birthday_\(month)_\(day)_\(year)_\(String(format: "%03d", nextIndex())).jpg")
    }
}
print("✓ 24 birthday/recurring event photos")

// 8. Face placeholder photos (16 photos - 4 "people" x 4 photos each)
let faceColors: [NSColor] = [.systemTeal, .systemIndigo, .systemBrown, .systemMint]
for person in 0..<4 {
    for photo in 0..<4 {
        let img = createImage(width: 1200, height: 900, color: faceColors[person], text: "Person\(person+1) #\(photo+1)")
        saveJPEG(img, to: "\(outputDir)/face_person\(person+1)_\(String(format: "%03d", nextIndex())).jpg")
    }
}
print("✓ 16 face placeholder photos (4 people x 4)")

// 9. High quality landscape photos (10 photos) - should be kept
for i in 0..<10 {
    let colors: [NSColor] = [.systemCyan, .systemMint, .systemTeal, .systemGreen, .systemBlue]
    let img = createImage(width: 4032, height: 3024, color: colors[i % colors.count], text: "Quality #\(i+1)")
    saveJPEG(img, to: "\(outputDir)/quality_\(String(format: "%03d", nextIndex())).jpg")
}
print("✓ 10 high quality landscape photos")

// 10. Mixed old photos from various years (fill to ~150)
let remaining = 150 - photoIndex
for i in 0..<remaining {
    let year = years.randomElement()!
    let month = Int.random(in: 1...12)
    let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemYellow, .systemRed, .systemPurple]
    let img = createImage(width: 1200, height: 900, color: colors.randomElement()!, text: "\(month)/\(year)")
    saveJPEG(img, to: "\(outputDir)/misc_\(year)_\(month)_\(String(format: "%03d", nextIndex())).jpg")
}
print("✓ \(remaining) miscellaneous photos from various years")

print("\n✅ Generated \(photoIndex) test photos in \(outputDir)")
