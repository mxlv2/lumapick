import Foundation
import Testing
@testable import XuanPian

@Test func roundsOnlyCarryKeptPhotos() {
    var s = CullingSession(folder: URL(fileURLWithPath: "/tmp"), assets: [], rounds: [SelectionRound(candidates: ["a", "b", "c"], kept: ["b", "c"])])
    s.advance()
    #expect(s.current.candidates == ["b", "c"])
    #expect(s.current.kept.isEmpty)
    s.advance()
    #expect(s.rounds.count == 2)
    for _ in 0..<100 { s.rounds[s.rounds.count - 1].kept = ["b"]; s.advance() }
    #expect(s.current.candidates == ["b"])
}
@Test func pairingAndRecursion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["DSC2.ARW", "DSC2.JPG", "DSC10.NEF", "nested/DSC2.JPG", "ignored.txt"] { try Data([1,2,3]).write(to: root.appendingPathComponent(name)) }
    let flat = try PhotoScanner.scan(root, recursive: false)
    #expect(flat.count == 2)
    #expect(flat[0].files.count == 2)
    #expect(flat[0].matches("RAW"))
    #expect(flat[0].matches("JPG"))
    #expect(try PhotoScanner.scan(root, recursive: true).count == 3)
}
@Test func exportNamesAndChoices() throws {
    let asset = PhotoAsset(id: "a", files: [URL(fileURLWithPath: "/a.ARW"), URL(fileURLWithPath: "/a.JPG")])
    let plan = try ExportPlan(assets: [asset], prefix: "嘉定湖", choice: .both)
    #expect(plan.items.map(\.name) == ["嘉定湖 1.ARW", "嘉定湖 1.JPG"])
    #expect(try ExportPlan(assets: [asset], prefix: "嘉定湖", choice: .raw).items.count == 1)
    #expect(throws: (any Error).self) { try ExportPlan(assets: [asset], prefix: "../bad", choice: .both) }
}
@Test func exportCopiesAndDoesNotOverwrite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.ARW")
    let bytes = Data([0, 1, 100, 255]); try bytes.write(to: source)
    let plan = try ExportPlan(assets: [PhotoAsset(id: "a", files: [source])], prefix: "湖", choice: .both)
    let first = try await ExportService.run(plan, parent: root) { _ in }
    let second = try await ExportService.run(plan, parent: root) { _ in }
    #expect(first != second)
    #expect(try Data(contentsOf: first.appendingPathComponent("湖 1.ARW")) == bytes)
    #expect(try Data(contentsOf: source) == bytes)
    let broken = try ExportPlan(assets: [PhotoAsset(id: "bad", files: [root.appendingPathComponent("missing.NEF")])], prefix: "失败", choice: .both)
    await #expect(throws: (any Error).self) { try await ExportService.run(broken, parent: root) { _ in } }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".xuanpian-") })
}
@Test func sessionRoundTrip() throws {
    let session = CullingSession(folder: URL(fileURLWithPath: "/tmp"), assets: [], rounds: [SelectionRound(candidates: ["a"], kept: ["a"])])
    let decoded = try JSONDecoder().decode(CullingSession.self, from: JSONEncoder().encode(session))
    #expect(decoded.rounds == session.rounds)
}

@Test func cancelledExportLeavesNoResult() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.JPG")
    try Data([1,2,3]).write(to: source)
    let plan = try ExportPlan(assets: [PhotoAsset(id: "a", files: [source])], prefix: "取消", choice: .both)
    let worker = Task { try await ExportService.run(plan, parent: root) { _ in withUnsafeCurrentTask { $0?.cancel() } } }
    await #expect(throws: CancellationError.self) { try await worker.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source.JPG"])
}
@Test func largeFolderEnumeration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<3000 { try Data([0]).write(to: root.appendingPathComponent("Photo\(index).JPG")) }
    let assets = try PhotoScanner.scan(root, recursive: true)
    #expect(assets.count == 3000)
    #expect(assets.first?.name == "Photo0")
    #expect(assets.last?.name == "Photo2999")
}

import CoreGraphics
import ImageIO

private func previewFixture(_ url: URL, width: Int = 2400, height: Int = 1600, orientation: Int = 1) throws {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.15, green: 0.5, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for x in stride(from: 0, to: width, by: 8) { context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: x, y: 0, width: 2, height: height)) }
    let image = try #require(context.makeImage())
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
}
@Test func previewResolutionCacheAndCoalescing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("detail.jpg"); try previewFixture(url)
    let service = PreviewService(cacheDirectory: root.appendingPathComponent("cache"))
    async let first = service.load(url, quality: .screen(1200))
    async let second = service.load(url, quality: .screen(1200))
    let (a, b) = await (first, second)
    #expect(a?.image.width == 1200); #expect(b?.image.height == 800)
    #expect(a?.nativeSize == CGSize(width: 2400, height: 1600))
    #expect(await service.decodeRequests == 1)
    _ = await service.load(url, quality: .screen(1200))
    #expect(await service.decodeRequests == 1)
    let original = await service.load(url, quality: .original)
    #expect(original?.image.width == 2400); #expect(original?.originalResolution == true)
    _ = await service.load(url, quality: .original)
    #expect(await service.decodeRequests == 2)
    let thumb = await service.load(url, quality: .thumbnail(768))
    #expect(thumb?.image.width == 768); #expect(thumb?.originalResolution == false)
}
@Test func previewOrientationInvalidationAndCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("rotate.jpg"); try previewFixture(url, orientation: 6)
    let service = PreviewService(cacheDirectory: root.appendingPathComponent("cache"))
    let image = await service.load(url, quality: .screen(1200))
    #expect(image?.image.width == 800); #expect(image?.image.height == 1200)
    #expect(image?.nativeSize == CGSize(width: 1600, height: 2400))
    try previewFixture(url, width: 1800, height: 1200)
    let changed = await service.load(url, quality: .screen(1200))
    #expect(changed?.nativeSize == CGSize(width: 1800, height: 1200))
    #expect(await service.decodeRequests == 2)
    let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return await service.load(url, quality: .original) }
    #expect(await cancelled.value == nil)
    #expect(await service.load(url, quality: .original)?.originalResolution == true)
}
