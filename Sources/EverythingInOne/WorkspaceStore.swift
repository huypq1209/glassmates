import Foundation
import AppKit
import ScreenCaptureKit

struct Workspace: Codable, Identifiable, Equatable {
    struct Item: Codable, Equatable {
        var bundleID: String
        var appName: String
        var title: String
        /// Vị trí tuỳ chỉnh (dùng khi bố cục = Tuỳ chỉnh).
        var placement: Placement? = nil
        /// Mã cửa sổ (CGWindowID) — nhận diện đúng cửa sổ khi app có nhiều cửa sổ.
        var windowID: UInt32? = nil
    }

    var id = UUID()
    var name: String
    var layout: LayoutPreset
    var items: [Item]
    /// Gắn các app: kích hoạt 1 app thì các app còn lại cùng nổi lên.
    var glued = true
    /// Mỗi lần nhóm nổi lên thì xếp lại theo bố cục.
    var rearrange = true
    /// Thu nhỏ các cửa sổ khác (không thuộc nhóm) của các app trong nhóm nếu chúng đè lên nhóm.
    var minimizeOthers = false

    init(name: String, layout: LayoutPreset, items: [Item]) {
        self.name = name
        self.layout = layout
        self.items = items
    }

    // Đọc được cả dữ liệu cũ chưa có glued / rearrange.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        layout = try c.decode(LayoutPreset.self, forKey: .layout)
        items = try c.decode([Item].self, forKey: .items)
        glued = try c.decodeIfPresent(Bool.self, forKey: .glued) ?? true
        rearrange = try c.decodeIfPresent(Bool.self, forKey: .rearrange) ?? true
        minimizeOthers = try c.decodeIfPresent(Bool.self, forKey: .minimizeOthers) ?? false
    }
}

/// Lưu / mở lại workspace (nhóm app + bố cục).
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published var status: String?

    private let key = "workspaces.v1"

    init() { load() }

    // MARK: Lưu trữ

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Workspace].self, from: data) else { return }
        workspaces = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(workspaces)
            UserDefaults.standard.set(data, forKey: key)
            let summary = workspaces.map { ws in
                "\(ws.name)[\(ws.layout.rawValue)] placements=\(ws.items.filter { $0.placement != nil }.count)/\(ws.items.count)"
            }
            debugLog("persist: \(summary.joined(separator: "; "))")
        } catch {
            debugLog("persist LỖI: \(error)")
            status = String(localized: "Không lưu được: \(error.localizedDescription)")
        }
    }

    func save(name: String, layout: LayoutPreset, windows: [SCWindow]) {
        var items = windows.compactMap { w -> Workspace.Item? in
            guard let app = w.owningApplication else { return nil }
            return Workspace.Item(bundleID: app.bundleIdentifier, appName: app.applicationName,
                                  title: w.title ?? "", windowID: w.windowID)
        }
        guard !items.isEmpty else { return }
        if let index = workspaces.firstIndex(where: { $0.name == name }) {
            // Lưu đè: giữ lại vị trí tuỳ chỉnh của các app đã có trong workspace.
            let old = workspaces[index].items
            for i in items.indices {
                let same = old.first(where: { $0.windowID != nil && $0.windowID == items[i].windowID })
                    ?? old.first(where: { $0.bundleID == items[i].bundleID && $0.windowID == nil })
                items[i].placement = same?.placement
            }
            let keepsCustom = workspaces[index].layout == .custom && items.contains { $0.placement != nil }
            workspaces[index].layout = keepsCustom ? .custom : layout
            workspaces[index].items = items
        } else {
            workspaces.append(Workspace(name: name, layout: layout, items: items))
        }
        persist()
    }

    func setGlued(_ id: UUID, _ value: Bool) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].glued = value
        persist()
    }

    func setRearrange(_ id: UUID, _ value: Bool) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].rearrange = value
        persist()
    }

    /// Lưu vị trí tuỳ chỉnh cho từng app và chuyển workspace sang bố cục Tuỳ chỉnh.
    func setPlacements(_ id: UUID, _ placements: [Placement?]) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        for (index, placement) in placements.enumerated() where index < workspaces[i].items.count {
            workspaces[i].items[index].placement = placement
        }
        workspaces[i].layout = .custom
        // Đã đặt vị trí thì phải áp dụng, không thì gắn app chỉ đưa lên mà không về đúng chỗ.
        workspaces[i].rearrange = true
        persist()
    }

    func setMinimizeOthers(_ id: UUID, _ value: Bool) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].minimizeOthers = value
        persist()
    }

    func setLayout(_ id: UUID, _ value: LayoutPreset) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].layout = value
        persist()
    }

    /// Thêm một cửa sổ (app) vào workspace đã lưu. Bố cục Tuỳ chỉnh: lấy vị trí hiện tại làm vị trí mặc định.
    func addItem(_ id: UUID, window: SCWindow) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }),
              let app = window.owningApplication,
              !workspaces[i].items.contains(where: { $0.windowID == window.windowID }) else { return }
        var item = Workspace.Item(bundleID: app.bundleIdentifier, appName: app.applicationName,
                                  title: window.title ?? "", windowID: window.windowID)
        if workspaces[i].layout == .custom {
            item.placement = Screens.placement(for: window.frame, in: Screens.all())
        }
        workspaces[i].items.append(item)
        persist()
        status = String(localized: "Đã thêm \(item.appName) vào \(workspaces[i].name).")
    }

    /// Cập nhật mã cửa sổ (và tiêu đề) khi nhận lại được cửa sổ của một mục, để lần sau khớp chính xác.
    func rebind(_ id: UUID, itemIndex: Int, windowID: UInt32, title: String?) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[i].items.indices.contains(itemIndex) else { return }
        var item = workspaces[i].items[itemIndex]
        guard item.windowID != windowID else { return }
        item.windowID = windowID
        if let title, !title.isEmpty { item.title = title }
        workspaces[i].items[itemIndex] = item
        debugLog("rebind \(workspaces[i].name)#\(itemIndex) \(item.appName) → wid=\(windowID)")
        persist()
    }

    func removeItem(_ id: UUID, at index: Int) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[i].items.indices.contains(index) else { return }
        let removed = workspaces[i].items.remove(at: index)
        persist()
        status = String(localized: "Đã bỏ \(removed.appName) khỏi \(workspaces[i].name).")
    }

    func delete(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        persist()
    }

    // MARK: Mở workspace

    /// Mở app còn thiếu, tìm cửa sổ tương ứng, rồi xếp và đưa lên trước.
    func open(_ workspace: Workspace, store: WindowStore) async {
        guard AXIsProcessTrusted() else {
            status = String(localized: "Cần quyền Accessibility để xếp cửa sổ.")
            return
        }
        status = String(localized: "Đang mở \(workspace.name)…")
        await store.refresh()

        var found: [SCWindow] = []
        var missing: [String] = []

        for item in workspace.items {
            var window = match(item, in: store.windows)
            if window == nil {
                launchIfNeeded(item)
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await store.refresh()
                    window = match(item, in: store.windows)
                    if window != nil { break }
                }
            }
            if let window { found.append(window) } else { missing.append(item.appName) }
        }

        if workspace.layout == .custom {
            let rebinds = await WindowArranger.glue(workspace, trigger: nil, forceArrange: true)
            applyRebinds(rebinds, workspaceID: workspace.id)
            status = missing.isEmpty
                ? String(localized: "Đã xếp \(workspace.name).")
                : String(localized: "Đã xếp \(workspace.name). Không mở được: \(missing.joined(separator: ", ")).")
            return
        }

        let result = await WindowArranger.arrange(found, preset: workspace.layout)
        let notArranged = missing + result.missed
        status = notArranged.isEmpty
            ? String(localized: "Đã xếp \(result.arranged) cửa sổ.")
            : String(localized: "Đã xếp \(result.arranged) cửa sổ. Không xếp được: \(notArranged.joined(separator: ", ")).")
    }

    func applyRebinds(_ rebinds: [WindowArranger.Rebind], workspaceID: UUID) {
        for r in rebinds { rebind(workspaceID, itemIndex: r.itemIndex, windowID: r.windowID, title: r.title) }
    }

    /// Cửa sổ ứng với một mục: đúng mã cửa sổ; không thì tiêu đề trùng khớp; không thì app chỉ có 1 cửa sổ.
    private func match(_ item: Workspace.Item, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { $0.owningApplication?.bundleIdentifier == item.bundleID }
        if let id = item.windowID, let hit = candidates.first(where: { $0.windowID == id }) { return hit }
        let sameTitle = candidates.filter { $0.title == item.title }
        if sameTitle.count == 1 { return sameTitle[0] }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func launchIfNeeded(_ item: Workspace.Item) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID)
        guard running.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
