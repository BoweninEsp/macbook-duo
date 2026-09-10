import AppKit
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size: Int) -> CGImage {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let inset = s * 0.045
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bg, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
    ctx.clip()
    let grad = CGGradient(colorsSpace: colorSpace, colors: [
        NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.12, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.11, green: 0.18, blue: 0.28, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.035, green: 0.05, blue: 0.085, alpha: 1).cgColor
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // Screen glow behind the silhouette.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.075, color: NSColor(calibratedRed: 0.25, green: 0.78, blue: 1, alpha: 0.6).cgColor)
    let screen = CGMutablePath()
    screen.move(to: CGPoint(x: s * 0.46, y: s * 0.58))
    screen.addLine(to: CGPoint(x: s * 0.285, y: s * 0.23))
    screen.addLine(to: CGPoint(x: s * 0.36, y: s * 0.185))
    screen.addLine(to: CGPoint(x: s * 0.59, y: s * 0.54))
    screen.closeSubpath()
    ctx.addPath(screen); ctx.setFillColor(NSColor(calibratedRed: 0.18, green: 0.7, blue: 0.95, alpha: 0.9).cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Matte aluminum screen frame and dark glass.
    ctx.addPath(screen); ctx.setFillColor(NSColor(calibratedWhite: 0.78, alpha: 1).cgColor); ctx.fillPath()
    let glass = CGMutablePath()
    glass.move(to: CGPoint(x: s * 0.445, y: s * 0.535))
    glass.addLine(to: CGPoint(x: s * 0.32, y: s * 0.255))
    glass.addLine(to: CGPoint(x: s * 0.355, y: s * 0.235))
    glass.addLine(to: CGPoint(x: s * 0.535, y: s * 0.515))
    glass.closeSubpath()
    ctx.addPath(glass); ctx.setFillColor(NSColor(calibratedRed: 0.035, green: 0.12, blue: 0.18, alpha: 1).cgColor); ctx.fillPath()
    // Bright inner screen sliver.
    ctx.addPath(glass); ctx.setStrokeColor(NSColor(calibratedRed: 0.48, green: 0.9, blue: 1, alpha: 0.75).cgColor); ctx.setLineWidth(s * 0.012); ctx.strokePath()

    // Base: low side-profile wedge.
    let base = CGMutablePath()
    base.move(to: CGPoint(x: s * 0.2, y: s * 0.64))
    base.addLine(to: CGPoint(x: s * 0.48, y: s * 0.575))
    base.addLine(to: CGPoint(x: s * 0.78, y: s * 0.64))
    base.addLine(to: CGPoint(x: s * 0.88, y: s * 0.69))
    base.addLine(to: CGPoint(x: s * 0.17, y: s * 0.69))
    base.closeSubpath()
    ctx.addPath(base); ctx.setFillColor(NSColor(calibratedWhite: 0.68, alpha: 1).cgColor); ctx.fillPath()
    let top = CGMutablePath()
    top.move(to: CGPoint(x: s * 0.2, y: s * 0.64)); top.addLine(to: CGPoint(x: s * 0.78, y: s * 0.64)); top.addLine(to: CGPoint(x: s * 0.82, y: s * 0.66)); top.addLine(to: CGPoint(x: s * 0.17, y: s * 0.66)); top.closeSubpath()
    ctx.addPath(top); ctx.setFillColor(NSColor(calibratedWhite: 0.9, alpha: 1).cgColor); ctx.fillPath()
    ctx.setStrokeColor(NSColor(calibratedWhite: 0.4, alpha: 0.8).cgColor); ctx.setLineWidth(s * 0.008); ctx.addPath(base); ctx.strokePath()
    return ctx.makeImage()!
}

for (name, px) in [("16x16",16),("32x32",32),("128x128",128),("256x256",256),("512x512",512)] {
    for scale in [1,2] where px * scale <= 1024 {
        let actual = px * scale
        let file = iconset.appendingPathComponent("icon_\(name)\(scale == 2 ? "@2x" : "").png")
        let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, draw(size: actual), nil)
        CGImageDestinationFinalize(dest)
    }
}
print(iconset.path)
