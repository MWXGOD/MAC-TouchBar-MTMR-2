import AppKit
import Foundation

let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets")

func render(_ name: String, to path: String) {
    let image = NSImage(named: name)!
    let size = NSSize(width: 38, height: 30)
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()
    let source = NSRect(x: (size.width - image.size.width) / 2,
                        y: (size.height - image.size.height) / 2,
                        width: image.size.width,
                        height: image.size.height)
    image.draw(in: source, from: .zero, operation: .sourceOver, fraction: 1)
    canvas.unlockFocus()

    let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    rep.bitmapFormat = rep.bitmapFormat.union(.alphaFirst)
    let bytes = rep.bitmapData!
    for index in stride(from: 0, to: rep.bytesPerRow * rep.pixelsHigh, by: 4) {
        let alpha = bytes[index]
        bytes[index] = alpha
        bytes[index + 1] = 255
        bytes[index + 2] = 255
        bytes[index + 3] = 255
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(NSImage.touchBarRewindTemplateName, to: projectDirectory.appendingPathComponent("touchbar-previous.png").path)
render(NSImage.touchBarPlayPauseTemplateName, to: projectDirectory.appendingPathComponent("touchbar-play.png").path)
render(NSImage.touchBarFastForwardTemplateName, to: projectDirectory.appendingPathComponent("touchbar-next.png").path)
