import SwiftUI
import AppKit
import IOSurface
import ApplicationServices

/// Hiển thị frame IOSurface trực tiếp lên CALayer (ít trễ, không copy)
/// và chuyển chuột / cuộn / phím về cửa sổ gốc.
struct CaptureView: NSViewRepresentable {
    let capture: WindowCapture

    func makeNSView(context: Context) -> InputView {
        let view = InputView(capture: capture)
        capture.onFrame = { [weak view] surface in
            view?.show(surface)
        }
        return view
    }

    func updateNSView(_ nsView: InputView, context: Context) {}
}

final class InputView: NSView {
    private let capture: WindowCapture
    private var surfaceSize = CGSize(width: 1, height: 1)

    init(capture: WindowCapture) {
        self.capture = capture
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show(_ surface: IOSurface) {
        surfaceSize = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        layer?.contents = surface
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    // MARK: Quy đổi toạ độ

    /// Vùng thực sự chứa nội dung bên trong view (do resizeAspect có viền đen).
    private var contentRect: CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / surfaceSize.width, bounds.height / surfaceSize.height)
        let size = CGSize(width: surfaceSize.width * scale, height: surfaceSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Vị trí hiện tại của cửa sổ gốc (toạ độ màn hình, gốc ở góc trên trái).
    private func liveWindowFrame() -> CGRect {
        let id = capture.window.windowID
        if let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
           let dict = list.first?[kCGWindowBounds as String] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: dict) {
            return rect
        }
        return capture.window.frame
    }

    /// Đổi điểm trong view sang toạ độ màn hình của cửa sổ gốc. nil nếu nằm ngoài nội dung.
    private func globalPoint(for event: NSEvent) -> CGPoint? {
        let local = convert(event.locationInWindow, from: nil)
        let fit = contentRect
        guard fit.width > 0, fit.height > 0 else { return nil }
        let nx = (local.x - fit.minX) / fit.width
        let ny = 1 - (local.y - fit.minY) / fit.height
        guard (0...1).contains(nx), (0...1).contains(ny) else { return nil }
        let frame = liveWindowFrame()
        return CGPoint(x: frame.minX + nx * frame.width, y: frame.minY + ny * frame.height)
    }

    private var targetPID: pid_t? { capture.window.owningApplication?.processID }

    // MARK: Chuột

    private func sendMouse(_ type: CGEventType, button: CGMouseButton, event: NSEvent) {
        guard AXIsProcessTrusted(), let pid = targetPID, let point = globalPoint(for: event),
              let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { return }
        cg.setIntegerValueField(.mouseEventClickState, value: Int64(event.clickCount))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(capture.window.windowID))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(capture.window.windowID))
        cg.postToPid(pid)
    }

    override func mouseDown(with event: NSEvent) {
        debugLog("mouseDown AX=\(AXIsProcessTrusted()) pid=\(targetPID ?? -1) point=\(String(describing: globalPoint(for: event))) frame=\(liveWindowFrame()) surface=\(surfaceSize) bounds=\(bounds)")
        window?.makeFirstResponder(self)
        sendMouse(.leftMouseDown, button: .left, event: event)
    }
    override func mouseUp(with event: NSEvent) { sendMouse(.leftMouseUp, button: .left, event: event) }
    override func mouseDragged(with event: NSEvent) { sendMouse(.leftMouseDragged, button: .left, event: event) }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouse(.rightMouseDown, button: .right, event: event)
    }
    override func rightMouseUp(with event: NSEvent) { sendMouse(.rightMouseUp, button: .right, event: event) }
    override func rightMouseDragged(with event: NSEvent) { sendMouse(.rightMouseDragged, button: .right, event: event) }
    override func mouseMoved(with event: NSEvent) { sendMouse(.mouseMoved, button: .left, event: event) }

    override func scrollWheel(with event: NSEvent) {
        guard AXIsProcessTrusted(), let pid = targetPID, let point = globalPoint(for: event),
              let cg = CGEvent(
                scrollWheelEvent2Source: nil,
                units: event.hasPreciseScrollingDeltas ? .pixel : .line,
                wheelCount: 2,
                wheel1: Int32(event.scrollingDeltaY),
                wheel2: Int32(event.scrollingDeltaX),
                wheel3: 0
              )
        else { return }
        cg.location = point
        cg.postToPid(pid)
    }

    // MARK: Bàn phím

    private func sendKey(_ event: NSEvent, down: Bool) {
        guard AXIsProcessTrusted(), let pid = targetPID,
              let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: down)
        else { return }
        cg.flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if down, let chars = event.characters, !chars.isEmpty {
            let units = Array(chars.utf16)
            cg.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        cg.postToPid(pid)
    }

    override func keyDown(with event: NSEvent) { sendKey(event, down: true) }
    override func keyUp(with event: NSEvent) { sendKey(event, down: false) }

    /// Cho phép Cmd+C / Cmd+V... đi tới app gốc khi ô đang được focus,
    /// trừ các phím điều khiển chính EverythingInOne.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        let reserved: Set<String> = ["q", "w", "m", "h", ","]
        if let key = event.charactersIgnoringModifiers?.lowercased(), reserved.contains(key) {
            return false
        }
        sendKey(event, down: true)
        sendKey(event, down: false)
        return true
    }
}

/// Log ra file để đọc được (NSLog bị macOS ẩn nội dung).
func debugLog(_ message: String) {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Glassmates/debug.log")
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
