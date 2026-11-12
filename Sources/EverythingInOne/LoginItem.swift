import Foundation
import ServiceManagement

/// Tự mở Glassmates khi đăng nhập macOS (để tính năng gắn app luôn chạy).
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false

    private let setupKey = "loginItem.didSetup"
    /// Ý muốn của người dùng (bật/tắt), tách khỏi trạng thái hệ thống.
    private let wantedKey = "loginItem.wanted"

    init() {
        let defaults = UserDefaults.standard
        // Lần chạy đầu tiên: bật sẵn.
        if !defaults.bool(forKey: setupKey) {
            defaults.set(true, forKey: setupKey)
            defaults.set(true, forKey: wantedKey)
        }
        // Đăng ký lại mỗi lần chạy để mục đăng nhập luôn trỏ tới đúng file .app hiện tại
        // (vd. sau khi đổi tên hoặc dời app).
        if defaults.object(forKey: wantedKey) as? Bool ?? true {
            set(true)
        } else {
            refresh()
        }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: wantedKey)
        do {
            if on {
                // Gỡ bản cũ (có thể trỏ tới đường dẫn cũ) rồi đăng ký lại.
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
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
