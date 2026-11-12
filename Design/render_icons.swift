// Vẽ 3 phương án icon phong cách liquid glass (1024x1024) + ảnh so sánh.
// Chạy: swift Design/render_icons.swift
import AppKit

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func linear(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
    ctx.restoreGState()
}

func radial(_ ctx: CGContext, clip: CGPath, center: CGPoint, radius: CGFloat, color: CGColor) {
    ctx.saveGState(); ctx.addPath(clip); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// Một tấm kính: màu tint trong suốt, bóng mềm, sheen trên, phản quang, viền sáng.
func glass(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, tint: UInt32, alpha: CGFloat = 0.62) {
    let p = rr(r, radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 22), blur: 46, color: c(0x2B3A55, 0.22))
    ctx.addPath(p); ctx.setFillColor(c(tint, alpha)); ctx.fillPath()
    ctx.restoreGState()
    // độ sâu: dưới đậm hơn một chút
    linear(ctx, p, [c(0xFFFFFF, 0.50), c(0xFFFFFF, 0.08), c(tint, 0.35)],
           from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: r.maxY))
    // phản quang góc trên trái
    radial(ctx, clip: p, center: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.12),
           radius: max(r.width, r.height) * 0.55, color: c(0xFFFFFF, 0.45))
    // viền sáng
    ctx.saveGState()
    ctx.addPath(rr(r.insetBy(dx: 2, dy: 2), radius - 2))
    ctx.setStrokeColor(c(0xFFFFFF, 0.85)); ctx.setLineWidth(4); ctx.strokePath()
    ctx.restoreGState()
    // vệt sáng mảnh ở mép trên
    ctx.saveGState()
    ctx.addPath(rr(CGRect(x: r.minX + radius * 0.6, y: r.minY + 10, width: r.width - radius * 1.2, height: 7), 3.5))
    ctx.setFillColor(c(0xFFFFFF, 0.75)); ctx.fillPath()
    ctx.restoreGState()
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185

func background(_ ctx: CGContext, top: UInt32, bottom: UInt32, blobs: [(CGPoint, CGFloat, UInt32)]) {
    let p = rr(body, bodyRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: c(0x1C2433, 0.25))
    ctx.addPath(p); ctx.setFillColor(c(bottom)); ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, p, [c(top), c(bottom)], from: CGPoint(x: body.minX, y: body.minY), to: CGPoint(x: body.maxX, y: body.maxY))
    for (center, radius, color) in blobs { radial(ctx, clip: p, center: center, radius: radius, color: c(color, 0.55)) }
    ctx.saveGState()
    ctx.addPath(rr(body.insetBy(dx: 3, dy: 3), bodyRadius - 3))
    ctx.setStrokeColor(c(0xFFFFFF, 0.7)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.restoreGState()
}

func iconA(_ ctx: CGContext) {
    background(ctx, top: 0xFCF8F1, bottom: 0xEDE3D3,
               blobs: [(CGPoint(x: 300, y: 820), 380, 0xC9DEC3), (CGPoint(x: 820, y: 260), 360, 0xF6D5C2)])
    glass(ctx, CGRect(x: 207, y: 216, width: 378, height: 591), 64, tint: 0x8FB887)
    glass(ctx, CGRect(x: 623, y: 216, width: 194, height: 276), 52, tint: 0xEFAF8C)
    glass(ctx, CGRect(x: 623, y: 531, width: 194, height: 276), 52, tint: 0x9CC3DC)
    for x in [252.0, 296.0] {
        ctx.setFillColor(c(0xFFFFFF, 0.9)); ctx.fillEllipse(in: CGRect(x: x, y: 252, width: 26, height: 26))
    }
}

func iconB(_ ctx: CGContext) {
    background(ctx, top: 0xF5F2FC, bottom: 0xDFE6F7,
               blobs: [(CGPoint(x: 280, y: 300), 360, 0xD9CFF3), (CGPoint(x: 780, y: 800), 380, 0xC4E2F3)])
    glass(ctx, CGRect(x: 202, y: 255, width: 397, height: 339), 64, tint: 0xA898DC)
    glass(ctx, CGRect(x: 425, y: 439, width: 397, height: 339), 64, tint: 0x86BEE3, alpha: 0.55)
    // mắt xích bằng kính trắng
    let ring = CGRect(x: 512 - 70, y: 502 - 70, width: 140, height: 140)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: c(0x2B3A55, 0.25))
    ctx.setStrokeColor(c(0xFFFFFF, 0.92)); ctx.setLineWidth(30); ctx.strokeEllipse(in: ring)
    ctx.restoreGState()
    ctx.setFillColor(c(0xFFFFFF, 0.95)); ctx.fillEllipse(in: ring.insetBy(dx: 46, dy: 46))
}

func iconC(_ ctx: CGContext) {
    background(ctx, top: 0xF1F6F8, bottom: 0xD8E3EA,
               blobs: [(CGPoint(x: 760, y: 300), 360, 0xCFE3D4), (CGPoint(x: 300, y: 780), 360, 0xF3E0C6)])
    glass(ctx, CGRect(x: 245, y: 190, width: 533, height: 320), 50, tint: 0x7F9DB3, alpha: 0.55)
    glass(ctx, CGRect(x: 285, y: 228, width: 285, height: 244), 30, tint: 0xFFFFFF, alpha: 0.45)
    glass(ctx, CGRect(x: 592, y: 228, width: 148, height: 244), 30, tint: 0xF0C99A, alpha: 0.7)
    glass(ctx, CGRect(x: 318, y: 548, width: 388, height: 262), 46, tint: 0x9AB6C7, alpha: 0.55)
    glass(ctx, CGRect(x: 352, y: 582, width: 320, height: 194), 26, tint: 0xB7DCC0, alpha: 0.7)
    glass(ctx, CGRect(x: 462, y: 818, width: 100, height: 38), 14, tint: 0x8FA9BA)
}

func render(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)  // trục y hướng xuống như thiết kế
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let icons = [("A", render(iconA)), ("B", render(iconB)), ("C", render(iconC))]
for (name, img) in icons { save(img, "\(dir)/icon_\(name).png") }

// Ảnh so sánh: 3 icon trên nền sáng và nền tối
let W = 1800, H = 1260
let cmp = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
cmp.setFillColor(c(0xF4F4F6)); cmp.fill(CGRect(x: 0, y: 630, width: W, height: 630))
cmp.setFillColor(c(0x1E1F24)); cmp.fill(CGRect(x: 0, y: 0, width: W, height: 630))
for (i, (_, img)) in icons.enumerated() {
    let x = CGFloat(60 + i * 580)
    cmp.draw(img, in: CGRect(x: x, y: 660, width: 520, height: 520))
    cmp.draw(img, in: CGRect(x: x + 130, y: 120, width: 260, height: 260))
    cmp.draw(img, in: CGRect(x: x + 400, y: 120, width: 64, height: 64))
}
save(cmp.makeImage()!, "\(dir)/icon_compare.png")
print("ok")
