import Foundation
import ServiceManagement

/// Tự mở EverythingInOne khi đăng nhập macOS (để tính năng gắn app luôn chạy).
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false

    private let setupKey = "loginItem.didSetup"

    init() {
        // Lần chạy đầu tiên: bật sẵn.
        if !UserDefaults.standard.bool(forKey: setupKey) {
            UserDefaults.standard.set(true, forKey: setupKey)
            set(true)
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            debugLog("LoginItem \(on ? "register" : "unregister") lỗi: \(error)")
        }
        refresh()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
