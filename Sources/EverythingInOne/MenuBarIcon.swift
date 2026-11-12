import AppKit

/// Biểu tượng thanh menu: 3 ô bo góc giống icon app (ô chính 2/3 + 2 ô phụ).
/// Dạng template để macOS tự tô màu theo chế độ sáng/tối.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 8.5, height: 13), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 11.5, y: 2.5, width: 5, height: 6), xRadius: 1.6, yRadius: 1.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 11.5, y: 9.5, width: 5, height: 6), xRadius: 1.6, yRadius: 1.6).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
