import AppKit
import CoreImage
import ImageIO
import CryptoKit

/// Pixel dimensions are kept independently of the current rendition so that a
/// quick preview never changes the geometry of a 100% view when it is upgraded.
struct PreviewFrame: @unchecked Sendable {
    let image: CGImage
    let nativeSize: CGSize
    let originalResolution: Bool
    var cost: Int { image.bytesPerRow * image.height }
    @MainActor var nsImage: NSImage { NSImage(cgImage: image, size: nativeSize) }
}
enum PreviewQuality: Hashable, Sendable {
    case embedded(Int), thumbnail(Int), screen(Int), original
    var pixels: Int {
        switch self { case .embedded(let n), .thumbnail(let n), .screen(let n): return n; case .original: return Int.max }
    }
    var isThumbnail: Bool { if case .thumbnail = self { return true }; return false }
    var isEmbedded: Bool { if case .embedded = self { return true }; return false }
}
private final class CachedFrame: NSObject { let value: PreviewFrame; init(_ value: PreviewFrame) { self.value = value } }
private final class PreviewCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Coalesces requests from the grid and viewer. Cancelling a view removes only
/// that subscriber; a decode needed by another view continues.
actor PreviewService {
    static let shared = PreviewService()
    private struct Flight {
        let generation: UUID
        let task: Task<PreviewFrame?, Never>
        let cancellation: PreviewCancellation
        var subscribers: Set<UUID>
    }
    private var flights: [String: Flight] = [:]
    private let small = NSCache<NSString, CachedFrame>()
    private let screen = NSCache<NSString, CachedFrame>()
    private let originals = NSCache<NSString, CachedFrame>()
    private let pool: PreviewDecoder
    private(set) var decodeRequests = 0
    init(cacheDirectory: URL? = nil) {
        small.totalCostLimit = 96 * 1024 * 1024
        screen.totalCostLimit = 128 * 1024 * 1024
        originals.totalCostLimit = 384 * 1024 * 1024; originals.countLimit = 2
        pool = PreviewDecoder(cacheDirectory: cacheDirectory)
    }
    func load(_ url: URL, quality: PreviewQuality) async -> PreviewFrame? {
        guard !Task.isCancelled else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fingerprint = "v2|\(url.path)|\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\((attributes?[.size] as? NSNumber)?.intValue ?? 0)|\(quality)"
        let key = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        let cache = cache(for: quality)
        if let value = cache.object(forKey: key as NSString) { return value.value }
        let subscriber = UUID()
        if flights[key] != nil { flights[key]!.subscribers.insert(subscriber) }
        else {
            let cancel = PreviewCancellation(); let decoder = pool
            decodeRequests += 1
            let task = Task.detached(priority: quality.isThumbnail ? .utility : .userInitiated) {
                await decoder.decode(url, quality: quality, key: key, cancellation: cancel)
            }
            flights[key] = Flight(generation: UUID(), task: task, cancellation: cancel, subscribers: [subscriber])
        }
        let flight = flights[key]!
        return await withTaskCancellationHandler {
            let result = await flight.task.value
            if !flight.cancellation.isCancelled, let result {
                let limit = quality == .original ? 192 * 1024 * 1024 : 96 * 1024 * 1024
                if result.cost <= limit { cache.setObject(CachedFrame(result), forKey: key as NSString, cost: result.cost) }
            }
            if flights[key]?.generation == flight.generation { flights.removeValue(forKey: key) }
            return Task.isCancelled ? nil : result
        } onCancel: {
            Task { await self.release(key, generation: flight.generation, subscriber: subscriber) }
        }
    }
    private func release(_ key: String, generation: UUID, subscriber: UUID) {
        guard flights[key]?.generation == generation else { return }
        flights[key]!.subscribers.remove(subscriber)
        if flights[key]!.subscribers.isEmpty { flights[key]!.cancellation.cancel(); flights.removeValue(forKey: key) }
    }
    private func cache(for quality: PreviewQuality) -> NSCache<NSString, CachedFrame> {
        switch quality { case .original: originals; case .screen: screen; default: small }
    }
    func prefetch(_ urls: [URL], pixels: Int = 2560) async {
        for url in urls.prefix(2) {
            guard !Task.isCancelled else { return }
            _ = await load(url, quality: .screen(pixels))
        }
    }
}

private final class PreviewDecoder: @unchecked Sendable {
    private let thumbnails: OperationQueue = { let q = OperationQueue(); q.name = "LumaPick.thumbnails"; q.maxConcurrentOperationCount = 3; q.qualityOfService = .utility; return q }()
    private let previews: OperationQueue = { let q = OperationQueue(); q.name = "LumaPick.viewer"; q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
    private let disk = DispatchQueue(label: "LumaPick.preview-cache", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let cacheDirectory: URL
    private var diskWrites = 0 // accessed only on disk queue
    init(cacheDirectory: URL?) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LumaPick/Previews")
    }
    func decode(_ url: URL, quality: PreviewQuality, key: String, cancellation: PreviewCancellation) async -> PreviewFrame? {
        await withCheckedContinuation { continuation in
            let queue = quality.isThumbnail || quality.isEmbedded ? thumbnails : previews
            queue.addOperation { [self] in
                guard !cancellation.isCancelled else { continuation.resume(returning: nil); return }
                let result: PreviewFrame? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                    let index = CGImageSourceGetPrimaryImageIndex(source)
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
                    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
                    let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
                    let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
                    let native = orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
                    let cachedURL = cacheDirectory.appendingPathComponent(key + ".png")
                    if quality.isThumbnail, let cached = CGImageSourceCreateWithURL(cachedURL as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(cached, 0, nil) {
                        return PreviewFrame(image: cg, nativeSize: native.width > 0 ? native : CGSize(width: cg.width, height: cg.height), originalResolution: false)
                    }
                    let full = quality == .original
                    let maxPixels = full ? max(1, Int(max(w, h))) : quality.pixels
                    var options: [CFString: Any] = [kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
                    // Reuse an embedded preview only when it has enough real pixels.
                    var cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
                    let required = min(maxPixels, Int(max(w, h)) > 0 ? Int(max(w, h)) : maxPixels)
                    if !quality.isEmbedded && (full || cg == nil || max(cg!.width, cg!.height) < required) {
                        options[kCGImageSourceCreateThumbnailFromImageAlways] = true
                        cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
                    }
                    if cancellation.isCancelled { return nil }
                    if !quality.isEmbedded && (cg == nil || (full && (w == 0 || max(cg!.width, cg!.height) < maxPixels))), let raw = CIRAWFilter(imageURL: url) {
                        raw.scaleFactor = full ? 1 : min(1, Float(maxPixels) / Float(max(raw.nativeSize.width, raw.nativeSize.height)))
                        if let output = raw.outputImage { cg = context.createCGImage(output, from: output.extent) }
                    }
                    guard let cg, !cancellation.isCancelled else { return nil }
                    let resolvedNative = native.width > 0 && native.height > 0 ? native : CGSize(width: cg.width, height: cg.height)
                    let frame = PreviewFrame(image: cg, nativeSize: resolvedNative, originalResolution: cg.width >= Int(resolvedNative.width) && cg.height >= Int(resolvedNative.height))
                    if quality.isThumbnail { writeThumbnail(cg, to: cachedURL) }
                    return frame
                }
                continuation.resume(returning: result)
            }
        }
    }
    private func writeThumbnail(_ image: CGImage, to url: URL) {
        disk.async { [self] in
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { return }
                try (data as Data).write(to: url, options: .atomic)
                diskWrites += 1
                if diskWrites % 24 == 1 { trimDiskCache() }
            } catch { /* A read-only cache never prevents viewing a photograph. */ }
        }
    }
    private func trimDiskCache() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let entries = urls.filter { $0.pathExtension == "png" }.map { url -> (URL, Int, Date) in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where total > 256 * 1024 * 1024 { try? fm.removeItem(at: url); total -= size }
    }
}
