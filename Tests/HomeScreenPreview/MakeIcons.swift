// Screenshot fixture art only. Never included in the production app or release IPA.
import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let symbols = ["doc.text.fill", "camera.fill", "music.note", "map.fill", "book.closed.fill", "waveform", "pencil.tip", "paperplane.fill", "folder.fill", "calendar", "photo.fill", "play.fill"]
let colors: [NSColor] = [.systemOrange, .systemGray, .systemPink, .systemGreen, .systemBrown, .systemPurple,
                         .systemTeal, .systemBlue, .systemIndigo, .systemRed, .systemYellow, .systemMint]
for (index, symbol) in symbols.enumerated() {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    colors[index].setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 180, height: 180)).fill()
    if let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 84, weight: .medium)) {
        icon.draw(in: NSRect(x: 44, y: 44, width: 92, height: 92))
        NSColor.white.setFill()
        NSRect(x: 44, y: 44, width: 92, height: 92).fill(using: .sourceAtop)
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(index).png"))
}
