import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @StateObject private var store = WindowStore()
    @EnvironmentObject private var workspaces: WorkspaceStore
    @State private var layout: LayoutPreset = .sideBySide
    @State private var showSave = false
    @State private var saveName = ""
    @State private var showPreview = false
    @AppStorage("skylightInput") private var skylightInput = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .safeAreaInset(edge: .bottom) { workspaceBar }
        }
        .task { await store.refresh() }
    }

    // MARK: Sidebar — chọn cửa sổ để chụp

    private var sidebar: some View {
        List {
            if !workspaces.workspaces.isEmpty {
                Section("Workspace") {
                    ForEach(workspaces.workspaces) { ws in
                        WorkspaceRow(workspace: ws, store: store)
                    }
                }
            }
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

    // MARK: Thanh workspace — xếp cửa sổ thật

    private var workspaceBar: some View {
        HStack(spacing: 10) {
            Picker("Bố cục", selection: $layout) {
                ForEach(LayoutPreset.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 220)

            Button {
                let windows = store.tiles.map(\.window)
                Task {
                    let result = await WindowArranger.arrange(windows, preset: layout)
                    workspaces.status = result.missed.isEmpty
                        ? "Đã xếp \(result.arranged) cửa sổ."
                        : "Đã xếp \(result.arranged). Không xếp được: \(result.missed.joined(separator: ", "))."
                }
            } label: {
                Label("Xếp cửa sổ thật", systemImage: "rectangle.3.group")
            }
            .disabled(store.tiles.isEmpty || !store.hasAccessibility)
            .help("Xếp các cửa sổ đã chọn cạnh nhau và đưa lên trước")

            Button {
                saveName = ""
                showSave = true
            } label: {
                Label("Lưu workspace…", systemImage: "square.and.arrow.down")
            }
            .disabled(store.tiles.isEmpty)

            Menu {
                if workspaces.workspaces.isEmpty {
                    Text("Chưa có workspace")
                }
                ForEach(workspaces.workspaces) { ws in
                    Button("Mở: \(ws.name) (\(ws.items.count) app)") {
                        layout = ws.layout
                        Task { await workspaces.open(ws, store: store) }
                    }
                }
                if !workspaces.workspaces.isEmpty {
                    Divider()
                    ForEach(workspaces.workspaces) { ws in
                        Button("Xoá: \(ws.name)", role: .destructive) { workspaces.delete(ws) }
                    }
                }
            } label: {
                Label("Workspace", systemImage: "square.stack.3d.up")
            }
            .fixedSize()

            Toggle("Xem trước", isOn: $showPreview)
                .toggleStyle(.checkbox)
                .help("Hiện ảnh chụp trực tiếp các cửa sổ đã chọn (chỉ để xem, không thao tác được)")

            Toggle("Thao tác trong ô (thử nghiệm)", isOn: $skylightInput)
                .toggleStyle(.checkbox)
                .help("Gửi chuột/phím vào app gốc qua SkyLight khi xem trước. Cần bật \"Xem trước\".")

            Spacer()

            if let status = workspaces.status {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .alert("Lưu workspace", isPresented: $showSave) {
            TextField("Tên workspace", text: $saveName)
            Button("Lưu") {
                let name = saveName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                workspaces.save(name: name, layout: layout, windows: store.tiles.map(\.window))
                workspaces.status = "Đã lưu workspace \(name)."
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Lưu các cửa sổ đang chọn và bố cục \(layout.title). Workspace mới được bật Gắn sẵn: kích hoạt 1 app thì các app còn lại cùng nổi lên.")
        }
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
            VStack(spacing: 0) {
                if !store.hasAccessibility { accessibilityBanner }
                if showPreview { grid } else { selectionList }
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Chưa có quyền Accessibility nên không thao tác (chuột/phím) được trong ô.")
                .font(.callout)
            Spacer()
            Button("Cấp quyền") { store.requestAccessibility() }
            Button("Mở System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding(8)
        .background(.yellow.opacity(0.15))
    }

    /// Danh sách cửa sổ đã chọn theo thứ tự (cửa sổ đầu là cửa sổ chính của bố cục).
    private var selectionList: some View {
        List {
            Section("Đã chọn — thứ tự quyết định vị trí trong bố cục") {
                ForEach(Array(store.tiles.enumerated()), id: \.element.id) { index, tile in
                    HStack {
                        Text("\(index + 1)").font(.headline).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(tile.window.owningApplication?.applicationName ?? "")
                            Text(tile.window.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { store.remove(id: tile.id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Text("Nhấn \"Xếp cửa sổ thật\" để xếp các cửa sổ này cạnh nhau, rồi thao tác trực tiếp trên chúng.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Chia đều không gian cho các ô, ô nào cũng lấp đầy phần của mình (nội dung giữ đúng tỉ lệ app gốc).
    private var grid: some View {
        GeometryReader { geo in
            let count = max(store.tiles.count, 1)
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            let gap: CGFloat = 12
            let w = max((geo.size.width - gap * CGFloat(cols + 1)) / CGFloat(cols), 120)
            let h = max((geo.size.height - gap * CGFloat(rows + 1)) / CGFloat(rows), 120)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: gap), count: cols), spacing: gap) {
                ForEach(store.tiles) { tile in
                    TileView(tile: tile, store: store)
                        .frame(width: w, height: h)
                }
            }
            .padding(gap)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary).allowsHitTesting(false))
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

/// Một workspace trong thanh bên: bật/tắt gắn, chọn bố cục, xếp lại mỗi lần.
struct WorkspaceRow: View {
    let workspace: Workspace
    @ObservedObject var store: WindowStore
    @EnvironmentObject private var workspaces: WorkspaceStore
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workspace.name).font(.headline)
                Spacer()
                Toggle("Gắn", isOn: Binding(
                    get: { workspace.glued },
                    set: { workspaces.setGlued(workspace.id, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            Text(workspace.items.map(\.appName).joined(separator: " + "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Picker("Bố cục", selection: Binding(
                get: { workspace.layout },
                set: { workspaces.setLayout(workspace.id, $0) }
            )) {
                ForEach(LayoutPreset.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            Toggle("Xếp lại bố cục mỗi lần", isOn: Binding(
                get: { workspace.rearrange },
                set: { workspaces.setRearrange(workspace.id, $0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            Button("Tuỳ chỉnh vị trí…") { showEditor = true }
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEditor) {
            LayoutEditor(workspace: workspace)
                .environmentObject(workspaces)
        }
        .contextMenu {
            Button("Mở và xếp ngay") { Task { await workspaces.open(workspace, store: store) } }
            Button("Xoá", role: .destructive) { workspaces.delete(workspace) }
        }
    }
}
