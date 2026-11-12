import Foundation
import AppKit
import ApplicationServices

/// THỬ NGHIỆM: dùng API riêng (không công khai) của macOS để gửi chuột/phím cho app đang chạy nền
/// mà không đưa nó lên trước. Có thể ngừng hoạt động sau khi macOS cập nhật.
enum SkyLight {
    private typealias PostEventRecordTo = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Int32
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias EventPostToPid = @convention(c) (pid_t, UnsafeRawPointer) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static let postEventRecordTo: PostEventRecordTo? = {
        guard let s = dlsym(handle, "SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(s, to: PostEventRecordTo.self)
    }()

    private static let getProcessForPID: GetProcessForPID? = {
        guard let s = dlsym(rtldDefault, "GetProcessForPID") else { return nil }
        return unsafeBitCast(s, to: GetProcessForPID.self)
    }()

    private static let eventPostToPid: EventPostToPid? = {
        guard let s = dlsym(handle, "SLEventPostToPid") else { return nil }
        return unsafeBitCast(s, to: EventPostToPid.self)
    }()

    private typealias SetFrontProcessWithOptions = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> Int32
    private typealias AXGetWindow = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt32>) -> Int32

    private static let setFrontProcessWithOptions: SetFrontProcessWithOptions? = {
        guard let s = dlsym(handle, "_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(s, to: SetFrontProcessWithOptions.self)
    }()

    private static let axGetWindow: AXGetWindow? = {
        guard let s = dlsym(rtldDefault, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(s, to: AXGetWindow.self)
    }()

    /// CGWindowID của một cửa sổ Accessibility.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: UInt32 = 0
        let err = axGetWindow(Unmanaged.passUnretained(element).toOpaque(), &id)
        return err == 0 && id != 0 ? id : nil
    }

    /// Đưa đúng MỘT cửa sổ lên trước và cho app của nó focus, không kéo các cửa sổ khác của app lên theo.
    @discardableResult
    static func focusSingleWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcessWithOptions, let getProcessForPID else { return false }
        var psn = [UInt32](repeating: 0, count: 2)
        guard psn.withUnsafeMutableBytes({ getProcessForPID(pid, $0.baseAddress!) }) == 0 else { return false }
        let userGenerated: UInt32 = 0x200
        let status = psn.withUnsafeBytes { setFrontProcessWithOptions($0.baseAddress!, windowID, userGenerated) }
        focusWithoutRaise(pid: pid, windowID: windowID)   // make key window
        return status == 0
    }

    static var isAvailable: Bool {
        postEventRecordTo != nil && getProcessForPID != nil
    }

    static var summary: String {
        "handle=\(handle != nil) postRecord=\(postEventRecordTo != nil) getPSN=\(getProcessForPID != nil) postToPid=\(eventPostToPid != nil)"
    }

    /// Đánh dấu cửa sổ của app đích là "đang active + key" mà không raise.
    @discardableResult
    static func focusWithoutRaise(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let postEventRecordTo, let getProcessForPID else { return false }

        // ProcessSerialNumber = 2 x UInt32
        var psn = [UInt32](repeating: 0, count: 2)
        guard psn.withUnsafeMutableBytes({ getProcessForPID(pid, $0.baseAddress!) }) == 0 else { return false }

        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var wid = windowID
        memcpy(&bytes[0x3c], &wid, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xff, 0x10)

        var status: Int32 = 0
        // 0x0c = activate cửa sổ; 0x01 / 0x02 = make key window (down / up)
        for code: UInt8 in [0x0c, 0x01, 0x02] {
            bytes[0x08] = code
            status |= psn.withUnsafeBytes { p in
                bytes.withUnsafeBytes { b in postEventRecordTo(p.baseAddress!, b.baseAddress!) }
            }
        }
        return status == 0
    }

    /// Gửi sự kiện tới pid; ưu tiên đường của SkyLight, rơi về cách công khai.
    static func post(_ event: CGEvent, pid: pid_t) {
        if let eventPostToPid {
            eventPostToPid(pid, Unmanaged.passUnretained(event).toOpaque())
        } else {
            event.postToPid(pid)
        }
    }
}
