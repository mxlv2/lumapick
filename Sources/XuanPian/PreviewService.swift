import AppKit
import CoreImage
import ImageIO

final class PreviewService: @unchecked Sendable {
    static let shared = PreviewService()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
    private let cache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.totalCostLimit = 256 * 1024 * 1024; return c }()
    func load(_ url: URL, pixels: Int) async -> NSImage? {
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = "\(url.path):\(pixels):\(stamp)"
        if let image = cache.object(forKey: key as NSString) { return image }
        let operation = BlockOperation()
        let cancellation = PreviewCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                operation.addExecutionBlock { [self] in
                    guard !cancellation.isCancelled else { continuation.resume(returning: nil); return }
                    let image: NSImage? = autoreleasepool {
                        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
                        var cg: CGImage?
                        if let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) {
                            let index = CGImageSourceGetPrimaryImageIndex(source)
                            let thumbnail: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: pixels > 1000, kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true]
                            cg = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnail as CFDictionary)
                        }
                        if cg == nil, let raw = CIRAWFilter(imageURL: url) {
                            raw.scaleFactor = min(1, Float(pixels) / Float(max(raw.nativeSize.width, raw.nativeSize.height)))
                            if let output = raw.outputImage { cg = CIContext().createCGImage(output, from: output.extent) }
                        }
                        guard let cg else { return nil }
                        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        if pixels <= 3000 { cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height) }
                        return image
                    }
                    continuation.resume(returning: image)
                }
                // Always execute the block so its continuation is resumed, even if its caller leaves.
                queue.addOperation(operation)
            }
        } onCancel: { cancellation.cancel() }
    }
}

private final class PreviewCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
