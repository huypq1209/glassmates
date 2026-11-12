import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit

enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
    case sideBySide   // chia đều theo chiều ngang
    case mainLeft     // cửa sổ đầu chiếm 2/3 bên trái, còn lại xếp dọc bên phải
    case grid         // lưới

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: return "Cạnh nhau"
        case .mainLeft: return "Chính 2/3 + phụ"
        case .grid: return "Lưới"
        }
    }
}

/// Sắp xếp cửa sổ THẬT của các app khác bằng Accessibility API.
enum WindowArranger {
    struct Result {
        var arranged = 0
        var missed: [String] = []
    }

    /// Vùng làm việc của màn hình hiện tại, theo toạ độ Accessibility (gốc ở góc trên trái màn hình chính).
    /// Nếu truyền `containing` (toạ độ AX), dùng màn hình chứa điểm đó.
    static func workArea(containing point: CGPoint? = nil) -> CGRect {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return .zero }
        var screen = NSScreen.main ?? primary
        if let point {
            let nsPoint = CGPoint(x: point.x, y: primary.frame.height - point.y)
            if let match = screens.first(where: { $0.frame.contains(nsPoint) }) { screen = match }
        }
        let v = screen.visibleFrame
        return CGRect(x: v.minX, y: primary.frame.height - v.maxY, width: v.width, height: v.height)
    }

    static func rects(count n: Int, preset: LayoutPreset, in area: CGRect, gap: CGFloat = 8) -> [CGRect] {
        guard n > 0 else { return [] }
        let a = area.insetBy(dx: gap, dy: gap)
        if n == 1 { return [a] }

        switch preset {
        case .sideBySide:
            let w = (a.width - gap * CGFloat(n - 1)) / CGFloat(n)
            return (0..<n).map { CGRect(x: a.minX + CGFloat($0) * (w + gap), y: a.minY, width: w, height: a.height) }

        case .mainLeft:
            let mainW = (a.width - gap) * 2 / 3
            let sideW = a.width - gap - mainW
            let others = n - 1
            let h = (a.height - gap * CGFloat(others - 1)) / CGFloat(others)
            var result = [CGRect(x: a.minX, y: a.minY, width: mainW, height: a.height)]
            for i in 0..<others {
                result.append(CGRect(x: a.minX + mainW + gap, y: a.minY + CGFloat(i) * (h + gap), width: sideW, height: h))
            }
            return result

        case .grid:
            let cols = Int(ceil(sqrt(Double(n))))
            let rows = Int(ceil(Double(n) / Double(cols)))
            let w = (a.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (a.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            return (0..<n).map {
                CGRect(x: a.minX + CGFloat($0 % cols) * (w + gap), y: a.minY + CGFloat($0 / cols) * (h + gap), width: w, height: h)
            }
        }
    }

    /// Xếp các cửa sổ theo bố cục và đưa tất cả lên trước.
    @MainActor
    static func arrange(_ windows: [SCWindow], preset: LayoutPreset) async -> Result {
        var result = Result()
        let cells = rects(count: windows.count, preset: preset, in: workArea())

        var raised: [(pid: pid_t, app: AXUIElement, window: AXUIElement)] = []
        for (window, cell) in zip(windows, cells) {
            let name = window.owningApplication?.applicationName ?? window.title ?? "?"
            guard let pid = window.owningApplication?.processID,
                  let ax = axWindow(pid: pid, title: window.title, frame: window.frame) else {
                result.missed.append(name)
                continue
            }
            place(ax, in: cell)
            raised.append((pid, AXUIElementCreateApplication(pid), ax))
            result.arranged += 1
        }

        // Đưa lần lượt từng app lên trước (có nhịp chờ), làm 2 lượt; app của cửa sổ đầu tiên lên cuối cùng để được focus.
        for _ in 0..<2 {
            for item in raised.reversed() {
                NSRunningApplication(processIdentifier: item.pid)?.activate(options: [.activateAllWindows])
                AXUIElementSetAttributeValue(item.app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(item.window, kAXRaiseAction as CFString)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        return result
    }

    // MARK: - Gắn app (glue)

    /// Đưa các app trong nhóm lên cùng lúc khi một app trong nhóm được kích hoạt.
    /// App vừa được kích hoạt (`triggerPID`) lên cuối cùng để giữ focus.
    @MainActor
    static func glue(_ workspace: Workspace, triggerPID: pid_t) async {
        var members: [(pid: pid_t, app: AXUIElement, window: AXUIElement)] = []
        for item in workspace.items {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first,
                  let window = mainWindow(pid: running.processIdentifier, preferredTitle: item.title)
            else { continue }
            let pid = running.processIdentifier
            members.append((pid, AXUIElementCreateApplication(pid), window))
        }
        guard members.count > 1 else { return }

        if workspace.rearrange {
            // Xếp trên màn hình chứa cửa sổ của app vừa được kích hoạt.
            let anchor = members.first(where: { $0.pid == triggerPID }).flatMap { frameOf($0.window) }
            let center = anchor.map { CGPoint(x: $0.midX, y: $0.midY) }
            let cells = rects(count: members.count, preset: workspace.layout, in: workArea(containing: center))
            for (member, cell) in zip(members, cells) { place(member.window, in: cell) }
        }

        let others = members.filter { $0.pid != triggerPID }
        let trigger = members.filter { $0.pid == triggerPID }
        for member in others + trigger {
            AXUIElementSetAttributeValue(member.app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(member.window, kAXRaiseAction as CFString)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    /// Cửa sổ chính của app: ưu tiên cửa sổ có tiêu đề khớp, rồi main window, rồi cửa sổ đầu tiên.
    private static func mainWindow(pid: pid_t, preferredTitle: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let windows: [AXUIElement] =
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success
            ? (value as? [AXUIElement] ?? []) : []

        if !preferredTitle.isEmpty, let match = windows.first(where: {
            guard let t = stringAttribute($0, kAXTitleAttribute) else { return false }
            return t == preferredTitle || t.contains(preferredTitle) || preferredTitle.contains(t)
        }) {
            return match
        }

        var main: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &main) == .success,
           let main, CFGetTypeID(main) == AXUIElementGetTypeID() {
            return (main as! AXUIElement)
        }
        return windows.first
    }

    // MARK: - Accessibility helpers

    private static func axWindow(pid: pid_t, title: String?, frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        // Tiêu đề AX có thể khác tiêu đề của ScreenCaptureKit (vd. Simulator thêm "– iOS 26.1"),
        // nên ưu tiên khớp tiêu đề, còn lại khớp theo vị trí + kích thước.
        var best: (element: AXUIElement, distance: CGFloat, titleMatches: Bool)?
        for w in windows {
            let t = stringAttribute(w, kAXTitleAttribute)
            let titleMatches = title != nil && t != nil
                && (t == title || t!.contains(title!) || title!.contains(t!))
            let distance: CGFloat
            if let f = frameOf(w) {
                distance = abs(f.minX - frame.minX) + abs(f.minY - frame.minY)
                    + abs(f.width - frame.width) + abs(f.height - frame.height)
            } else {
                distance = .greatestFiniteMagnitude
            }
            let better: Bool
            if let b = best {
                better = (titleMatches != b.titleMatches) ? titleMatches : distance < b.distance
            } else {
                better = true
            }
            if better { best = (w, distance, titleMatches) }
        }
        guard let best else { debugLog("axWindow: pid=\(pid) không có cửa sổ AX nào"); return nil }
        if best.titleMatches || best.distance < 80 || windows.count == 1 { return best.element }
        debugLog("axWindow: pid=\(pid) title=\(title ?? "nil") không khớp (distance=\(best.distance), số cửa sổ AX=\(windows.count))")
        return nil
    }

    /// Đặt khung cho cửa sổ. Cửa sổ không co giãn được (vd. Simulator) sẽ được căn giữa trong ô.
    private static func place(_ ax: AXUIElement, in cell: CGRect) {
        // Gỡ trạng thái full screen / thu nhỏ nếu có.
        AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)

        setSize(ax, cell.size)
        setPosition(ax, cell.origin)
        setSize(ax, cell.size)   // lần 2 để chắc khi app tự giới hạn kích thước

        if let actual = frameOf(ax),
           actual.width < cell.width - 1 || actual.height < cell.height - 1 {
            let x = cell.minX + (cell.width - actual.width) / 2
            let y = cell.minY + (cell.height - actual.height) / 2
            setPosition(ax, CGPoint(x: x, y: y))
        }
    }

    private static func stringAttribute(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func frameOf(_ el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?
        var sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success,
              let pv, let sv,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID()
        else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func setPosition(_ el: AXUIElement, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
        }
    }

    private static func setSize(_ el: AXUIElement, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
        }
    }
}
