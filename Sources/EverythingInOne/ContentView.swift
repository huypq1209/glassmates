import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @StateObject private var store = WindowStore()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .task { await store.refresh() }
    }

    // MARK: Sidebar — chọn cửa sổ để chụp

    private var sidebar: some View {
        List {
            ForEach(grouped, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.windows, id: \.windowID) { window in
                        Button {
                            store.toggle(window)
                        } label: {
                            HStack {
                                Image(systemName: store.isShown(window) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.isShown(window) ? Color.accentColor : .secondary)
                                Text(window.title ?? "")
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Làm mới", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var grouped: [(name: String, windows: [SCWindow])] {
        Dictionary(grouping: store.windows) { $0.owningApplication?.applicationName ?? "Khác" }
            .map { (name: $0.key, windows: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Detail — lưới các ô đang chụp

    @ViewBuilder
    private var detail: some View {
        if !store.hasPermission {
            permissionView
        } else if store.tiles.isEmpty {
            ContentUnavailableView(
                "Chưa chọn cửa sổ nào",
                systemImage: "rectangle.on.rectangle",
                description: Text("Chọn cửa sổ ở thanh bên trái để hiển thị tại đây.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 12)], spacing: 12) {
                    ForEach(store.tiles) { tile in
                        TileView(tile: tile, store: store)
                    }
                }
                .padding(12)
            }
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Cần quyền Screen Recording", systemImage: "lock.rectangle")
        } description: {
            Text("Bật quyền cho EverythingInOne trong System Settings → Privacy & Security → Screen & System Audio Recording, rồi mở lại app.")
        } actions: {
            Button("Yêu cầu quyền") { store.requestPermission() }
            Button("Mở System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
    }
}

struct TileView: View {
    let tile: WindowStore.Tile
    @ObservedObject var store: WindowStore
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(tile.window.owningApplication?.applicationName ?? "") — \(tile.window.title ?? "")")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button {
                    store.activate(tile.window)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Đưa app gốc lên trước")
                Button {
                    store.remove(id: tile.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .help("Bỏ ô này")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            ZStack {
                CaptureView(capture: tile.capture)
                if let failure {
                    Text(failure)
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .aspectRatio(tile.window.frame.width / max(tile.window.frame.height, 1), contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .task {
            tile.capture.onStop = { error in
                failure = error?.localizedDescription ?? "Luồng chụp đã dừng"
            }
            do {
                try await tile.capture.start()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
