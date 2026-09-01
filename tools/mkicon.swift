// Renders Resources/logo.svg's geometry into a 1024px app icon. No design tool
// needed, and no image asset to drift out of sync -- the numbers below are the same
// ones in the SVG's comment header, at 2x. Change one, change both.
//
// Verified against the SVG by pixel diff: every filled region lands identically and
// the only differences are a 1px antialiased edge, which is inherent to rasterising
// the same geometry through two different engines.
import AppKit
import Foundation

let S = 1024.0
let scale = S / 512.0                     // the SVG's viewBox

let storm = NSColor(srgbRed: 0x24/255.0, green: 0x28/255.0, blue: 0x3b/255.0, alpha: 1)
let dawn  = NSColor(srgbRed: 0xf2/255.0, green: 0xe9/255.0, blue: 0xe1/255.0, alpha: 1)
let iris  = NSColor(srgbRed: 0x90/255.0, green: 0x7a/255.0, blue: 0xa9/255.0, alpha: 1)

let blades = 6
let rake   = 0.62                         // radians off-radius; this is the mark
let rOut   = 152.0 * scale
let rIn    =  58.0 * scale
let seamW  =  17.0 * scale
let c      = S / 2

// AppKit's y axis points up and SVG's points down, so sin is negated to keep the
// rake turning the same way it does in the SVG.
func pt(_ r: Double, _ a: Double) -> NSPoint {
    NSPoint(x: c + r * cos(a), y: c - r * sin(a))
}

let out = NSImage(size: NSSize(width: S, height: S))
out.lockFocus()

let tile = NSBezierPath(roundedRect: NSRect(x: 32 * scale, y: 32 * scale,
                                            width: 448 * scale, height: 448 * scale),
                        xRadius: 116 * scale, yRadius: 116 * scale)
tile.addClip()

storm.setFill()
NSRect(x: 0, y: 0, width: S, height: S).fill()

iris.setFill()
NSBezierPath(ovalIn: NSRect(x: c - rOut, y: c - rOut, width: rOut * 2, height: rOut * 2)).fill()

// the opening
let opening = NSBezierPath()
for i in 0..<blades {
    let a = 2 * Double.pi * Double(i) / Double(blades) - Double.pi / 2
    let p = pt(rIn, a)
    i == 0 ? opening.move(to: p) : opening.line(to: p)
}
opening.close()
dawn.setFill()
opening.fill()

// the seams, raked so the mark reads as rotating rather than as a star
storm.setStroke()
for i in 0..<blades {
    let a = 2 * Double.pi * Double(i) / Double(blades) - Double.pi / 2
    let seam = NSBezierPath()
    seam.move(to: pt(rIn, a))
    seam.line(to: pt(rOut, a + rake))
    seam.lineWidth = seamW
    seam.lineCapStyle = .round
    seam.stroke()
}

out.unlockFocus()

guard let tiff = out.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
