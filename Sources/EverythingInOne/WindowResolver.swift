import Foundation
import AppKit
import ApplicationServices

/// Tìm đúng cửa sổ thật ứng với một mục trong workspace.
///
/// Mỗi mục được nhớ bằng mã cửa sổ (CGWindowID) — cố định suốt đời cửa sổ, không đổi theo tab/tiêu đề.
/// Nhờ vậy app có nhiều cửa sổ (Chrome, VS Code, Terminal…) chỉ cửa sổ đã chọn bị đụng tới.
/// Khi cửa sổ cũ đã đóng (vd. mở lại app), tìm lại một cách thận trọng; mơ hồ thì bỏ qua, không đoán bừa.
enum WindowResolver {
    struct Resolved {
        let pid: pid_t
        let window: AXUIElement
        let windowID: CGWindowID?
        /// true nếu khớp đúng mã cửa sổ đã lưu.
        let exact: Bool
    }

    /// Mọi tiến trình đang chạy của app (một số app chạy nhiều phiên bản cùng lúc).
    static func processes(of bundleID: String) -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
    }

    /// Các cửa sổ chuẩn (không phải panel, sheet, popover…) của một tiến trình.
    static func standardWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter {
            let subrole = WindowArranger.stringAttribute($0, kAXSubroleAttribute)
            return subrole == nil || subrole == (kAXStandardWindowSubrole as String)
        }
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? { SkyLight.windowID(of: window) }

    /// Tiến trình sở hữu một cửa sổ (theo mã cửa sổ).
    static func ownerPID(of windowID: CGWindowID) -> pid_t? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first
        else { return nil }
        return info[kCGWindowOwnerPID as String] as? pid_t
    }

    /// Cửa sổ đang focus của một tiến trình.
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Tìm cửa sổ của một mục. `expectedFrame`: vị trí mong đợi (vd. vị trí tuỳ chỉnh đã lưu) để nhận lại cửa sổ.
    static func resolve(_ item: Workspace.Item, expectedFrame: CGRect? = nil) -> Resolved? {
        var pids = processes(of: item.bundleID)
        // Dự phòng: danh sách app của macOS đôi khi tạm thời trống → lấy tiến trình sở hữu từ mã cửa sổ đã lưu.
        if pids.isEmpty, let saved = item.windowID, let owner = ownerPID(of: saved) { pids = [owner] }
        guard !pids.isEmpty else {
            debugLog("resolve \(item.appName): app không chạy")
            return nil
        }
        let candidates: [(pid: pid_t, window: AXUIElement, id: CGWindowID?)] = pids.flatMap { pid in
            standardWindows(pid: pid).map { (pid, $0, windowID(of: $0)) }
        }
        if let saved = item.windowID, !candidates.contains(where: { $0.id == saved }) {
            debugLog("resolve \(item.appName): không thấy wid=\(saved) trong \(candidates.map { $0.id.map(String.init) ?? "?" }) (pids=\(pids))")
        }

        // 1. Đúng mã cửa sổ đã lưu.
        if let saved = item.windowID, let hit = candidates.first(where: { $0.id == saved }) {
            return Resolved(pid: hit.pid, window: hit.window, windowID: hit.id, exact: true)
        }

        // Cửa sổ cũ không còn (hoặc dữ liệu cũ chưa có mã) → tìm lại, chỉ nhận khi KHÔNG mơ hồ.
        func unique(_ list: [(pid: pid_t, window: AXUIElement, id: CGWindowID?)], _ why: String) -> Resolved? {
            guard list.count == 1, let hit = list.first else { return nil }
            debugLog("resolve \(item.appName): nhận lại cửa sổ theo \(why) (wid=\(hit.id.map(String.init) ?? "nil"))")
            return Resolved(pid: hit.pid, window: hit.window, windowID: hit.id, exact: false)
        }
        let title = item.title
        if !title.isEmpty {
            let same = candidates.filter { WindowArranger.stringAttribute($0.window, kAXTitleAttribute) == title }
            if let r = unique(same, "tiêu đề trùng khớp") { return r }
        }
        if let expectedFrame {
            let near = candidates.filter { c in
                guard let f = WindowArranger.frameOf(c.window) else { return false }
                return abs(f.minX - expectedFrame.minX) + abs(f.minY - expectedFrame.minY)
                    + abs(f.width - expectedFrame.width) + abs(f.height - expectedFrame.height) < 60
            }
            if let r = unique(near, "vị trí đã lưu") { return r }
        }
        if !title.isEmpty {
            // Tiêu đề gần giống (vd. Simulator thêm "– iOS 26.1").
            let similar = candidates.filter { c in
                guard let t = WindowArranger.stringAttribute(c.window, kAXTitleAttribute), !t.isEmpty else { return false }
                return t.contains(title) || title.contains(t)
            }
            if let r = unique(similar, "tiêu đề gần giống") { return r }
        }
        if let r = unique(candidates, "app chỉ có 1 cửa sổ") { return r }

        debugLog("resolve \(item.appName): không xác định được cửa sổ (\(candidates.count) cửa sổ) → bỏ qua, không đụng tới")
        return nil
    }
}
