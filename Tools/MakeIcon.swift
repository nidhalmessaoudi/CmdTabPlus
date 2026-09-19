import AppKit

let destination = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.39, alpha: 1).setFill(); base.fill()
        let left = NSBezierPath(roundedRect: NSRect(x: 180, y: 320, width: 392, height: 384), xRadius: 64, yRadius: 64)
        NSColor.white.withAlphaComponent(0.94).setFill(); left.fill()
        let right = NSBezierPath(roundedRect: NSRect(x: 596, y: 320, width: 252, height: 384), xRadius: 48, yRadius: 48)
        NSColor.white.withAlphaComponent(0.22).setFill(); right.fill()
        let symbol = "⌘" as NSString
        symbol.draw(in: NSRect(x: 221, y: 362, width: 320, height: 320), withAttributes: [.font: NSFont.systemFont(ofSize: 264, weight: .regular), .foregroundColor: NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.39, alpha: 1)])
        for y in [420, 504, 588] {
            let line = NSBezierPath(roundedRect: NSRect(x: 640, y: y, width: 164, height: 28), xRadius: 14, yRadius: 14)
            NSColor.white.withAlphaComponent(y == 504 ? 1 : 0.45).setFill(); line.fill()
        }
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
