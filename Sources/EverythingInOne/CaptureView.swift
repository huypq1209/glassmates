import SwiftUI
import AppKit
import IOSurface

/// Hiển thị frame IOSurface trực tiếp lên CALayer (ít trễ, không copy).
struct CaptureView: NSViewRepresentable {
    let capture: WindowCapture

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.backgroundColor = NSColor.black.cgColor
        capture.onFrame = { [weak view] surface in
            view?.layer?.contents = surface
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
