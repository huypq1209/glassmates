import Foundation
import AppKit
import ScreenCaptureKit
import ApplicationServices

/// Danh sách cửa sổ có thể chụp + các ô (tile) đang được hiển thị.
@MainActor
final class WindowStore: ObservableObject {
    struct Tile: Identifiable {
        let id: CGWindowID
        let window: SCWindow
        let capture: WindowCapture
    }

    @Published var windows: [SCWindow] = []
    @Published var tiles: [Tile] = []
    @Published var hasPermission = CGPreflightScreenCaptureAccess()
    @Published var errorMessage: String?

    func requestPermission() {
        hasPermission = CGRequestScreenCaptureAccess()
    }

    func refresh() async {
        hasPermission = CGPreflightScreenCaptureAccess()
        guard hasPermission else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let myBundle = Bundle.main.bundleIdentifier
            windows = content.windows
                .filter {
                    $0.windowLayer == 0
                        && $0.frame.width > 120 && $0.frame.height > 80
                        && ($0.title?.isEmpty == false)
                        && $0.owningApplication != nil
                        && $0.owningApplication?.bundleIdentifier != myBundle
                }
                .sorted {
                    let a = $0.owningApplication?.applicationName ?? ""
                    let b = $1.owningApplication?.applicationName ?? ""
                    return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isShown(_ window: SCWindow) -> Bool {
        tiles.contains { $0.id == window.windowID }
    }

    func toggle(_ window: SCWindow) {
        if let index = tiles.firstIndex(where: { $0.id == window.windowID }) {
            remove(at: index)
        } else {
            add(window)
        }
    }

    private func add(_ window: SCWindow) {
        // Cần quyền Accessibility để chuyển chuột / phím về app gốc.
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        let capture = WindowCapture(window: window)
        tiles.append(Tile(id: window.windowID, window: window, capture: capture))
    }

    func remove(at index: Int) {
        let tile = tiles.remove(at: index)
        Task { await tile.capture.stop() }
    }

    func remove(id: CGWindowID) {
        if let index = tiles.firstIndex(where: { $0.id == id }) {
            remove(at: index)
        }
    }

    /// Đưa app gốc của cửa sổ lên trước.
    func activate(_ window: SCWindow) {
        guard let pid = window.owningApplication?.processID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }
}
