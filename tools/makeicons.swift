// Gera o ícone do app (AppIcon.icns) e os ícones template da barra de menu.
// Uso: makeicons <pasta Resources>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "."
let fm = FileManager.default

func png(_ image: NSImage, _ path: String) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { fatalError("png \(path)") }
    try! data.write(to: URL(fileURLWithPath: path))
}

/// Ícone do app: quadrado arredondado com gradiente, lente circular e um "gimbal" por baixo.
func appIcon(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let inset = s * 0.05
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.36, alpha: 1),
                        NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.70, alpha: 1),
                        NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.40, alpha: 1)])!
        .draw(in: bg, angle: 60)
    // brilho sutil no topo
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: NSRect(x: inset, y: s * 0.55, width: s - 2 * inset, height: s * 0.40 - inset), xRadius: s * 0.22, yRadius: s * 0.22).fill()

    let cx = s / 2, cy = s * 0.56
    // haste e base do gimbal
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: NSRect(x: cx - s * 0.035, y: s * 0.16, width: s * 0.07, height: s * 0.22), xRadius: s * 0.035, yRadius: s * 0.035).fill()
    NSBezierPath(roundedRect: NSRect(x: cx - s * 0.17, y: s * 0.12, width: s * 0.34, height: s * 0.07), xRadius: s * 0.035, yRadius: s * 0.035).fill()
    // arco do gimbal
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: s * 0.30, startAngle: 200, endAngle: 340)
    arc.lineWidth = s * 0.055; arc.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.92).setStroke(); arc.stroke()
    // corpo da câmera (lente)
    let body = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.22, y: cy - s * 0.22, width: s * 0.44, height: s * 0.44))
    NSColor.white.setFill(); body.fill()
    let lens = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.15, y: cy - s * 0.15, width: s * 0.30, height: s * 0.30))
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.22, alpha: 1).setFill(); lens.fill()
    let iris = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.085, y: cy - s * 0.085, width: s * 0.17, height: s * 0.17))
    NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.95, alpha: 1).setFill(); iris.fill()
    let glint = NSBezierPath(ovalIn: NSRect(x: cx + s * 0.02, y: cy + s * 0.05, width: s * 0.06, height: s * 0.06))
    NSColor.white.withAlphaComponent(0.9).setFill(); glint.fill()
    img.unlockFocus()
    return img
}

/// Ícone da barra de menu (template, preto com alpha): lente sobre um arco de gimbal.
func menuIcon(_ size: CGFloat, off: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size, cx = s / 2, cy = s * 0.58
    NSColor.black.setStroke(); NSColor.black.setFill()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: s * 0.40, startAngle: 205, endAngle: 335)
    arc.lineWidth = s * 0.10; arc.lineCapStyle = .round; arc.stroke()
    NSBezierPath(roundedRect: NSRect(x: cx - s * 0.05, y: s * 0.04, width: s * 0.10, height: s * 0.18), xRadius: s * 0.05, yRadius: s * 0.05).fill()
    let ring = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.27, y: cy - s * 0.27, width: s * 0.54, height: s * 0.54))
    ring.lineWidth = s * 0.10; ring.stroke()
    if off {
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: cx - s * 0.36, y: cy - s * 0.36)); slash.line(to: NSPoint(x: cx + s * 0.36, y: cy + s * 0.36))
        slash.lineWidth = s * 0.10; slash.lineCapStyle = .round; slash.stroke()
    } else {
        NSBezierPath(ovalIn: NSRect(x: cx - s * 0.11, y: cy - s * 0.11, width: s * 0.22, height: s * 0.22)).fill()
    }
    img.unlockFocus()
    img.isTemplate = true
    return img
}

let iconset = outDir + "/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    png(appIcon(CGFloat(px)), "\(iconset)/icon_\(name).png")
}
png(appIcon(1024), outDir + "/AppIcon-1024.png")
png(menuIcon(18, off: false), outDir + "/MenuIcon.png")
png(menuIcon(36, off: false), outDir + "/MenuIcon@2x.png")
png(menuIcon(18, off: true), outDir + "/MenuIconOff.png")
png(menuIcon(36, off: true), outDir + "/MenuIconOff@2x.png")
print("ícones gerados em \(outDir)")
