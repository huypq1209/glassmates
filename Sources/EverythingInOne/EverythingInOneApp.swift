import SwiftUI

@main
struct EverythingInOneApp: App {
    @StateObject private var workspaces: WorkspaceStore
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

        // Biểu tượng trên thanh menu: app vẫn chạy (và vẫn gắn app) khi đóng cửa sổ chính.
        MenuBarExtra("EverythingInOne", systemImage: "rectangle.3.group") {
            MenuBarContent()
                .environmentObject(workspaces)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var workspaces: WorkspaceStore
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
        Button("Mở EverythingInOne") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Thoát") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
