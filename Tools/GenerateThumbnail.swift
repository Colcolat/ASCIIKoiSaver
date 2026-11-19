import AppKit
import CoreGraphics
import Foundation

func renderThumbnail(width: Int, height: Int, outPath: String) {
    // Render crisp high-res frame of a bold hero Koi, then downsample smoothly to Apple's exact thumbnail size
    let srcW = width * 2
    let srcH = height * 2

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

    let srcSize = CGSize(width: srcW, height: srcH)
    engine.resize(to: srcSize)
    for _ in 0..<35 {
        engine.step(dt: 1.0 / 30.0)
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let srcCtx = CGContext(
        data: nil, width: srcW, height: srcH,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create src bitmap context") }

    engine.draw(in: srcCtx, rect: CGRect(origin: .zero, size: srcSize))
    guard let srcImg = srcCtx.makeImage() else { fatalError("Could not create src CGImage") }

    guard let dstCtx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create dst bitmap context") }

    dstCtx.interpolationQuality = .high
    dstCtx.draw(srcImg, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let finalImg = dstCtx.makeImage() else { fatalError("Could not create final CGImage") }
    let rep = NSBitmapImageRep(cgImage: finalImg)
    guard let pngData = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
    try! pngData.write(to: URL(fileURLWithPath: outPath))
}

@main
struct ThumbnailTool {
    static func main() {
        let args = CommandLine.arguments
        let outDir = args.count > 1 ? args[1] : "."
        // Exact Apple macOS Screen Saver thumbnail dimensions (matching Random.saver)
        renderThumbnail(width: 90, height: 58, outPath: "\(outDir)/thumbnail.png")
        renderThumbnail(width: 180, height: 116, outPath: "\(outDir)/thumbnail@2x.png")
        print("Generated thumbnail.png (90x58) and thumbnail@2x.png (180x116) in \(outDir)")
    }
}
