import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let background = NSBezierPath(
        roundedRect: NSRect(x: 45, y: 45, width: 934, height: 934), xRadius: 215, yRadius: 215)
    NSColor(srgbRed: 0.11, green: 0.36, blue: 0.63, alpha: 1).setFill()
    background.fill()
    let orbit = NSBezierPath()
    orbit.appendArc(
        withCenter: NSPoint(x: 492, y: 500), radius: 246, startAngle: 32, endAngle: 330, clockwise: false)
    orbit.lineWidth = 56
    orbit.lineCapStyle = .round
    NSColor.white.setStroke()
    orbit.stroke()
    let star = NSBezierPath()
    let center = NSPoint(x: 662, y: 650)
    let points: [NSPoint] = [
        NSPoint(x: center.x, y: center.y + 130), NSPoint(x: center.x + 35, y: center.y + 35),
        NSPoint(x: center.x + 130, y: center.y), NSPoint(x: center.x + 35, y: center.y - 35),
        NSPoint(x: center.x, y: center.y - 130), NSPoint(x: center.x - 35, y: center.y - 35),
        NSPoint(x: center.x - 130, y: center.y), NSPoint(x: center.x - 35, y: center.y + 35),
    ]
    star.move(to: points[0])
    for point in points.dropFirst() { star.line(to: point) }
    star.close()
    NSColor.white.setFill()
    star.fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else { fatalError("Icon rendering failed") }
    let names: [String] =
        switch size {
        case 16: ["icon_16x16.png"]
        case 32: ["icon_16x16@2x.png", "icon_32x32.png"]
        case 64: ["icon_32x32@2x.png"]
        case 128: ["icon_128x128.png"]
        case 256: ["icon_128x128@2x.png", "icon_256x256.png"]
        case 512: ["icon_256x256@2x.png", "icon_512x512.png"]
        default: ["icon_512x512@2x.png"]
        }
    for name in names { try png.write(to: output.appendingPathComponent(name)) }
}
