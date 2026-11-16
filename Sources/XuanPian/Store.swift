import SwiftUI
import AppKit

@MainActor final class AppStore: ObservableObject {
    @Published var session: CullingSession?
    @Published var selected: Set<String> = []
    @Published var isolation: [String]?
    @Published var format = "全部"
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var result: URL?
    @Published var recursive = true
    @Published var exportProgress = 0
    private var undoStates: [CullingSession] = []
    private var task: Task<Void, Never>?
    private var sourceAccess: URL?
    private let saveURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("XuanPian/session.json")
    init() {
        if let data = try? Data(contentsOf: saveURL), let saved = try? JSONDecoder().decode(CullingSession.self, from: data), !saved.rounds.isEmpty {
            session = saved
            result = saved.exportedFolder
            if let bookmark = saved.bookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() { sourceAccess = url }
            }
        }
    }
    var assets: [PhotoAsset] {
        guard let s = session else { return [] }
        let ids = Set(isolation ?? s.current.candidates)
        return s.assets.filter { ids.contains($0.id) && $0.matches(format) }
    }
    var keptAssets: [PhotoAsset] { session?.assets.filter { session!.current.kept.contains($0.id) } ?? [] }
    var formats: [String] { ["全部"] + ((session?.assets.contains { $0.files.contains(where: PhotoAsset.isRAW) } ?? false) ? ["RAW"] : []) + Set(session?.assets.flatMap { $0.files.filter { !PhotoAsset.isRAW($0) }.map { $0.pathExtension.uppercased() } } ?? []).sorted() }
    var roundName: String { let n = session?.rounds.count ?? 1; return n == 1 ? "粗筛" : n == 2 ? "精筛" : "第 \(n) 轮" }
    func relocate() {
        guard session != nil, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "重新定位原文件夹"
        if panel.runModal() == .OK, let folder = panel.url {
            let old = session!.folder.path
            let accessing = folder.startAccessingSecurityScopedResource()
            checkpoint()
            session!.assets = session!.assets.map { asset in
                var updated = asset
                updated.files = asset.files.map { folder.appendingPathComponent(String($0.path.dropFirst(old.count + 1))) }
                return updated
            }
            sourceAccess?.stopAccessingSecurityScopedResource(); sourceAccess = accessing ? folder : nil
            session!.folder = folder
            session!.bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            save()
        }
    }
    func save() {
        guard let session else { return }
        do { try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(session).write(to: saveURL, options: .atomic) }
        catch { self.error = "筛选进度保存失败：\(error.localizedDescription)" }
    }
    func open() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "开始选片"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func load(_ url: URL) {
        guard !busy else { return }
        busy = true; status = "正在读取照片…"
        let recurse = recursive
        task = Task {
            let accessing = url.startAccessingSecurityScopedResource()
            do {
                let assets = try await Task.detached { try PhotoScanner.scan(url, recursive: recurse) }.value
                sourceAccess?.stopAccessingSecurityScopedResource(); sourceAccess = accessing ? url : nil
                session = CullingSession(folder: url, bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), assets: assets, rounds: [SelectionRound(candidates: assets.map(\.id))])
                selected = []; isolation = nil; format = "全部"; undoStates = []; result = nil; save()
                if assets.isEmpty { status = "文件夹中没有图片" } else { status = "" }
            } catch { if accessing { url.stopAccessingSecurityScopedResource() }; self.error = error.localizedDescription }
            busy = false
        }
    }
    func checkpoint() { if let session { undoStates.append(session); if undoStates.count > 50 { undoStates.removeFirst() } } }
    func mark(_ ids: Set<String>, kept: Bool) {
        guard session != nil, !busy, session?.completed != true else { return }
        checkpoint()
        if kept { session!.rounds[session!.rounds.count - 1].kept.formUnion(ids) }
        else { session!.rounds[session!.rounds.count - 1].kept.subtract(ids) }
        save()
    }
    func toggle(_ id: String) { mark([id], kept: !(session?.current.kept.contains(id) ?? false)) }
    func advance() { guard !keptAssets.isEmpty else { return }; checkpoint(); session?.advance(); selected = []; isolation = nil; format = "全部"; save() }
    func undo() { if let old = undoStates.popLast() { session = old; selected = []; isolation = nil; save() } }
    func restore(_ index: Int) { checkpoint(); session?.rounds = Array(session!.rounds.prefix(index + 1)); session?.completed = false; selected = []; isolation = nil; save() }
    func export(_ plan: ExportPlan, parent: URL) {
        busy = true; exportProgress = 0; status = "正在复制原片…"
        task = Task {
            let accessing = parent.startAccessingSecurityScopedResource()
            defer { if accessing { parent.stopAccessingSecurityScopedResource() }; busy = false }
            do {
                let worker = Task.detached { try await ExportService.run(plan, parent: parent) { count in await MainActor.run { self.exportProgress = count } } }
                let url = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                checkpoint(); session?.completed = true; session?.exportedFolder = url; result = url; status = "已导出 \(plan.items.count) 个文件"; save()
            } catch is CancellationError { status = "导出已取消，筛选进度已保留" }
            catch { self.error = error.localizedDescription; status = "导出未完成，可重试" }
        }
    }
    func cancelExport() { task?.cancel() }
}
