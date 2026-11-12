import AppKit

/// Một màn hình, toạ độ theo hệ Accessibility (gốc ở góc trên trái màn hình chính, trục y hướng xuống).
struct ScreenInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let frame: CGRect
    let visible: CGRect
}

/// Vị trí của một cửa sổ: thuộc màn hình nào + khung tương đối (0...1) trong vùng làm việc của màn hình đó.
struct Placement: Codable, Equatable {
    var screenID: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

enum Screens {
    static func all() -> [ScreenInfo] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func ax(_ r: NSRect) -> CGRect {
            CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens.map {
            ScreenInfo(id: id(for: $0), name: $0.localizedName, frame: ax($0.frame), visible: ax($0.visibleFrame))
        }
    }

    /// ID ổn định của màn hình (UUID), để nhớ đúng màn hình kể cả khi rút/cắm lại.
    static func id(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "\(displayID)"
    }

    /// Màn hình chứa tâm của khung (hoặc màn hình gần nhất).
    static func screen(for rect: CGRect, in screens: [ScreenInfo]) -> ScreenInfo? {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = screens.first(where: { $0.frame.contains(c) }) { return hit }
        return screens.min { distance($0.frame, c) < distance($1.frame, c) }
    }

    /// Khung tuyệt đối từ Placement. Màn hình đã rút ra thì dùng màn hình chính.
    static func rect(for p: Placement, in screens: [ScreenInfo]) -> CGRect? {
        guard let screen = screens.first(where: { $0.id == p.screenID }) ?? screens.first else { return nil }
        let v = screen.visible
        return CGRect(x: v.minX + p.x * v.width, y: v.minY + p.y * v.height,
                      width: p.w * v.width, height: p.h * v.height)
    }

    static func placement(for rect: CGRect, in screens: [ScreenInfo]) -> Placement? {
        guard let screen = screen(for: rect, in: screens) else { return nil }
        let v = screen.visible
        return Placement(screenID: screen.id,
                         x: (rect.minX - v.minX) / v.width, y: (rect.minY - v.minY) / v.height,
                         w: rect.width / v.width, h: rect.height / v.height)
    }

    /// Giữ khung nằm gọn trong vùng làm việc của màn hình chứa nó.
    static func clamp(_ rect: CGRect, in screens: [ScreenInfo]) -> CGRect {
        guard let v = screen(for: rect, in: screens)?.visible else { return rect }
        var r = rect
        r.size.width = min(r.width, v.width)
        r.size.height = min(r.height, v.height)
        r.origin.x = min(max(r.minX, v.minX), v.maxX - r.width)
        r.origin.y = min(max(r.minY, v.minY), v.maxY - r.height)
        return r
    }

    private static func distance(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
