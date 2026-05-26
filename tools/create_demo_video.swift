import AppKit
import AVFoundation
import CoreVideo
import Foundation

struct Slide {
    let title: String
    let subtitle: String
    let bullets: [String]
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let audioURL = root.appendingPathComponent("OKX-ILGuard-voiceover-short.aiff")
let tempVideoURL = root.appendingPathComponent("OKX-ILGuard-demo-silent.mp4")
let outputURL = root.appendingPathComponent("OKX-ILGuard-demo.mp4")

try? FileManager.default.removeItem(at: tempVideoURL)
try? FileManager.default.removeItem(at: outputURL)

let slides: [Slide] = [
    Slide(
        title: "OKX-ILGuard",
        subtitle: "Impermanent Loss Protection Hook for Uniswap V4 on X Layer",
        bullets: [
            "Built for OKX X Layer Build X Hackathon - Hook Edition",
            "Mainnet deployed on X Layer chain 196",
            "Public repo: github.com/Souler-S/OKX-ILGuard"
        ]
    ),
    Slide(
        title: "The LP Problem",
        subtitle: "Impermanent loss is the fear that keeps LPs away.",
        bullets: [
            "LPs can earn fees but still underperform simply holding assets",
            "No native protection exists in earlier Uniswap versions",
            "The result: lower confidence, lower retention, lower TVL"
        ]
    ),
    Slide(
        title: "The Hook Design",
        subtitle: "Protection is embedded directly into the V4 pool lifecycle.",
        bullets: [
            "afterAddLiquidity: record LP snapshot",
            "afterSwap: record insurance premium accounting",
            "beforeRemoveLiquidity: enforce full-range MVP rule",
            "afterRemoveLiquidity: detect loss and compensate from reserve"
        ]
    ),
    Slide(
        title: "X Layer Mainnet Proof",
        subtitle: "Core deployments",
        bullets: [
            "Hook: 0x043b00Ae5d234e6c34107D60bFb663e7088a8744",
            "PoolId: 0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186",
            "PoolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32",
            "Reserve funded on-chain with 10 token0"
        ]
    ),
    Slide(
        title: "DemoFlow Transactions",
        subtitle: "Real add, swap, remove lifecycle on X Layer",
        bullets: [
            "Add liquidity: PositionSnapshotRecorded",
            "Swap: InsurancePremiumAccrued",
            "Remove liquidity: snapshot cleared",
            "totalPremiumsAccrued: 148073705159559"
        ]
    ),
    Slide(
        title: "MVP Honesty",
        subtitle: "Mainnet lifecycle is real; compensation branch is tested.",
        bullets: [
            "MVP uses a simplified 1:1 additive IL formula",
            "Real swap -> remove does not trigger compensation yet",
            "Forge test demonstrates ImpermanentLossDetected + ILCompensated",
            "Next upgrade: sqrtPriceX96 price-weighted IL calculation"
        ]
    ),
    Slide(
        title: "Why It Matters",
        subtitle: "A native LP protection primitive for X Layer",
        bullets: [
            "Makes protected liquidity a first-class pool property",
            "Improves LP confidence and TVL retention",
            "Gives X Layer a clear DeFi infrastructure narrative",
            "OKX-ILGuard: LP protection built into the pool"
        ]
    )
]

let audioAsset = AVURLAsset(url: audioURL)
let audioDuration = try await audioAsset.load(.duration)
let totalSeconds = CMTimeGetSeconds(audioDuration)
let width = 1920
let height = 1080
let fps = 30
let slideSeconds = totalSeconds / Double(slides.count)
let totalFrames = Int(ceil(totalSeconds * Double(fps)))

func drawWrapped(_ text: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.alignment = attributes[.paragraphStyle].flatMap { ($0 as? NSParagraphStyle)?.alignment } ?? .left
    var attrs = attributes
    attrs[.paragraphStyle] = paragraph
    NSString(string: text).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
}

func render(slide: Slide, index: Int) -> CGImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()

    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.067, alpha: 1).setFill()
    bounds.fill()

    let accent = NSColor(calibratedRed: 0.13, green: 0.75, blue: 0.58, alpha: 1)
    let secondary = NSColor(calibratedRed: 0.48, green: 0.68, blue: 0.95, alpha: 1)
    let text = NSColor(calibratedWhite: 0.94, alpha: 1)
    let muted = NSColor(calibratedWhite: 0.72, alpha: 1)

    accent.setFill()
    CGRect(x: 0, y: height - 16, width: width, height: 16).fill()
    secondary.setFill()
    CGRect(x: 0, y: 0, width: width, height: 10).fill()

    let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: muted
    ]
    NSString(string: "X Layer mainnet | Uniswap V4 Hook | Slide \(index + 1)/\(slides.count)")
        .draw(at: CGPoint(x: 96, y: height - 105), withAttributes: badgeAttrs)

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 76, weight: .bold),
        .foregroundColor: text
    ]
    drawWrapped(slide.title, rect: CGRect(x: 96, y: height - 235, width: 1728, height: 110), attributes: titleAttrs)

    let subtitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 38, weight: .medium),
        .foregroundColor: accent
    ]
    drawWrapped(slide.subtitle, rect: CGRect(x: 100, y: height - 330, width: 1680, height: 95), attributes: subtitleAttrs)

    let bulletAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 31, weight: .regular),
        .foregroundColor: text
    ]
    var y = height - 445
    for bullet in slide.bullets {
        accent.setFill()
        CGRect(x: 112, y: y + 10, width: 14, height: 14).fill()
        drawWrapped(bullet, rect: CGRect(x: 152, y: y - 12, width: 1600, height: 82), attributes: bulletAttrs)
        y -= 96
    }

    let footAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .regular),
        .foregroundColor: muted
    ]
    NSString(string: "github.com/Souler-S/OKX-ILGuard")
        .draw(at: CGPoint(x: 96, y: 52), withAttributes: footAttrs)

    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 6_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let colorSpace = CGColorSpaceCreateDeviceRGB()
var frame = 0
let renderedSlides = slides.enumerated().map { render(slide: $0.element, index: $0.offset) }

while frame < totalFrames {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.01)
    }
    let seconds = Double(frame) / Double(fps)
    let slideIndex = min(Int(seconds / slideSeconds), renderedSlides.count - 1)
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
    guard let buffer = pixelBuffer else { fatalError("Could not allocate pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )!
    context.draw(renderedSlides[slideIndex], in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
    adaptor.append(buffer, withPresentationTime: time)
    frame += 1
}

input.markAsFinished()
await writer.finishWriting()
if writer.status != .completed {
    fatalError("Video writer failed: \(String(describing: writer.error))")
}

let videoAsset = AVURLAsset(url: tempVideoURL)
let composition = AVMutableComposition()
let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first!
let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first!
let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
let range = CMTimeRange(start: .zero, duration: audioDuration)
try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
try compAudio.insertTimeRange(range, of: audioTrack, at: .zero)
compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
exporter.outputURL = outputURL
exporter.outputFileType = .mp4
exporter.shouldOptimizeForNetworkUse = true
await exporter.export()
if exporter.status != .completed {
    fatalError("Export failed: \(String(describing: exporter.error))")
}

try? FileManager.default.removeItem(at: tempVideoURL)
print("Wrote \(outputURL.path)")
