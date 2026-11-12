import Foundation
import ScreenCaptureKit
import CoreMedia
import IOSurface

/// Chụp liên tục một cửa sổ bằng ScreenCaptureKit và đẩy từng frame (IOSurface) ra ngoài.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let window: SCWindow
    var onFrame: ((IOSurface) -> Void)?
    var onStop: ((Error?) -> Void)?
    /// Kích thước (point) mới của cửa sổ gốc.
    var onResize: ((CGSize) -> Void)?

    private var stream: SCStream?
    private var configWidth = 0
    private var configHeight = 0
    private var isResizing = false
    private let queue = DispatchQueue(label: "everythinginone.capture", qos: .userInteractive)

    init(window: SCWindow) {
        self.window = window
    }

    func start() async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let info = SCShareableContent.info(for: filter)
        let scale = CGFloat(info.pointPixelScale)

        let config = SCStreamConfiguration()
        config.width = max(1, Int(info.contentRect.width * scale))
        config.height = max(1, Int(info.contentRect.height * scale))
        configWidth = config.width
        configHeight = config.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        let current = stream
        stream = nil
        try? await current?.stopCapture()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        followSourceSize(attachments.first)

        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(surface)
        }
    }

    /// Khi cửa sổ gốc đổi kích thước, cập nhật luồng chụp cho khớp (không thì ảnh bị méo/giữ cỡ cũ).
    private func followSourceSize(_ info: [SCStreamFrameInfo: Any]?) {
        guard !isResizing,
              let rectDict = info?[.contentRect] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: rectDict),
              let scale = info?[.scaleFactor] as? CGFloat, rect.width > 0, rect.height > 0
        else { return }
        let wantW = Int(rect.width * scale)
        let wantH = Int(rect.height * scale)
        guard abs(wantW - configWidth) > 2 || abs(wantH - configHeight) > 2,
              let stream else { return }

        isResizing = true
        configWidth = wantW
        configHeight = wantH
        let config = SCStreamConfiguration()
        config.width = wantW
        config.height = wantH
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.showsCursor = false
        Task { [weak self] in
            try? await stream.updateConfiguration(config)
            self?.isResizing = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.onResize?(CGSize(width: rect.width, height: rect.height))
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStop?(error)
        }
    }
}
