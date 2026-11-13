import SwiftUI
import AppKit

/// Trình chỉnh bố cục: hiển thị tất cả màn hình, kéo/đổi cỡ khung của từng app.
struct LayoutEditor: View {
    let workspace: Workspace

    @EnvironmentObject private var workspaces: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var screens: [ScreenInfo] = Screens.all()
    /// Khung tuyệt đối (toạ độ AX) của từng app, cùng thứ tự với workspace.items.
    @State private var rects: [CGRect] = []
    @State private var dragStart: CGRect?

    private let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tuỳ chỉnh vị trí — \(workspace.name)").font(.title3.bold())
            Text("Kéo khung để di chuyển (kéo sang màn hình khác được). Kéo ô vuông ở góc dưới phải để đổi kích thước.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                canvas(size: geo.size)
            }
            .frame(minHeight: 340)
            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            ForEach(Array(workspace.items.enumerated()), id: \.offset) { index, item in
                if index < rects.count { row(index: index, item: item) }
            }

            HStack {
                Button("Lấy vị trí cửa sổ hiện tại") { loadCurrent() }
                Button("Xem thử") { Task { await preview() } }
                Spacer()
                Button("Huỷ") { dismiss() }
                Button("Lưu") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 640)
        .onAppear(perform: setup)
    }

    // MARK: Canvas

    private struct Mapper {
        let union: CGRect
        let scale: CGFloat
        let offset: CGPoint

        func toCanvas(_ r: CGRect) -> CGRect {
            CGRect(x: offset.x + (r.minX - union.minX) * scale,
                   y: offset.y + (r.minY - union.minY) * scale,
                   width: r.width * scale, height: r.height * scale)
        }
    }

    private func mapper(for size: CGSize) -> Mapper {
        let union = screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull, union.width > 0, union.height > 0 else {
            return Mapper(union: .zero, scale: 1, offset: .zero)
        }
        let pad: CGFloat = 16
        let scale = min((size.width - 2 * pad) / union.width, (size.height - 2 * pad) / union.height)
        let offset = CGPoint(x: (size.width - union.width * scale) / 2,
                             y: (size.height - union.height * scale) / 2)
        return Mapper(union: union, scale: scale, offset: offset)
    }

    private func canvas(size: CGSize) -> some View {
        let m = mapper(for: size)
        return ZStack(alignment: .topLeading) {
            ForEach(screens) { screen in
                let c = m.toCanvas(screen.frame)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.6)))
                    .overlay(alignment: .bottomLeading) {
                        Text(screen.name).font(.caption2).foregroundStyle(.secondary).padding(4)
                    }
                    .frame(width: c.width, height: c.height)
                    .offset(x: c.minX, y: c.minY)
            }
            ForEach(rects.indices, id: \.self) { index in
                box(index: index, mapper: m)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "canvas")
    }

    private func box(index: Int, mapper m: Mapper) -> some View {
        let c = m.toCanvas(rects[index])
        let color = palette[index % palette.count]
        let name = workspace.items[index].appName

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 2))
                .overlay { Text(name).font(.caption.bold()).padding(2) }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .named("canvas"))
                        .onChanged { v in
                            let start = dragStart ?? rects[index]
                            dragStart = start
                            rects[index].origin = CGPoint(x: start.minX + v.translation.width / m.scale,
                                                          y: start.minY + v.translation.height / m.scale)
                        }
                        .onEnded { _ in finishDrag(index) }
                )

            Rectangle()
                .fill(color)
                .frame(width: 12, height: 12)
                .gesture(
                    DragGesture(coordinateSpace: .named("canvas"))
                        .onChanged { v in
                            let start = dragStart ?? rects[index]
                            dragStart = start
                            rects[index].size = CGSize(width: max(200, start.width + v.translation.width / m.scale),
                                                       height: max(150, start.height + v.translation.height / m.scale))
                        }
                        .onEnded { _ in finishDrag(index) }
                )
        }
        .frame(width: max(c.width, 1), height: max(c.height, 1))
        .offset(x: c.minX, y: c.minY)
    }

    private func finishDrag(_ index: Int) {
        dragStart = nil
        rects[index] = Screens.clamp(rects[index], in: screens)
    }

    // MARK: Hàng điều khiển từng app

    private func row(index: Int, item: Workspace.Item) -> some View {
        HStack {
            Circle().fill(palette[index % palette.count]).frame(width: 10, height: 10)
            Text("\(index + 1). \(item.appName)").frame(width: 160, alignment: .leading)

            Picker("Màn hình", selection: Binding(
                get: { Screens.screen(for: rects[index], in: screens)?.id ?? "" },
                set: { moveToScreen(index, screenID: $0) }
            )) {
                ForEach(screens) { Text($0.name).tag($0.id) }
            }
            .frame(width: 260)

            Menu("Vị trí nhanh") {
                Button("Toàn màn hình") { quick(index, 0, 0, 1, 1) }
                Button("Nửa trái") { quick(index, 0, 0, 0.5, 1) }
                Button("Nửa phải") { quick(index, 0.5, 0, 0.5, 1) }
                Button("2/3 trái") { quick(index, 0, 0, 2.0 / 3, 1) }
                Button("1/3 phải") { quick(index, 2.0 / 3, 0, 1.0 / 3, 1) }
                Button("1/3 trái") { quick(index, 0, 0, 1.0 / 3, 1) }
                Button("2/3 phải") { quick(index, 1.0 / 3, 0, 2.0 / 3, 1) }
                Button("Nửa trên") { quick(index, 0, 0, 1, 0.5) }
                Button("Nửa dưới") { quick(index, 0, 0.5, 1, 0.5) }
            }
            .fixedSize()

            Spacer()
            Text(sizeText(rects[index])).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func sizeText(_ r: CGRect) -> String {
        String(localized: "\(Int(r.width))×\(Int(r.height)) tại (\(Int(r.minX)), \(Int(r.minY)))")
    }

    private func quick(_ index: Int, _ fx: Double, _ fy: Double, _ fw: Double, _ fh: Double) {
        guard let v = Screens.screen(for: rects[index], in: screens)?.visible else { return }
        let gap: CGFloat = 4
        rects[index] = CGRect(x: v.minX + fx * v.width + gap, y: v.minY + fy * v.height + gap,
                              width: fw * v.width - 2 * gap, height: fh * v.height - 2 * gap)
    }

    /// Chuyển khung sang màn hình khác, giữ nguyên vị trí tương đối.
    private func moveToScreen(_ index: Int, screenID: String) {
        guard let target = screens.first(where: { $0.id == screenID }),
              var p = Screens.placement(for: rects[index], in: screens) else { return }
        p.screenID = target.id
        if let r = Screens.rect(for: p, in: screens) {
            rects[index] = Screens.clamp(r, in: screens)
        }
    }

    // MARK: Khởi tạo / lưu

    private func setup() {
        screens = Screens.all()
        let fallback = WindowArranger.rects(count: workspace.items.count, preset: .sideBySide,
                                            in: WindowArranger.workArea())
        rects = workspace.items.enumerated().map { index, item in
            if let p = item.placement, let r = Screens.rect(for: p, in: screens) { return r }
            if let r = WindowArranger.currentFrame(of: item) { return r }
            return index < fallback.count ? fallback[index] : CGRect(x: 100, y: 100, width: 800, height: 600)
        }
    }

    private func loadCurrent() {
        for (index, item) in workspace.items.enumerated() where index < rects.count {
            if let r = WindowArranger.currentFrame(of: item) { rects[index] = r }
        }
    }

    private var placements: [Placement?] {
        rects.map { Screens.placement(for: $0, in: screens) }
    }

    private func preview() async {
        var temp = workspace
        for (index, p) in placements.enumerated() where index < temp.items.count {
            temp.items[index].placement = p
        }
        temp.layout = .custom
        let rebinds = await WindowArranger.glue(temp, trigger: nil, forceArrange: true)
        workspaces.applyRebinds(rebinds, workspaceID: workspace.id)
    }

    private func save() {
        debugLog("LayoutEditor.save \(workspace.name): \(placements)")
        workspaces.setPlacements(workspace.id, placements)
        workspaces.status = String(localized: "Đã lưu vị trí tuỳ chỉnh cho \(workspace.name).")
        dismiss()
    }
}
