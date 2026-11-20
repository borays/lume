import AppKit

// 微光 / Lume 品牌图标生成器
// 用法: make_icon.swift light|dark|menubar <输出.png>

enum Mode {
    case light
    case dark
    case menubar
}

let modeArg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "light"
let output = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "lume-icon.png"
let mode: Mode
switch modeArg {
case "dark": mode = .dark
case "menubar": mode = .menubar
default: mode = .light

}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

func drawArcPath(center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: false
    )
    return path
}

let image: NSImage

switch mode {
case .menubar:
    // 16px 精简版：只保留一小段微光圆弧
    let size = 64.0
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    let arc = drawArcPath(
        center: NSPoint(x: 32, y: 29),
        radius: 19,
        startAngle: 35,
        endAngle: 145
    )
    arc.lineWidth = 8.5
    arc.lineCapStyle = .round
    NSColor.black.setStroke()
    arc.stroke()

    img.unlockFocus()
    image = img

case .light, .dark:
    let size = 1024.0
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let isDark = mode == .dark
    let line = isDark ? color(0xD6D6D8) : color(0x2B2B2E)      // 深炭灰 / 浅灰线条
    let glow = isDark ? color(0xF0E6D2) : color(0xD4A24E)      // 暖米白光 / 低饱和琥珀
    let plate = isDark ? color(0x1E1E20) : color(0xF5F4F0)     // 底板

    // mac 标准圆角矩形底板
    let plateRect = NSRect(x: 40, y: 40, width: size - 80, height: size - 80)
    let platePath = NSBezierPath(roundedRect: plateRect, xRadius: 228, yRadius: 228)
    plate.setFill()
    platePath.fill()

    let stroke: CGFloat = 40

    // 下半部分：极简线条文档轮廓 + 几横细线代表文本
    let docRect = NSRect(x: 302, y: 152, width: 420, height: 318)
    let doc = NSBezierPath(roundedRect: docRect, xRadius: 46, yRadius: 46)
    doc.lineWidth = stroke
    line.setStroke()
    doc.stroke()

    let lineWidths: [CGFloat] = [300, 300, 176]
    for (index, width) in lineWidths.enumerated() {
        let y = 360.0 - Double(index) * 80
        let lineRect = NSRect(x: 360, y: y, width: width, height: stroke)
        let bar = NSBezierPath(roundedRect: lineRect, xRadius: stroke / 2, yRadius: stroke / 2)
        line.setFill()
        bar.fill()
    }

    // 上半部分：柔和向上的微光弧
    let halo = drawArcPath(
        center: NSPoint(x: 512, y: 474),
        radius: 264,
        startAngle: 28,
        endAngle: 152
    )
    halo.lineWidth = stroke
    halo.lineCapStyle = .round
    glow.setStroke()
    halo.stroke()

    img.unlockFocus()
    image = img
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
