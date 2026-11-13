import Foundation
import AppKit
import ApplicationServices
import Combine

/// Theo dõi cửa sổ được focus. Chỉ khi đúng một cửa sổ thuộc workspace đang bật "Gắn" được focus,
/// mới đưa các cửa sổ còn lại trong nhóm lên. Các cửa sổ khác của cùng app (vd. Chrome khác) không bị đụng tới.
///
/// Nghe 2 nguồn:
///  - Chuyển app (NSWorkspace.didActivateApplication): bấm cửa sổ, Dock, ⌘-Tab.
///  - Chuyển cửa sổ bên trong cùng app (AXObserver kAXFocusedWindowChanged): vd. từ Chrome A sang Chrome B.
@MainActor
final class GlueManager {
    private let store: WorkspaceStore
    private var tokens: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var axObservers: [pid_t: AXObserver] = [:]
    private var busy = false
    private var cooldownUntil = Date.distantPast
    private var lastTrigger: (windowID: CGWindowID, at: Date)?

    init(store: WorkspaceStore) {
        self.store = store
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appActivated(app) }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshObservers() }
            })
        }
        store.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshObservers() }
            .store(in: &cancellables)
        refreshObservers()
    }

    // MARK: Sự kiện

    private func appActivated(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let pid = app.processIdentifier
        // Chờ một nhịp để macOS cập nhật cửa sổ đang focus của app (vd. khi bấm Dock).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self.windowFocused(pid: pid, source: "activate")
        }
    }

    /// Gọi từ AXObserver khi cửa sổ focus của một app thay đổi.
    fileprivate func focusChanged(pid: pid_t) {
        // Chỉ quan tâm khi app đó đang ở trên cùng (người dùng đang thao tác với nó).
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        windowFocused(pid: pid, source: "focus")
    }

    private func windowFocused(pid: pid_t, source: String) {
        let focused = WindowResolver.focusedWindow(pid: pid)
        debugLog("\(source) pid=\(pid) busy=\(busy) cooldown=\(Date() < cooldownUntil) ax=\(AXIsProcessTrusted()) focused=\(focused != nil) wid=\(focused.flatMap { WindowResolver.windowID(of: $0) }.map(String.init) ?? "nil")")
        guard !busy, Date() > cooldownUntil, AXIsProcessTrusted(),
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              let window = WindowResolver.focusedWindow(pid: pid),
              let windowID = WindowResolver.windowID(of: window) else { return }
        if let last = lastTrigger, last.windowID == windowID, Date().timeIntervalSince(last.at) < 0.4 { return }

        guard let (workspace, itemIndex) = findMember(bundleID: bundleID, windowID: windowID) else {
            debugLog("\(source) \(bundleID) wid=\(windowID): không thuộc nhóm nào → bỏ qua")
            return
        }
        debugLog("\(source) \(bundleID) wid=\(windowID): thuộc \(workspace.name)#\(itemIndex)")
        lastTrigger = (windowID, Date())
        busy = true
        Task { @MainActor in
            let rebinds = await WindowArranger.glue(workspace, trigger: windowID)
            store.applyRebinds(rebinds, workspaceID: workspace.id)
            busy = false
            cooldownUntil = Date().addingTimeInterval(0.6)
        }
    }

    /// Workspace đang bật Gắn có chứa đúng cửa sổ này.
    private func findMember(bundleID: String, windowID: CGWindowID) -> (Workspace, Int)? {
        for ws in store.workspaces where ws.glued {
            if let i = ws.items.firstIndex(where: { $0.bundleID == bundleID && $0.windowID == windowID }) {
                return (ws, i)
            }
        }
        // Mục chưa có mã cửa sổ (dữ liệu cũ) hoặc cửa sổ cũ đã đóng: nhận lại nếu xác định được chắc chắn
        // đúng là cửa sổ đang focus.
        for ws in store.workspaces where ws.glued {
            for (i, item) in ws.items.enumerated() where item.bundleID == bundleID {
                let stillExists = item.windowID.map { id in
                    WindowResolver.processes(of: bundleID).contains { pid in
                        WindowResolver.standardWindows(pid: pid).contains { WindowResolver.windowID(of: $0) == id }
                    }
                } ?? false
                guard !stillExists else { continue }   // cửa sổ đã lưu vẫn còn → đây là cửa sổ khác của app
                let expected = item.placement.flatMap { Screens.rect(for: $0, in: Screens.all()) }
                if let r = WindowResolver.resolve(item, expectedFrame: expected), r.windowID == windowID {
                    store.rebind(ws.id, itemIndex: i, windowID: windowID,
                                 title: WindowArranger.stringAttribute(r.window, kAXTitleAttribute))
                    if let updated = store.workspaces.first(where: { $0.id == ws.id }) { return (updated, i) }
                }
            }
        }
        return nil
    }

    // MARK: AXObserver cho các app trong nhóm

    private func refreshObservers() {
        let bundleIDs = Set(store.workspaces.filter(\.glued).flatMap { $0.items.map(\.bundleID) })
        let wanted = Set(bundleIDs.flatMap { WindowResolver.processes(of: $0) })

        for (pid, observer) in axObservers where !wanted.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObservers[pid] = nil
        }
        for pid in wanted where axObservers[pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(pid, glueAXCallback, &observer) == .success, let observer else { continue }
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let app = AXUIElementCreateApplication(pid)
            AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
            AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObservers[pid] = observer
        }
    }
}

/// Callback C của AXObserver (chạy trên main run loop).
private func glueAXCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                            _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let manager = Unmanaged<GlueManager>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    MainActor.assumeIsolated { manager.focusChanged(pid: pid) }
}
