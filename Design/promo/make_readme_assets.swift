// Tạo ảnh/GIF cho README từ video quảng bá.
// swift Design/promo/make_readme_assets.swift Design/promo/glassmates_promo.mp4 docs
import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

let video = URL(fileURLWithPath: CommandLine.arguments[1]), out = CommandLine.arguments[2]
let asset = AVURLAsset(url: video)
let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
gen.appliesPreferredTrackTransform = true

func frame(_ t: Double, width: Int) -> CGImage {
    gen.maximumSize = CGSize(width: width, height: width * 9 / 16)
    return try! gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
}
func png(_ img: CGImage, _ name: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
func gif(_ name: String, from a: Double, to b: Double, fps: Double, width: Int) {
    let count = Int((b - a) * fps)
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name)") as CFURL, UTType.gif.identifier as CFString, count, nil)!
    CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
    for i in 0..<count { CGImageDestinationAddImage(d, frame(a + Double(i) / fps, width: width), props) }
    CGImageDestinationFinalize(d)
}
png(frame(19.0, width: 1600), "hero.png")
png(frame(26.0, width: 1280), "displays.png")
png(frame(29.6, width: 1280), "menubar.png")
gif("glue.gif", from: 16.35, to: 21.6, fps: 12, width: 800)
gif("arrange.gif", from: 9.8, to: 15.6, fps: 12, width: 800)
print("ok")
