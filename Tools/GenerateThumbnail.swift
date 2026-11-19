import AppKit
import CoreGraphics
import Foundation

func renderThumbnail(width: Int, height: Int, outPath: String) {
    let engine = PondEngine()
    var cfg = SaverConfig()
    cfg.timeMode = "day"
    cfg.season = "autumn"
    cfg.koiCount = 2
    cfg.showClock = false
    cfg.rainOn = false
    cfg.monoMode = false
    cfg.isPreview = true
    engine.applyConfig(cfg)

    let size = CGSize(width: width, height: height)
    engine.resize(to: size)
    // Advance simulation slightly so the Koi curves gracefully in the center
    for _ in 0..<45 {
        engine.step(dt: 1.0 / 30.0)
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create bitmap context")
    }

    engine.draw(in: ctx, rect: CGRect(origin: .zero, size: size))
    guard let cgImage = ctx.makeImage() else {
        fatalError("Could not create CGImage")
    }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }

    try! pngData.write(to: URL(fileURLWithPath: outPath))
}

@main
struct ThumbnailTool {
    static func main() {
        let args = CommandLine.arguments
        let outDir = args.count > 1 ? args[1] : "."
        renderThumbnail(width: 180, height: 116, outPath: "\(outDir)/thumbnail.png")
        renderThumbnail(width: 360, height: 232, outPath: "\(outDir)/thumbnail@2x.png")
        print("Generated thumbnail.png and thumbnail@2x.png in \(outDir)")
    }
}
