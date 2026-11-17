// Renders lyric screens to PNG files: swift render-lyric-screens.swift <output-folder> <screen text> [<screen text>...]
// An empty screen text renders a plain background (used for the "no text" fixture).
import AppKit

let arguments = CommandLine.arguments.dropFirst()
guard let outputFolder = arguments.first else { fatalError("usage: <output-folder> <screen>...") }
let screens = Array(arguments.dropFirst())
let canvasSize = NSSize(width: 640, height: 360)

for (index, screenText) in screens.enumerated() {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width), pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.08, green: 0.1, blue: 0.2, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 8
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let text = screenText.replacingOccurrences(of: "|", with: "\n") as NSString
    let textHeight = text.boundingRect(with: NSSize(width: 580, height: 300), options: .usesLineFragmentOrigin, attributes: attributes).height
    text.draw(in: NSRect(x: 30, y: (canvasSize.height - textHeight) / 2, width: 580, height: textHeight), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()

    let fileURL = URL(fileURLWithPath: outputFolder).appendingPathComponent(String(format: "screen-%02d.png", index))
    try! bitmap.representation(using: .png, properties: [:])!.write(to: fileURL)
}
