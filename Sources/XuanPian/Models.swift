import Foundation
import UniformTypeIdentifiers

struct PhotoAsset: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var files: [URL]
    var name: String { files[0].deletingPathExtension().lastPathComponent }
    var formats: [String] { files.map { $0.pathExtension.uppercased() } }
    var previewURL: URL { files.first(where: { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }) ?? files[0] }
    static let rawExtensions: Set<String> = ["arw", "nef", "nrw", "cr2", "cr3", "crw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw", "3fr", "fff", "iiq", "rwl", "sr2", "srf", "erf", "mos", "mrw", "kdc", "dcr"]
    static func isRAW(_ url: URL) -> Bool { rawExtensions.contains(url.pathExtension.lowercased()) || (UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .rawImage) ?? false) }
    func matches(_ format: String) -> Bool {
        format == "全部" || (format == "RAW" ? files.contains(where: Self.isRAW) : formats.contains(format))
    }
}
struct SelectionRound: Codable, Equatable, Sendable {
    var candidates: [String]
    var kept: Set<String> = []
}
struct CullingSession: Codable, Sendable {
    var folder: URL
    var bookmark: Data?
    var assets: [PhotoAsset]
    var rounds: [SelectionRound]
    var completed = false
    var exportedFolder: URL?
    var current: SelectionRound { rounds.last! }
    mutating func advance() {
        let ids = current.candidates.filter { current.kept.contains($0) }
        guard !ids.isEmpty else { return }
        rounds.append(SelectionRound(candidates: ids))
    }
}
enum ExportChoice: String, CaseIterable, Identifiable {
    case both = "RAW + JPEG", raw = "仅 RAW", jpeg = "仅 JPEG"
    var id: String { rawValue }
}
struct ExportPlan: Sendable {
    struct Item: Sendable { var source: URL; var name: String }
    var items: [Item]
    var prefix: String
    init(assets: [PhotoAsset], prefix: String, choice: ExportChoice) throws {
        let clean = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), !clean.contains(":"), !clean.contains("\0"), clean.utf8.count < 180 else { throw AppError.message("名称不能为空，不能包含 /、: 或过长的文字。") }
        self.prefix = clean
        items = assets.enumerated().flatMap { index, asset in
            let files = asset.files.count > 1 ? asset.files.filter { choice == .both || (choice == .raw ? PhotoAsset.isRAW($0) : !PhotoAsset.isRAW($0)) } : asset.files
            return files.map { Item(source: $0, name: "\(clean) \(index + 1).\($0.pathExtension)") }
        }
    }
}
enum AppError: LocalizedError { case message(String); var errorDescription: String? { switch self { case .message(let s): s } } }

struct PhotoScanner {
    static func scan(_ folder: URL, recursive: Bool) throws -> [PhotoAsset] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        var scanError: Error?
        guard let iterator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: options, errorHandler: { _, error in scanError = error; return true }) else { throw AppError.message("无法读取文件夹。") }
        var groups: [String: [URL]] = [:]
        for case let url as URL in iterator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard ["jpg", "jpeg", "heic", "heif", "hif", "png", "tif", "tiff", "gif", "bmp", "webp", "avif", "jxl"].contains(url.pathExtension.lowercased()) || PhotoAsset.isRAW(url) || (UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) ?? false) else { continue }
            groups[url.deletingPathExtension().path, default: []].append(url)
        }
        if let scanError { throw scanError }
        return groups.flatMap { key, files -> [PhotoAsset] in
            let raws = files.filter(PhotoAsset.isRAW)
            let jpgs = files.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            if files.count == 2 && raws.count == 1 && jpgs.count == 1 { return [PhotoAsset(id: key, files: raws + jpgs)] }
            return files.map { PhotoAsset(id: $0.path, files: [$0]) }
        }.sorted {
            let compare = $0.name.localizedStandardCompare($1.name)
            return compare == .orderedSame ? $0.id < $1.id : compare == .orderedAscending
        }
    }
}

struct ExportService {
    static func run(_ plan: ExportPlan, parent: URL, progress: @Sendable (Int) async -> Void) async throws -> URL {
        guard !plan.items.isEmpty else { throw AppError.message("没有可导出的照片。") }
        let fm = FileManager.default
        let staging = parent.appendingPathComponent(".xuanpian-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        for (index, item) in plan.items.enumerated() {
            try Task.checkCancellation()
            try fm.copyItem(at: item.source, to: staging.appendingPathComponent(item.name))
            await progress(index + 1)
        }
        try Task.checkCancellation()
        var target = parent.appendingPathComponent("\(plan.prefix) 精选")
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(plan.prefix) 精选 \(suffix)"); suffix += 1
        }
        try fm.moveItem(at: staging, to: target)
        return target
    }
}
