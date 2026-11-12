// Video quảng bá Glassmates (~33s, 1920x1080, 30fps, H.264).
// Build & chạy:
//   swiftc -O Design/promo/render_promo.swift -o /tmp/render_promo && /tmp/render_promo Design/icon_A.png Design/promo/glassmates_promo.mp4
// Thêm tham số thứ 3 = thư mục để xuất ảnh xem trước từng cảnh.
import AppKit
import AVFoundation
import CoreVideo

let W: CGFloat = 1920, H: CGFloat = 1080, FPS: Int32 = 30
let DURATION = 33.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Tiện ích

func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func ns(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(cgColor: col(hex, a))! }

func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp01((t - a) / (b - a)) }
func easeInOut(_ x: Double) -> Double {
    let t = clamp01(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}
func easeOut(_ x: Double) -> Double { let t = clamp01(x); return 1 - pow(1 - t, 3) }
func easeOutBack(_ x: Double) -> Double {
    let t = clamp01(x), c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }
func lerpP(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p)) }
func lerpR(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, p), y: lerp(a.minY, b.minY, p), width: lerp(a.width, b.width, p), height: lerp(a.height, b.height, p))
}
/// Hiện dần trong khoảng [a, b] (fade in 0.35s, fade out 0.35s).
func window(_ t: Double, _ a: Double, _ b: Double, fade: Double = 0.35) -> CGFloat {
    CGFloat(min(prog(t, a, a + fade), 1 - prog(t, b - fade, b)))
}

func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let rad = min(radius, min(r.width, r.height) / 2)
    return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

// MARK: - Bối cảnh vẽ

var ctx: CGContext!

func fill(_ path: CGPath, _ c: CGColor) { ctx.addPath(path); ctx.setFillColor(c); ctx.fillPath() }
func stroke(_ path: CGPath, _ c: CGColor, _ w: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.strokePath()
}
func linear(_ path: CGPath, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func radial(_ center: CGPoint, _ radius: CGFloat, _ c: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}
func withAlpha(_ a: CGFloat, _ draw: () -> Void) {
    guard a > 0.001 else { return }
    ctx.saveGState(); ctx.setAlpha(a); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    draw()
    ctx.endTransparencyLayer(); ctx.restoreGState()
}
func shadowed(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: col(0x1F2A44, alpha))
    draw()
    ctx.restoreGState()
}
/// Phóng to/thu nhỏ quanh tâm.
func scaled(_ s: CGFloat, around c: CGPoint, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: s, y: s); ctx.translateBy(x: -c.x, y: -c.y)
    draw()
    ctx.restoreGState()
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor,
          center: CGPoint? = nil, at: CGPoint? = nil, alpha: CGFloat = 1, tracking: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha),
        .kern: tracking,
    ]
    let a = NSAttributedString(string: s, attributes: attrs)
    let sz = a.size()
    if let center { a.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2)) }
    else if let at { a.draw(at: at) }
}
func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width
}

var iconImage: CGImage!
func drawIcon(_ r: CGRect, alpha: CGFloat = 1) {
    ctx.saveGState(); ctx.setAlpha(alpha)
    ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(iconImage, in: CGRect(origin: .zero, size: r.size))
    ctx.restoreGState()
}

// MARK: - Thành phần

func wallpaper() {
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    linear(CGPath(rect: full, transform: nil), [col(0xFBF5EC), col(0xEEF2EC), col(0xE6EEF4)],
           CGPoint(x: 0, y: 0), CGPoint(x: W, y: H))
    radial(CGPoint(x: 260, y: 900), 760, col(0xCFE2C8, 0.75))
    radial(CGPoint(x: 1700, y: 180), 700, col(0xF7D6C3, 0.7))
    radial(CGPoint(x: 1500, y: 1000), 640, col(0xC9DDEB, 0.7))
    radial(CGPoint(x: 700, y: 120), 520, col(0xE4DBF3, 0.5))
}

func menuBar(highlightIcon: CGFloat = 0) {
    let bar = CGRect(x: 0, y: 0, width: W, height: 38)
    fill(CGPath(rect: bar, transform: nil), col(0xFFFFFF, 0.55))
    fill(CGPath(rect: CGRect(x: 0, y: 37, width: W, height: 1), transform: nil), col(0xFFFFFF, 0.8))
    text("Glassmates", size: 17, weight: .semibold, color: ns(0x2B2F3A), at: CGPoint(x: 28, y: 9))
    for (i, m) in ["File", "Edit", "View", "Window", "Help"].enumerated() {
        text(m, size: 17, color: ns(0x2B2F3A, 0.85), at: CGPoint(x: 150 + CGFloat(i) * 78, y: 9))
    }
    text("Thu 9:41 AM", size: 17, weight: .medium, color: ns(0x2B2F3A), at: CGPoint(x: W - 140, y: 9))
    // biểu tượng Glassmates trên thanh menu
    let ix: CGFloat = W - 200, iy: CGFloat = 10
    if highlightIcon > 0 { fill(rr(CGRect(x: ix - 8, y: 4, width: 38, height: 30), 7), col(0x2B2F3A, 0.12 * highlightIcon)) }
    let ic = col(0x2B2F3A, 0.9)
    fill(rr(CGRect(x: ix, y: iy + 1, width: 11, height: 17), 2.5), ic)
    fill(rr(CGRect(x: ix + 13, y: iy + 1, width: 7, height: 8), 2), ic)
    fill(rr(CGRect(x: ix + 13, y: iy + 10, width: 7, height: 8), 2), ic)
}

enum Kind { case code, browser, sim, notes, mail }

let codeLines: [(CGFloat, CGFloat, UInt32)] = {
    let palette: [UInt32] = [0xC3B6E6, 0x9CC3DC, 0xA8C5A0, 0xF2C4A8, 0xE8D7A6, 0xB9D3E3]
    var out: [(CGFloat, CGFloat, UInt32)] = []
    var seed: UInt64 = 7
    for _ in 0..<40 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let indent = CGFloat((seed >> 33) % 4) * 28
        let len = CGFloat(120 + Int((seed >> 40) % 360))
        out.append((indent, len, palette[Int((seed >> 20) % UInt64(palette.count))]))
    }
    return out
}()

func appWindow(_ r: CGRect, _ kind: Kind, glow: CGFloat = 0) {
    if kind == .sim { phone(r, glow: glow); return }
    let radius: CGFloat = 16
    let path = rr(r, radius)
    shadowed(blur: 50, dy: 22, alpha: 0.22) { fill(path, col(0xFFFFFF)) }
    if glow > 0 {
        stroke(rr(r.insetBy(dx: -5, dy: -5), radius + 5), col(0x8FB887, 0.85 * glow), 6)
    }
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let titleH: CGFloat = 44
    switch kind {
    case .code:
        fill(CGPath(rect: r, transform: nil), col(0x22262F))
        fill(CGPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: titleH), transform: nil), col(0x2C313C))
        fill(CGPath(rect: CGRect(x: r.minX, y: r.minY + titleH, width: min(220, r.width * 0.2), height: r.height), transform: nil), col(0x272B35))
        let left = r.minX + min(220, r.width * 0.2) + 30
        var y = r.minY + titleH + 26
        var i = 0
        while y < r.maxY - 18 && i < codeLines.count {
            let (indent, len, c) = codeLines[i]
            let w = min(len, r.maxX - left - indent - 30)
            if w > 20 { fill(rr(CGRect(x: left + indent, y: y, width: w, height: 11), 5.5), col(c, 0.85)) }
            y += 26; i += 1
        }
        for k in 0..<6 {
            fill(rr(CGRect(x: r.minX + 22, y: r.minY + titleH + 26 + CGFloat(k) * 30, width: min(150, r.width * 0.14), height: 10), 5), col(0x5B6272))
        }
        text("ContentView.swift — Glassmates", size: 15, weight: .medium, color: ns(0xC9CED8), center: CGPoint(x: r.midX, y: r.minY + titleH / 2))
    case .browser:
        fill(CGPath(rect: r, transform: nil), col(0xFFFFFF))
        fill(CGPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: titleH + 8), transform: nil), col(0xF1F2F5))
        fill(rr(CGRect(x: r.minX + 110, y: r.minY + 10, width: r.width - 160, height: 30), 15), col(0xFFFFFF))
        text("sprint.board", size: 14, color: ns(0x6B7280), center: CGPoint(x: r.minX + 110 + (r.width - 160) / 2, y: r.minY + 25))
        let top = r.minY + titleH + 30
        fill(rr(CGRect(x: r.minX + 28, y: top, width: r.width * 0.45, height: 22), 11), col(0x2B2F3A, 0.8))
        let cardW = (r.width - 28 * 2 - 24) / 3
        let cards: [UInt32] = [0xF2C4A8, 0xA8C5A0, 0xB9D3E3]
        for (k, c) in cards.enumerated() {
            let cr = CGRect(x: r.minX + 28 + CGFloat(k) * (cardW + 12), y: top + 44, width: cardW, height: min(120, r.height * 0.22))
            fill(rr(cr, 12), col(c, 0.55))
        }
        let chartTop = top + 44 + min(120, r.height * 0.22) + 24
        let chartH = r.maxY - chartTop - 26
        if chartH > 40 {
            let bars = 9
            let bw = (r.width - 56) / CGFloat(bars) - 10
            for k in 0..<bars {
                let h = chartH * CGFloat(0.3 + 0.7 * abs(sin(Double(k) * 1.3 + 0.6)))
                fill(rr(CGRect(x: r.minX + 28 + CGFloat(k) * (bw + 10), y: chartTop + chartH - h, width: bw, height: h), 6),
                     col(k % 2 == 0 ? 0x9CC3DC : 0xC3B6E6, 0.8))
            }
        }
    case .notes:
        fill(CGPath(rect: r, transform: nil), col(0xFFF8E1))
        fill(CGPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: titleH), transform: nil), col(0xF8EDC8))
        text("Notes", size: 15, weight: .medium, color: ns(0x6B5B2E), center: CGPoint(x: r.midX, y: r.minY + titleH / 2))
        var y = r.minY + titleH + 34
        while y < r.maxY - 20 {
            fill(rr(CGRect(x: r.minX + 30, y: y, width: r.width * 0.75, height: 10), 5), col(0xD9C88F, 0.7))
            y += 30
        }
    case .mail:
        fill(CGPath(rect: r, transform: nil), col(0xF7F8FB))
        fill(CGPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: titleH), transform: nil), col(0xE9ECF3))
        text("Inbox", size: 15, weight: .medium, color: ns(0x4B5563), center: CGPoint(x: r.midX, y: r.minY + titleH / 2))
        var y = r.minY + titleH + 20
        while y < r.maxY - 60 {
            fill(rr(CGRect(x: r.minX + 24, y: y, width: r.width - 48, height: 56), 10), col(0xFFFFFF))
            fill(rr(CGRect(x: r.minX + 40, y: y + 14, width: r.width * 0.35, height: 10), 5), col(0x6B7280, 0.6))
            fill(rr(CGRect(x: r.minX + 40, y: y + 32, width: r.width * 0.6, height: 8), 4), col(0xC9CED8))
            y += 68
        }
    case .sim: break
    }
    ctx.restoreGState()
    // đèn giao thông
    let lights: [UInt32] = [0xFF6159, 0xFFBD2E, 0x28C941]
    for (k, c) in lights.enumerated() {
        fill(CGPath(ellipseIn: CGRect(x: r.minX + 18 + CGFloat(k) * 22, y: r.minY + 15, width: 14, height: 14), transform: nil), col(c))
    }
    stroke(path, col(0xFFFFFF, 0.7), 1.5)
}

/// Simulator: điện thoại căn giữa trong ô (giữ tỉ lệ như Simulator thật).
func phone(_ cell: CGRect, glow: CGFloat) {
    let aspect: CGFloat = 0.47
    var h = cell.height, w = h * aspect
    if w > cell.width { w = cell.width; h = w / aspect }
    let r = CGRect(x: cell.midX - w / 2, y: cell.midY - h / 2, width: w, height: h)
    let radius = w * 0.17
    shadowed(blur: 44, dy: 20, alpha: 0.25) { fill(rr(r, radius), col(0x1C1E22)) }
    if glow > 0 { stroke(rr(r.insetBy(dx: -6, dy: -6), radius + 6), col(0x8FB887, 0.85 * glow), 6) }
    let s = r.insetBy(dx: w * 0.045, dy: w * 0.045)
    let sp = rr(s, radius * 0.82)
    ctx.saveGState(); ctx.addPath(sp); ctx.clip()
    linear(sp, [col(0xFDF8F0), col(0xEEF3EC)], CGPoint(x: s.minX, y: s.minY), CGPoint(x: s.maxX, y: s.maxY))
    fill(rr(CGRect(x: s.midX - s.width * 0.17, y: s.minY + s.height * 0.018, width: s.width * 0.34, height: s.height * 0.035), 20), col(0x1C1E22))
    // ô tìm kiếm
    fill(rr(CGRect(x: s.minX + s.width * 0.07, y: s.minY + s.height * 0.09, width: s.width * 0.86, height: s.height * 0.05), 14), col(0xFFFFFF))
    // lưới app
    let tiles: [UInt32] = [0x6C9BE8, 0x7FC4DA, 0xF0C35C, 0xF0B04E, 0x6C8FE8, 0xA084E8, 0x6CC4C8, 0x6E7A8C]
    let gw = s.width * 0.86, cellW = gw / 4
    for k in 0..<8 {
        let cx = s.minX + s.width * 0.07 + CGFloat(k % 4) * cellW + cellW * 0.18
        let cy = s.minY + s.height * 0.17 + CGFloat(k / 4) * cellW * 1.25
        fill(rr(CGRect(x: cx, y: cy, width: cellW * 0.64, height: cellW * 0.64), cellW * 0.16), col(tiles[k], 0.9))
        fill(rr(CGRect(x: cx, y: cy + cellW * 0.74, width: cellW * 0.64, height: cellW * 0.08), 3), col(0x9AA1AE, 0.7))
    }
    // thẻ danh sách
    let ly = s.minY + s.height * 0.17 + cellW * 2.6
    fill(rr(CGRect(x: s.minX + s.width * 0.07, y: ly, width: s.width * 0.86, height: s.height * 0.12), 16), col(0xFCE9B8))
    fill(rr(CGRect(x: s.minX + s.width * 0.07, y: ly + s.height * 0.14, width: s.width * 0.86, height: s.height * 0.12), 16), col(0xDDEBDD))
    ctx.restoreGState()
}

func cursor(_ p: CGPoint, click: Double = 0, alpha: CGFloat = 1) {
    guard alpha > 0 else { return }
    if click > 0 && click < 1 {
        let rad = lerp(10, 54, easeOut(click))
        stroke(CGPath(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2), transform: nil),
               col(0x5B8DEF, 0.7 * CGFloat(1 - click)), 4)
    }
    let s: CGFloat = 1.7
    let path = CGMutablePath()
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.2, 13), (7, 19.5), (9.6, 18.4), (6.9, 12.1), (12.4, 12.1)]
    path.move(to: CGPoint(x: p.x, y: p.y))
    for (x, y) in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x + x * s, y: p.y + y * s)) }
    path.closeSubpath()
    ctx.saveGState(); ctx.setAlpha(alpha)
    shadowed(blur: 8, dy: 3, alpha: 0.35) { fill(path, col(0x111111)) }
    stroke(path, col(0xFFFFFF), 2.5)
    fill(path, col(0x111111))
    ctx.restoreGState()
}

func caption(_ s: String, alpha: CGFloat, y: CGFloat = 985) {
    guard alpha > 0 else { return }
    let size: CGFloat = 40
    let w = textWidth(s, size: size, weight: .semibold) + 80
    let r = CGRect(x: W / 2 - w / 2, y: y - 38 + (1 - alpha) * 14, width: w, height: 76)
    withAlpha(alpha) {
        shadowed(blur: 30, dy: 10, alpha: 0.18) { fill(rr(r, 38), col(0xFFFFFF, 0.82)) }
        stroke(rr(r.insetBy(dx: 1, dy: 1), 37), col(0xFFFFFF, 0.95), 2)
        text(s, size: size, weight: .semibold, color: ns(0x2B2F3A), center: CGPoint(x: r.midX, y: r.midY))
    }
}

func pill(_ s: String, center: CGPoint, alpha: CGFloat, size: CGFloat = 22, tint: UInt32 = 0xFFFFFF, textColor: UInt32 = 0x2B2F3A, pressed: CGFloat = 0) {
    guard alpha > 0 else { return }
    let w = textWidth(s, size: size, weight: .semibold) + 48
    let h = size + 26
    let r = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    withAlpha(alpha) {
        scaled(1 - 0.06 * pressed, around: center) {
            shadowed(blur: 24, dy: 8, alpha: 0.18) { fill(rr(r, h / 2), col(tint, 0.88)) }
            stroke(rr(r.insetBy(dx: 1, dy: 1), h / 2 - 1), col(0xFFFFFF, 0.9), 2)
            text(s, size: size, weight: .semibold, color: ns(textColor), center: center)
        }
    }
}

// MARK: - Bố cục cửa sổ

let scattered: [Kind: CGRect] = [
    .code: CGRect(x: 170, y: 150, width: 960, height: 620),
    .browser: CGRect(x: 760, y: 300, width: 860, height: 560),
    .sim: CGRect(x: 1330, y: 120, width: 330, height: 700),
    .notes: CGRect(x: 420, y: 430, width: 620, height: 440),
]
let gap: CGFloat = 18
let area = CGRect(x: gap, y: 38 + gap, width: W - 2 * gap, height: H - 38 - 2 * gap)
let mainLeft: [Kind: CGRect] = {
    let mainW = (area.width - gap) * 2 / 3, sideW = area.width - gap - mainW
    let h = (area.height - gap) / 2
    return [.code: CGRect(x: area.minX, y: area.minY, width: mainW, height: area.height),
            .sim: CGRect(x: area.minX + mainW + gap, y: area.minY, width: sideW, height: h),
            .browser: CGRect(x: area.minX + mainW + gap, y: area.minY + h + gap, width: sideW, height: h)]
}()
let sideBySide: [Kind: CGRect] = {
    let w = (area.width - 2 * gap) / 3
    return [.code: CGRect(x: area.minX, y: area.minY, width: w, height: area.height),
            .sim: CGRect(x: area.minX + w + gap, y: area.minY, width: w, height: area.height),
            .browser: CGRect(x: area.minX + 2 * (w + gap), y: area.minY, width: w, height: area.height)]
}()
let grid: [Kind: CGRect] = {
    let w = (area.width - gap) / 2, h = (area.height - gap) / 2
    return [.code: CGRect(x: area.minX, y: area.minY, width: w, height: h),
            .sim: CGRect(x: area.minX + w + gap, y: area.minY, width: w, height: h),
            .browser: CGRect(x: area.minX, y: area.minY + h + gap, width: area.width, height: h)]
}()

// MARK: - Các cảnh (t = thời gian cục bộ)

func sceneIntro(_ t: Double) {
    wallpaper()
    let p = easeOutBack(prog(t, 0.1, 1.1))
    let size: CGFloat = 300 * CGFloat(0.6 + 0.4 * p)
    let c = CGPoint(x: W / 2, y: 410)
    shadowed(blur: 50, dy: 20, alpha: 0.18 * CGFloat(prog(t, 0.1, 0.8))) {
        drawIcon(CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size), alpha: CGFloat(prog(t, 0.1, 0.6)))
    }
    let a1 = CGFloat(easeOut(prog(t, 0.7, 1.4)))
    text("Glassmates", size: 96, weight: .bold, color: ns(0x2B2F3A), center: CGPoint(x: W / 2, y: 650 + (1 - a1) * 20), alpha: a1, tracking: -1)
    let a2 = CGFloat(easeOut(prog(t, 1.3, 2.0)))
    text("Your windows, always together.", size: 40, weight: .medium, color: ns(0x5B6272), center: CGPoint(x: W / 2, y: 740 + (1 - a2) * 16), alpha: a2)
}

/// Thứ tự vẽ (dưới → trên) cho cảnh "vấn đề".
func sceneProblem(_ t: Double) {
    wallpaper(); menuBar()
    var order: [Kind] = [.code, .sim, .browser, .notes]
    let clickCode = 1.9, clickBrowser = 3.6
    if t >= clickCode { order = [.sim, .browser, .notes, .code] }
    if t >= clickBrowser { order = [.sim, .notes, .code, .browser] }
    for k in order {
        var r = scattered[k]!
        if (k == .code && t >= clickCode && t < clickCode + 0.3) || (k == .browser && t >= clickBrowser && t < clickBrowser + 0.3) {
            let since = t - (k == .code ? clickCode : clickBrowser)
            let s = 1 + 0.015 * sin(since / 0.3 * .pi)
            r = r.insetBy(dx: -r.width * CGFloat(s - 1), dy: -r.height * CGFloat(s - 1))
        }
        appWindow(r, k)
    }
    // con trỏ
    let p0 = CGPoint(x: 1000, y: 900), p1 = CGPoint(x: 330, y: 300), p2 = CGPoint(x: 1450, y: 760)
    var pos = lerpP(p0, p1, easeInOut(prog(t, 0.6, 1.8)))
    if t > 2.4 { pos = lerpP(p1, p2, easeInOut(prog(t, 2.4, 3.5))) }
    let click = t >= clickBrowser ? prog(t, clickBrowser, clickBrowser + 0.5) : prog(t, clickCode, clickCode + 0.5)
    cursor(pos, click: click)
    caption("Juggling an IDE, a simulator and a browser?", alpha: window(t, 0.2, 2.9))
    caption("Click one… and the others disappear.", alpha: window(t, 3.0, 5.6))
}

func sceneArrange(_ t: Double) {
    wallpaper(); menuBar()
    // Trước khi xếp: giữ thứ tự cuối của cảnh trước
    let start: [Kind: CGRect] = scattered
    let pArrange: (Kind) -> Double = { k in
        let delay: Double = k == .code ? 0 : (k == .sim ? 0.12 : 0.24)
        return easeInOut(prog(t, 1.35 + delay, 2.45 + delay))
    }
    // Chuyển qua các bố cục
    func target(_ k: Kind) -> CGRect {
        let base = lerpR(start[k]!, mainLeft[k]!, pArrange(k))
        if t < 3.0 { return base }
        let toSide = easeInOut(prog(t, 3.0, 3.7))
        let toGrid = easeInOut(prog(t, 4.2, 4.9))
        let toMain = easeInOut(prog(t, 5.4, 6.0))
        var r = lerpR(mainLeft[k]!, sideBySide[k]!, toSide)
        r = lerpR(r, grid[k]!, toGrid)
        return lerpR(r, mainLeft[k]!, toMain)
    }
    let notesAlpha = CGFloat(1 - prog(t, 1.3, 1.9))
    let notesRect = scattered[.notes]!.offsetBy(dx: CGFloat(-prog(t, 1.3, 1.9)) * 200, dy: 0)
    withAlpha(notesAlpha) { appWindow(notesRect, .notes) }
    for k in [Kind.sim, .code, .browser] { appWindow(target(k), k) }

    // Nút "Arrange Windows"
    let btnC = CGPoint(x: W / 2, y: 120)
    let btnAlpha = window(t, 0.2, 2.6)
    pill("Arrange Windows", center: btnC, alpha: btnAlpha, size: 26, tint: 0xFFFFFF,
         pressed: CGFloat(t > 1.15 && t < 1.45 ? 1 : 0))
    // Nhãn bố cục hiện tại
    var label = ""
    if t >= 2.5 && t < 3.3 { label = "Main 2/3 + Side" }
    else if t >= 3.3 && t < 4.5 { label = "Side by Side" }
    else if t >= 4.5 && t < 5.6 { label = "Grid" }
    else if t >= 5.6 { label = "Main 2/3 + Side" }
    if !label.isEmpty { pill(label, center: CGPoint(x: W / 2, y: 120), alpha: window(t, 2.5, 6.4, fade: 0.25), size: 24, tint: 0x8FB887, textColor: 0xFFFFFF) }

    let cp = lerpP(CGPoint(x: 1300, y: 700), CGPoint(x: btnC.x + 40, y: btnC.y + 6), easeInOut(prog(t, 0.2, 1.1)))
    cursor(cp, click: prog(t, 1.15, 1.65), alpha: CGFloat(1 - prog(t, 2.2, 2.6)))
    caption("Arrange them all in one click.", alpha: window(t, 0.2, 2.9))
    caption("Side by side, grid, or main + side.", alpha: window(t, 3.0, 6.3))
}

func sceneGlue(_ t: Double) {
    wallpaper(); menuBar()
    let clickT = 2.2
    let covers: [(Kind, CGRect)] = [
        (.mail, CGRect(x: 380, y: 180, width: 900, height: 640)),
        (.notes, CGRect(x: 900, y: 360, width: 760, height: 560)),
    ]
    let raised = t >= clickT
    func coverRect(_ i: Int) -> CGRect {
        let base = covers[i].1
        let enter = easeOut(prog(t, 0.3 + Double(i) * 0.25, 1.0 + Double(i) * 0.25))
        return base.offsetBy(dx: 0, dy: CGFloat(1 - enter) * 500)
    }
    func group() {
        // nhóm nổi lên lần lượt: browser, code, sim (app được bấm lên cuối)
        let order: [Kind] = [.browser, .code, .sim]
        for (i, k) in order.enumerated() {
            let since = t - clickT - Double(i) * 0.12
            var r = mainLeft[k]!
            var glow: CGFloat = 0
            if raised && since > 0 {
                let s = 1 + 0.02 * sin(clamp01(since / 0.35) * .pi)
                r = r.insetBy(dx: -r.width * CGFloat(s - 1), dy: -r.height * CGFloat(s - 1))
                glow = CGFloat(1 - prog(since, 0.6, 1.6)) * CGFloat(prog(since, 0, 0.15))
            }
            appWindow(r, k, glow: glow)
        }
    }
    if raised {
        for i in covers.indices { appWindow(coverRect(i), covers[i].0) }
        group()
        // các đường nối giữa nhóm
        let la = CGFloat(prog(t, clickT + 0.3, clickT + 0.6)) * CGFloat(1 - prog(t, clickT + 1.8, clickT + 2.4))
        if la > 0 {
            let centers = [mainLeft[.code]!, mainLeft[.sim]!, mainLeft[.browser]!].map { CGPoint(x: $0.midX, y: $0.midY) }
            for (a, b) in [(0, 1), (0, 2), (1, 2)] {
                let path = CGMutablePath(); path.move(to: centers[a]); path.addLine(to: centers[b])
                ctx.saveGState(); ctx.setLineDash(phase: CGFloat(t * 60), lengths: [18, 12])
                stroke(path, col(0x8FB887, 0.9 * la), 5); ctx.restoreGState()
                for c in [centers[a], centers[b]] {
                    fill(CGPath(ellipseIn: CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28), transform: nil), col(0xFFFFFF, la))
                    stroke(CGPath(ellipseIn: CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28), transform: nil), col(0x8FB887, la), 5)
                }
            }
        }
    } else {
        group()
        for i in covers.indices { appWindow(coverRect(i), covers[i].0) }
    }
    // con trỏ tới phần Simulator còn lộ ra
    let simCell = mainLeft[.sim]!
    let target = CGPoint(x: simCell.maxX - 60, y: simCell.minY + 140)
    let cp = lerpP(CGPoint(x: 700, y: 950), target, easeInOut(prog(t, 1.1, 2.1)))
    cursor(cp, click: prog(t, clickT, clickT + 0.5), alpha: CGFloat(1 - prog(t, 4.6, 5.0)))
    caption("Glue apps together.", alpha: window(t, 0.2, 2.6))
    caption("Click one — the whole group comes forward.", alpha: window(t, 2.7, 6.0))
}

func sceneDisplays(_ t: Double) {
    wallpaper()
    let ext = CGRect(x: 520, y: 70, width: 880, height: 495)
    let lap = CGRect(x: 680, y: 600, width: 560, height: 350)
    func display(_ r: CGRect, _ name: String) {
        shadowed(blur: 40, dy: 16, alpha: 0.2) { fill(rr(r, 18), col(0xFFFFFF, 0.55)) }
        stroke(rr(r.insetBy(dx: 1, dy: 1), 17), col(0xFFFFFF, 0.95), 2.5)
        text(name, size: 17, weight: .medium, color: ns(0x5B6272), at: CGPoint(x: r.minX + 18, y: r.maxY - 32))
    }
    let a = CGFloat(easeOut(prog(t, 0, 0.6)))
    withAlpha(a) {
        display(ext, "External display")
        display(lap, "Built-in display")
    }
    func frame(_ r: CGRect, _ tint: UInt32, _ name: String, _ alpha: CGFloat = 1, handle: Bool = false) {
        withAlpha(alpha) {
            shadowed(blur: 24, dy: 10, alpha: 0.18) { fill(rr(r, 12), col(tint, 0.55)) }
            linear(rr(r, 12), [col(0xFFFFFF, 0.45), col(0xFFFFFF, 0.05)], CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY))
            stroke(rr(r.insetBy(dx: 1.5, dy: 1.5), 10.5), col(tint), 3)
            text(name, size: 22, weight: .semibold, color: ns(0x2B2F3A), center: CGPoint(x: r.midX, y: r.midY))
            if handle { fill(rr(CGRect(x: r.maxX - 22, y: r.maxY - 22, width: 16, height: 16), 4), col(tint)) }
        }
    }
    let codeR = lap.insetBy(dx: 14, dy: 14).offsetBy(dx: 0, dy: -12).insetBy(dx: 0, dy: 6)
    let simR = CGRect(x: ext.minX + 18, y: ext.minY + 18, width: 170, height: 340)
    // Chrome: kéo từ laptop lên màn hình ngoài, rồi đổi cỡ
    let chromeStart = CGRect(x: lap.minX + 260, y: lap.minY + 60, width: 260, height: 200)
    let chromeMid = CGRect(x: ext.minX + 210, y: ext.minY + 18, width: 260, height: 200)
    let chromeEnd = CGRect(x: ext.minX + 210, y: ext.minY + 18, width: 650, height: 440)
    let pDrag = easeInOut(prog(t, 1.2, 2.6))
    let pResize = easeInOut(prog(t, 3.0, 4.0))
    let chromeR = lerpR(lerpR(chromeStart, chromeMid, pDrag), chromeEnd, pResize)
    let fa = CGFloat(easeOut(prog(t, 0.3, 0.9)))
    frame(codeR, 0x8FB887, "Code", fa)
    frame(simR, 0x9CC3DC, "Simulator", fa)
    frame(chromeR, 0xEFAF8C, "Chrome", fa, handle: true)
    // con trỏ
    var cp = CGPoint(x: chromeStart.midX + 30, y: chromeStart.midY + 30)
    if t < 1.2 { cp = lerpP(CGPoint(x: 1500, y: 900), cp, easeInOut(prog(t, 0.4, 1.1))) }
    else if t < 2.8 { cp = CGPoint(x: chromeR.midX + 30, y: chromeR.midY + 30) }
    else { cp = CGPoint(x: chromeR.maxX - 14, y: chromeR.maxY - 14) }
    if t >= 2.6 && t < 3.0 {
        let from = CGPoint(x: chromeMid.midX + 30, y: chromeMid.midY + 30), to = CGPoint(x: chromeMid.maxX - 14, y: chromeMid.maxY - 14)
        cp = lerpP(from, to, easeInOut(prog(t, 2.6, 3.0)))
    }
    cursor(cp, click: prog(t, 1.1, 1.5), alpha: CGFloat(1 - prog(t, 4.6, 5.0)))
    pill("Saved", center: CGPoint(x: W / 2, y: 30 + 10), alpha: window(t, 4.2, 5.4, fade: 0.25), size: 20, tint: 0x8FB887, textColor: 0xFFFFFF)
    caption("Design custom layouts across two displays.", alpha: window(t, 0.2, 5.4))
}

func sceneMenuBar(_ t: Double) {
    wallpaper()
    for k in [Kind.code, .sim, .browser] { appWindow(mainLeft[k]!, k) }
    // phủ lớp kính sáng để làm nổi menu
    fill(CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil), col(0xF7F3EC, 0.55))
    menuBar(highlightIcon: CGFloat(prog(t, 0.3, 0.5)))
    // menu thả xuống
    let pa = CGFloat(easeOut(prog(t, 0.4, 0.8)))
    let panel = CGRect(x: W - 520, y: 46, width: 420, height: 292)
    withAlpha(pa) {
        shadowed(blur: 40, dy: 14, alpha: 0.25) { fill(rr(panel, 16), col(0xFDFCFA, 1)) }
        stroke(rr(panel.insetBy(dx: 1, dy: 1), 15), col(0xFFFFFF), 2)
        var y = panel.minY + 22
        func item(_ s: String, check: Bool? = nil, bold: Bool = false, highlight: CGFloat = 0) {
            if highlight > 0 { fill(rr(CGRect(x: panel.minX + 10, y: y - 6, width: panel.width - 20, height: 44), 9), col(0x5B8DEF, 0.9 * highlight)) }
            let tc: UInt32 = highlight > 0.5 ? 0xFFFFFF : 0x2B2F3A
            if let check, check { text("✓", size: 22, weight: .bold, color: ns(tc), at: CGPoint(x: panel.minX + 24, y: y)) }
            text(s, size: 22, weight: bold ? .semibold : .regular, color: ns(tc), at: CGPoint(x: panel.minX + 56, y: y))
            y += 48
        }
        func divider() { fill(CGPath(rect: CGRect(x: panel.minX + 18, y: y - 4, width: panel.width - 36, height: 1.5), transform: nil), col(0x2B2F3A, 0.12)); y += 10 }
        item("Glue: Dev", check: true)
        item("Glue: Design", check: t > 2.0)
        divider()
        item("Open at Login", check: true)
        divider()
        item("Open Glassmates", highlight: CGFloat(prog(t, 2.6, 2.8)) * CGFloat(1 - prog(t, 3.4, 3.6)))
        item("Quit Glassmates")
    }
    // con trỏ
    let cp = lerpP(CGPoint(x: W - 380, y: 600), CGPoint(x: W - 360, y: 46 + 22 + 48 + 14), easeInOut(prog(t, 0.9, 1.8)))
    let cp2 = lerpP(cp, CGPoint(x: W - 340, y: 46 + 22 + 48 * 4 + 20 + 14), easeInOut(prog(t, 2.2, 2.7)))
    cursor(t < 2.2 ? cp : cp2, click: prog(t, 1.9, 2.3))
    caption("Save workspaces. Lives in your menu bar.", alpha: window(t, 0.2, 2.3))
    caption("Opens at login. Speaks English & Tiếng Việt.", alpha: window(t, 2.4, 4.0))
}

func sceneOutro(_ t: Double) {
    wallpaper()
    let p = easeOutBack(prog(t, 0.1, 0.9))
    let size: CGFloat = 240 * CGFloat(0.7 + 0.3 * p)
    let c = CGPoint(x: W / 2, y: 390)
    shadowed(blur: 50, dy: 20, alpha: 0.18) {
        drawIcon(CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size), alpha: CGFloat(prog(t, 0.1, 0.5)))
    }
    let a1 = CGFloat(easeOut(prog(t, 0.5, 1.1)))
    text("Glassmates", size: 88, weight: .bold, color: ns(0x2B2F3A), center: CGPoint(x: W / 2, y: 600), alpha: a1, tracking: -1)
    let a2 = CGFloat(easeOut(prog(t, 0.9, 1.6)))
    text("Click one. Bring them all.", size: 42, weight: .medium, color: ns(0x5B6272), center: CGPoint(x: W / 2, y: 690), alpha: a2)
    pill("for macOS", center: CGPoint(x: W / 2, y: 790), alpha: CGFloat(easeOut(prog(t, 1.4, 2.0))), size: 24, tint: 0x8FB887, textColor: 0xFFFFFF)
}

// MARK: - Dòng thời gian

let scenes: [(start: Double, end: Double, draw: (Double) -> Void)] = [
    (0.0, 3.5, sceneIntro),
    (3.5, 9.3, sceneProblem),
    (9.3, 15.8, sceneArrange),
    (15.8, 21.8, sceneGlue),
    (21.8, 27.3, sceneDisplays),
    (27.3, 31.3, sceneMenuBar),
    (31.3, DURATION, sceneOutro),
]
let crossfade = 0.45

func drawFrame(at t: Double) {
    for (i, s) in scenes.enumerated() {
        let fadeIn = i == 0 ? 1 : prog(t, s.start, s.start + crossfade)
        guard t >= s.start, t < s.end + crossfade || i == scenes.count - 1 else { continue }
        let local = t - s.start
        if fadeIn >= 1 { s.draw(local) } else { withAlpha(CGFloat(fadeIn)) { s.draw(local) } }
    }
    // mờ dần ở cuối video
    let out = prog(t, DURATION - 0.6, DURATION)
    if out > 0 { fill(CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil), col(0xFBF5EC, CGFloat(out))) }
}

// MARK: - Xuất video

let args = CommandLine.arguments
guard args.count >= 3, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let icon = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("Cách dùng: render_promo <icon.png> <out.mp4> [thư mục ảnh xem trước]"); exit(1)
}
iconImage = icon
let outURL = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: outURL)

func withFrameContext(_ data: UnsafeMutableRawPointer?, bytesPerRow: Int, _ body: () -> Void) {
    ctx = CGContext(data: data, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// Ảnh xem trước từng cảnh (để kiểm tra nhanh)
if args.count >= 4 {
    let dir = args[3]
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for t in [2.2, 5.0, 8.0, 12.2, 14.5, 17.0, 19.0, 23.5, 26.0, 29.0, 31.0, 32.6] {
        withFrameContext(nil, bytesPerRow: 0) {
            ctx.setFillColor(col(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            drawFrame(at: t)
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
            .write(to: URL(fileURLWithPath: String(format: "%@/frame_%05.1f.jpg", dir, t)))
    }
    print("Đã xuất ảnh xem trước vào \(dir)")
}

let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let total = Int(DURATION * Double(FPS))
for f in 0..<total {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buffer = pb else { fatalError("Không tạo được pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    withFrameContext(CVPixelBufferGetBaseAddress(buffer), bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)) {
        ctx.setFillColor(col(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        drawFrame(at: Double(f) / Double(FPS))
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: FPS))
    if f % 150 == 0 { print("frame \(f)/\(total)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "Đã xuất: \(outURL.path)" : "Lỗi: \(String(describing: writer.error))")
