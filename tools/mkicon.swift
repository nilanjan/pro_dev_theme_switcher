// Renders the menu bar glyph into a 1024px app icon. No design tool needed.
import AppKit

let S = 1024.0
let storm = NSColor(srgbRed: 0x24/255.0, green: 0x28/255.0, blue: 0x3b/255.0, alpha: 1) // Tokyo Night Storm bg
let dawn  = NSColor(srgbRed: 0xfa/255.0, green: 0xf4/255.0, blue: 0xed/255.0, alpha: 1) // Rosé Pine Dawn base

let out = NSImage(size: NSSize(width: S, height: S))
out.lockFocus()
storm.setFill()
NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: S-160, height: S-160),
             xRadius: 190, yRadius: 190).fill()

let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .light)
if let sym = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    dawn.set()
    NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: (S - sym.size.width)/2, y: (S - sym.size.height)/2,
                           width: sym.size.width, height: sym.size.height))
}
out.unlockFocus()

guard let tiff = out.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
