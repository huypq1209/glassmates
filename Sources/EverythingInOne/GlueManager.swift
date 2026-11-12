import Foundation
import AppKit
import ApplicationServices

/// Theo dõi app được kích hoạt. Nếu app đó thuộc một workspace đang bật "Gắn",
/// đưa các app còn lại trong nhóm lên cùng (và xếp lại bố cục nếu được bật).
@MainActor
final class GlueManager {
    private let store: WorkspaceStore
    private var observer: NSObjectProtocol?
    private var busy = false
    private var cooldownUntil = Date.distantPast

    init(store: WorkspaceStore) {
        self.store = store
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.handleActivation(app) }
        }
    }

    private func handleActivation(_ app: NSRunningApplication?) {
        // Bỏ qua các lần kích hoạt do chính mình gây ra (tránh vòng lặp).
        guard !busy, Date() > cooldownUntil, AXIsProcessTrusted(),
              let app, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              let workspace = store.workspaces.first(where: { ws in
                  ws.glued && ws.items.contains { $0.bundleID == bundleID }
              })
        else { return }

        busy = true
        Task { @MainActor in
            await WindowArranger.glue(workspace, triggerPID: app.processIdentifier)
            busy = false
            cooldownUntil = Date().addingTimeInterval(0.6)
        }
    }
}
