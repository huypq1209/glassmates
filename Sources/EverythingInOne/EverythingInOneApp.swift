import SwiftUI

@main
struct EverythingInOneApp: App {
    @StateObject private var workspaces: WorkspaceStore
    @StateObject private var loginItem = LoginItem()
    private let glue: GlueManager

    init() {
        let store = WorkspaceStore()
        _workspaces = StateObject(wrappedValue: store)
        glue = GlueManager(store: store)
    }

    var body: some Scene {
        WindowGroup("EverythingInOne", id: "main") {
            ContentView()
                .environmentObject(workspaces)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            // Cmd+Q chỉ đóng cửa sổ; app vẫn chạy trên thanh menu để gắn app tiếp tục hoạt động.
            // Muốn thoát hẳn: dùng "Thoát" trên biểu tượng thanh menu.
            CommandGroup(replacing: .appTermination) {
                Button("Đóng cửa sổ (vẫn chạy trên thanh menu)") { closeMainWindows() }
                    .keyboardShortcut("q")
            }
        }

        // Biểu tượng trên thanh menu: app vẫn chạy (và vẫn gắn app) khi đóng cửa sổ chính.
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(workspaces)
                .environmentObject(loginItem)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }

    private func closeMainWindows() {
        NSApp.windows
            .filter { $0.isVisible && $0.styleMask.contains(.titled) }
            .forEach { $0.close() }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var workspaces: WorkspaceStore
    @EnvironmentObject private var loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if workspaces.workspaces.isEmpty {
            Text("Chưa có workspace")
        }
        ForEach(workspaces.workspaces) { ws in
            Toggle("Gắn: \(ws.name)", isOn: Binding(
                get: { ws.glued },
                set: { workspaces.setGlued(ws.id, $0) }
            ))
        }
        Divider()
        Toggle("Mở cùng máy khi đăng nhập", isOn: Binding(
            get: { loginItem.enabled },
            set: { loginItem.set($0) }
        ))
        if loginItem.needsApproval {
            Button("Cần cho phép trong Login Items…") { loginItem.openSettings() }
        }
        Divider()
        Button("Mở EverythingInOne") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Thoát hẳn") { NSApp.terminate(nil) }
    }
}
