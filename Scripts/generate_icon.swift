// One-off tool: renders AppIcon.icns from an SF Symbol onto a gradient rounded-square.
// Run with: swift Scripts/generate_icon.swift
import AppKit

let sizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

func makeIcon(pixelSize: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let cornerRadius = CGFloat(pixelSize) * 0.2237 // matches macOS "squircle" convention closely enough
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.29, green: 0.20, blue: 0.90, alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -90)

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.52, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let symSize = tinted.size
        let origin = NSPoint(x: (CGFloat(pixelSize) - symSize.width) / 2, y: (CGFloat(pixelSize) - symSize.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

let fm = FileManager.default
let iconsetPath = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, scale) in sizes {
    let pixelSize = size * scale
    let image = makeIcon(pixelSize: pixelSize)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let suffix = scale == 2 ? "@2x" : ""
    let filename = "icon_\(size)x\(size)\(suffix).png"
    try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
}

print("Wrote iconset to \(iconsetPath)")
