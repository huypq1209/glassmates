import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit

enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
    case sideBySide   // chia đều theo chiều ngang
    case mainLeft     // cửa sổ đầu chiếm 2/3 bên trái, còn lại xếp dọc bên phải
    case grid         // lưới
    case custom       // vị trí tự đặt cho từng app (có thể trên nhiều màn hình)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: return String(localized: "Cạnh nhau")
        case .mainLeft: return String(localized: "Chính 2/3 + phụ")
        case .grid: return String(localized: "Lưới")
        case .custom: return String(localized: "Tuỳ chỉnh")
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
        case .sideBySide, .custom:
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
                  let ax = axWindow(pid: pid, windowID: window.windowID, title: window.title, frame: window.frame) else {
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

    /// Cập nhật mã cửa sổ cho một mục khi cửa sổ cũ không còn và đã nhận lại được cửa sổ mới.
    struct Rebind {
        let itemIndex: Int
        let windowID: UInt32
        let title: String?
    }

    struct Member {
        let index: Int
        let pid: pid_t
        let app: AXUIElement
        let window: AXUIElement
        let windowID: CGWindowID?
        let item: Workspace.Item
    }

    /// Tìm đúng cửa sổ của từng mục (theo mã cửa sổ). Mục nào không xác định chắc chắn thì bỏ qua.
    @MainActor
    static func members(of workspace: Workspace) -> (members: [Member], rebinds: [Rebind]) {
        let screens = Screens.all()
        var members: [Member] = []
        var rebinds: [Rebind] = []
        var used = Set<CGWindowID>()
        for (index, item) in workspace.items.enumerated() {
            let expected = item.placement.flatMap { Screens.rect(for: $0, in: screens) }
            guard let r = WindowResolver.resolve(item, expectedFrame: expected) else { continue }
            if let id = r.windowID {
                guard !used.contains(id) else { continue }   // 2 mục không được trỏ cùng 1 cửa sổ
                used.insert(id)
                if !r.exact {
                    rebinds.append(Rebind(itemIndex: index, windowID: id,
                                          title: stringAttribute(r.window, kAXTitleAttribute)))
                }
            }
            members.append(Member(index: index, pid: r.pid, app: AXUIElementCreateApplication(r.pid),
                                  window: r.window, windowID: r.windowID, item: item))
        }
        return (members, rebinds)
    }

    /// Đưa cả nhóm lên khi một cửa sổ trong nhóm được focus.
    /// `trigger`: mã cửa sổ vừa được focus (nil = coi cửa sổ đầu tiên của nhóm là cửa sổ được chọn).
    /// Trả về các mục cần cập nhật mã cửa sổ.
    @MainActor
    @discardableResult
    static func glue(_ workspace: Workspace, trigger: CGWindowID?, forceArrange: Bool = false) async -> [Rebind] {
        let (members, rebinds) = members(of: workspace)
        let triggerMember = trigger.flatMap { t in members.first { $0.windowID == t } } ?? members.first
        debugLog("glue \(workspace.name) trigger=\(trigger.map(String.init) ?? "nil") members=\(members.map { "\($0.item.appName)#\($0.windowID.map(String.init) ?? "?")" }) / \(workspace.items.count) mục")
        guard !members.isEmpty else { return rebinds }

        if workspace.layout == .custom, workspace.rearrange || forceArrange {
            let screens = Screens.all()
            for member in members {
                if let p = member.item.placement, let target = Screens.rect(for: p, in: screens) {
                    place(member.window, in: target)
                }
            }
        } else if workspace.rearrange || forceArrange {
            // Xếp trên màn hình chứa cửa sổ vừa được chọn.
            let anchor = triggerMember.flatMap { frameOf($0.window) }
            let center = anchor.map { CGPoint(x: $0.midX, y: $0.midY) }
            let cells = rects(count: members.count, preset: workspace.layout, in: workArea(containing: center))
            for (member, cell) in zip(members, cells) { place(member.window, in: cell) }
        }

        if workspace.minimizeOthers {
            minimizeOverlappingExtras(members.map { ($0.pid, $0.window, $0.item.appName) })
        }

        // Chỉ đưa lên những cửa sổ đang bị che. Nếu cả nhóm đã hiện rõ thì không làm gì (tránh giật).
        let others = members.filter { $0.index != triggerMember?.index }
        let hidden = others.filter { isObstructed($0.pid, $0.window, windowID: $0.windowID) }
        debugLog("glue raise: \(hidden.map(\.item.appName)) / bỏ qua \(others.count - hidden.count) cửa sổ đã hiện")
        guard !hidden.isEmpty else { return rebinds }

        // Cách 1: chỉ raise cửa sổ, KHÔNG chuyển focus.
        for member in hidden {
            AXUIElementPerformAction(member.window, kAXRaiseAction as CFString)
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        let stillHidden = hidden.filter { isObstructed($0.pid, $0.window, windowID: $0.windowID) }
        debugLog("glue raise (không đổi focus): còn bị che \(stillHidden.map(\.item.appName))")
        guard !stillHidden.isEmpty else { return rebinds }

        // Cách 2 (dự phòng): đưa từng cửa sổ lên bằng cách focus đúng cửa sổ đó (không kéo cửa sổ khác của app),
        // cuối cùng trả focus về đúng cửa sổ vừa được chọn.
        for member in stillHidden {
            focusSingle(member)
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        if let triggerMember { focusSingle(triggerMember) }
        return rebinds
    }

    /// Focus đúng một cửa sổ (SkyLight); không được thì dùng API công khai.
    private static func focusSingle(_ member: Member) {
        AXUIElementSetAttributeValue(member.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let wid = member.windowID, SkyLight.focusSingleWindow(pid: member.pid, windowID: wid) {
            debugLog("focus \(member.item.appName) bằng SkyLight (wid=\(wid))")
        } else {
            AXUIElementSetAttributeValue(member.app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(member.window, kAXRaiseAction as CFString)
            debugLog("focus \(member.item.appName) bằng AXFrontmost")
        }
    }

    /// Thu nhỏ các cửa sổ của app trong nhóm mà KHÔNG thuộc nhóm, nếu chúng đè lên một cửa sổ của nhóm.
    /// Nhờ vậy lần sau bấm app trên Dock, macOS không đưa chúng lên che nhóm nữa.
    private static func minimizeOverlappingExtras(_ members: [(pid: pid_t, window: AXUIElement, name: String)]) {
        let groupFrames = members.compactMap { frameOf($0.window) }
        var minimized: [String] = []
        for pid in Set(members.map(\.pid)) {
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for w in windows {
                if members.contains(where: { CFEqual($0.window, w) }) { continue }
                guard stringAttribute(w, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
                      !boolAttribute(w, kAXMinimizedAttribute),
                      let frame = frameOf(w) else { continue }
                let covers = groupFrames.contains { g in
                    let overlap = g.intersection(frame)
                    return !overlap.isNull && overlap.width * overlap.height > 0.15 * g.width * g.height
                }
                if covers {
                    AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                    minimized.append("\(members.first { $0.pid == pid }?.name ?? "?"): \(stringAttribute(w, kAXTitleAttribute) ?? "")")
                }
            }
        }
        if !minimized.isEmpty { debugLog("glue minimize: \(minimized)") }
    }

    private static func boolAttribute(_ el: AXUIElement, _ attr: String) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return false }
        return (v as? Bool) ?? false
    }

    /// Cửa sổ có đang bị một cửa sổ khác (thuộc app khác) nằm trên và đè lên không.
    private static func isObstructed(_ pid: pid_t, _ window: AXUIElement, windowID: CGWindowID? = nil) -> Bool {
        guard let frame = frameOf(window),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return true }
        // Danh sách đi từ trên xuống dưới.
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 50, bounds.height > 50 else { continue }
            if let windowID, (info[kCGWindowNumber as String] as? CGWindowID) == windowID { return false }
            if ownerPID == pid {
                // Gặp chính cửa sổ này trước khi gặp cửa sổ nào che → không bị che.
                if windowID == nil && approximatelyEqual(bounds, frame, tolerance: 4) { return false }
                // Cửa sổ khác của cùng app nằm đè lên cũng tính là che.
                if windowID != nil, bounds.intersection(frame).width > 8, bounds.intersection(frame).height > 8 { return true }
                continue
            }
            if (info[kCGWindowAlpha as String] as? Double ?? 1) < 0.05 { continue }
            if bounds.intersection(frame).width > 8 && bounds.intersection(frame).height > 8 { return true }
        }
        return true   // không thấy trên màn hình (vd. ở Space khác) → coi như cần đưa lên
    }

    private static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Khung hiện tại của cửa sổ thật ứng với một app trong workspace (nil nếu app chưa chạy).
    static func currentFrame(of item: Workspace.Item) -> CGRect? {
        WindowResolver.resolve(item).flatMap { frameOf($0.window) }
    }

    // MARK: - Accessibility helpers

    private static func axWindow(pid: pid_t, windowID: CGWindowID, title: String?, frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        // Đúng mã cửa sổ → chắc chắn đúng cửa sổ đã chọn.
        if let exact = windows.first(where: { SkyLight.windowID(of: $0) == windowID }) { return exact }

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
    /// Kết quả lần đặt trước cho từng ô: nếu cửa sổ vẫn đúng như kết quả đó thì không đặt lại
    /// (vd. macOS đẩy cửa sổ xuống dưới thanh menu nên không bao giờ khớp đúng ô).
    @MainActor private static var lastPlaced: [String: CGRect] = [:]

    @MainActor
    private static func place(_ ax: AXUIElement, in cell: CGRect) {
        let key = "\(Int(cell.minX)),\(Int(cell.minY)),\(Int(cell.width)),\(Int(cell.height))-\(CFHash(ax))"
        if let current = frameOf(ax) {
            if approximatelyEqual(current, cell, tolerance: 3) { return }
            if let last = lastPlaced[key], approximatelyEqual(current, last, tolerance: 3) { return }
            // Cửa sổ cố định kích thước (vd. Simulator) đã nằm giữa ô sẵn.
            if current.width <= cell.width + 1, current.height <= cell.height + 1,
               abs(current.midX - cell.midX) <= 3, abs(current.midY - cell.midY) <= 3 { return }
        }

        // Gỡ trạng thái thu nhỏ nếu có.
        AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)

        setSize(ax, cell.size)
        if let sized = frameOf(ax), sized.width < cell.width - 1 || sized.height < cell.height - 1 {
            // Không co giãn được: đặt thẳng vào giữa ô, không qua góc ô (tránh nhảy 2 lần).
            setPosition(ax, CGPoint(x: cell.midX - sized.width / 2, y: cell.midY - sized.height / 2))
        } else {
            setPosition(ax, cell.origin)
            setSize(ax, cell.size)   // lần 2 để chắc khi app tự giới hạn kích thước theo màn hình
        }
        if let result = frameOf(ax) { lastPlaced[key] = result }
    }

    static func stringAttribute(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    static func frameOf(_ el: AXUIElement) -> CGRect? {
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
