import SwiftUI
import AppKit

// Explicit property-wrapper alias supports SDKs that also declare a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct XuanPianApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("留影") { ContentView().environmentObject(store).frame(minWidth: 900, minHeight: 620) }
            .defaultSize(width: 1200, height: 800)
            .commands {
                CommandGroup(replacing: .newItem) { Button("打开文件夹…") { store.open() }.keyboardShortcut("o").disabled(store.busy) }
                CommandGroup(after: .pasteboard) {
                    Button("全选照片") { store.selected = Set(store.assets.map(\.id)) }.disabled(store.busy)
                    Button("取消所选保留") { store.mark(store.selected, kept: false) }.disabled(store.busy || store.selected.isEmpty)
                }
                CommandGroup(replacing: .undoRedo) { Button("撤销") { store.undo() }.keyboardShortcut("z").disabled(store.busy) }
            }
    }
}
struct ViewerSelection: Identifiable { let id = UUID(); let assets: [PhotoAsset] }
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @ViewState private var size: Double = 190
    @ViewState private var showExport = false
    @ViewState private var viewer: ViewerSelection?
    @ViewState private var history = false
    var body: some View {
        VStack(spacing: 0) {
            if let session = store.session {
                HStack(spacing: 16) {
                    Picker("格式", selection: $store.format) { ForEach(store.formats, id: \.self) { Text($0).tag($0) } }.frame(width: 150)
                    Divider().frame(height: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.isolation == nil ? session.folder.lastPathComponent : "隔离选片").font(.headline)
                        Text(store.isolation == nil ? "第 \(session.rounds.count) 轮 · \(store.roundName)" : "仅查看这一组 · 标记同步当前轮").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isolation != nil { Button("返回本轮", systemImage: "arrow.uturn.backward") { store.isolation = nil; store.selected = [] } }
                    Button("隔离", systemImage: "square.dashed") { store.isolation = store.assets.filter { store.selected.contains($0.id) }.map(\.id); store.selected = [] }.disabled(store.selected.count < 2)
                    Button("对比", systemImage: "rectangle.split.2x1") { openViewer() }.disabled(store.selected.isEmpty)
                    Slider(value: $size, in: 140...320).frame(width: 95).help("缩略图大小")
                }.padding(20).background(.bar)
                Divider()
                if store.assets.isEmpty {
                    ContentUnavailableView("暂无照片", systemImage: "photo.on.rectangle.angled", description: Text("选择其他格式，或打开包含照片的文件夹。"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: size), spacing: 18)], spacing: 22) {
                            ForEach(store.assets) { asset in
                                PhotoCard(asset: asset, selected: store.selected.contains(asset.id), kept: session.current.kept.contains(asset.id), size: size) { store.toggle(asset.id) }
                                    .onTapGesture(count: 2) { viewer = ViewerSelection(assets: [asset]) }
                                    .onTapGesture { select(asset) }
                                    .contextMenu {
                                        Button("加入对比选择") { store.selected.insert(asset.id) }
                                        Button("保留") { store.mark([asset.id], kept: true) }
                                        Button("取消保留") { store.mark([asset.id], kept: false) }
                                        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(asset.files) }
                                    }
                            }
                        }.padding(24)
                    }.background(Color(nsColor: .windowBackgroundColor))
                }
                Divider()
                HStack(spacing: 16) {
                    Button("轮次历史", systemImage: "clock.arrow.circlepath") { history = true }
                    Text("\(session.current.candidates.count) 张 · 已保留 \(session.current.kept.count) 张").font(.callout).monospacedDigit()
                    Button("保留所选") { store.mark(store.selected, kept: true) }.disabled(store.selected.isEmpty || session.completed)
                    Spacer()
                    if session.completed {
                        Label("已完成", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let result = store.result { Button("打开结果") { NSWorkspace.shared.open(result) } }
                    } else if store.isolation == nil {
                        Button("进入下一轮") { store.advance() }.disabled(store.keptAssets.isEmpty)
                        Button("命名并导出…") { showExport = true }.buttonStyle(.borderedProminent).disabled(store.keptAssets.isEmpty)
                    }
                }.padding(18).background(.bar)
            } else {
                VStack(spacing: 22) {
                    Image(systemName: "photo.stack").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.tint)
                    Text("让好照片，留下来。").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("从一整次拍摄，到值得精修的几张。\n打开文件夹，开始你的第一轮选片。").multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(6)
                    Button("选择照片文件夹…", systemImage: "folder.badge.plus") { store.open() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Toggle("包含子文件夹", isOn: $store.recursive).toggleStyle(.checkbox)
                    Text("也可以将文件夹拖到这里").font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !store.status.isEmpty { Text(store.status).font(.caption).foregroundStyle(.secondary).padding(6) }
        }
        .onCommand(#selector(NSText.selectAll(_:))) { if !store.busy { store.selected = Set(store.assets.map(\.id)) } }
        .toolbar {
            ToolbarItem { Button(action: store.open) { Label("打开文件夹", systemImage: "folder") }.disabled(store.busy) }
            ToolbarItem { if store.session != nil { Button("重新定位来源", systemImage: "folder.badge.questionmark") { store.relocate() }.disabled(store.busy) } }
            ToolbarItem { Toggle("包含子文件夹", isOn: $store.recursive).help("下次打开文件夹时生效") }
        }
        .disabled(store.busy)
        .overlay { if store.busy { VStack(spacing: 14) { ProgressView(); Text(store.status); if store.status.contains("复制") { Text("已复制 \(store.exportProgress) 个文件"); Button("取消导出", role: .cancel) { store.cancelExport() } } }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in var dir: ObjCBool = false; if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue { store.load(url) } } } }; return true
        }
        .background { KeyHandler { key in
            guard !showExport, viewer == nil, !history, !store.busy else { return false }
            switch key {
            case "p": store.mark(store.selected, kept: true)
            case "u": store.mark(store.selected, kept: false)
            case " ": if !store.selected.isEmpty { openViewer() }
            case "\u{1b}": store.isolation = nil; store.selected = []
            default: return false
            }; return true
        } }
        .sheet(isPresented: $showExport) { ExportSheet().environmentObject(store) }
        .sheet(item: $viewer) { selection in CompareView(assets: selection.assets).environmentObject(store) }
        .sheet(isPresented: $history) { HistoryView().environmentObject(store) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好", role: .cancel) {} } message: { Text(store.error ?? "") }
    }
    private func openViewer() { let chosen = store.assets.filter { store.selected.contains($0.id) }; if !chosen.isEmpty { viewer = ViewerSelection(assets: chosen) } }
    private func select(_ asset: PhotoAsset) {
        if (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.command) { if store.selected.contains(asset.id) { store.selected.remove(asset.id) } else { store.selected.insert(asset.id) } }
        else if (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift), let first = store.assets.firstIndex(where: { store.selected.contains($0.id) }), let last = store.assets.firstIndex(of: asset) { store.selected.formUnion(store.assets[min(first,last)...max(first,last)].map(\.id)) }
        else { store.selected = [asset.id] }
    }
}
struct PhotoCard: View {
    let asset: PhotoAsset; let selected: Bool; let kept: Bool; let size: Double; let toggle: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Thumbnail(url: asset.previewURL, pixels: 640).frame(height: size * 0.72).frame(maxWidth: .infinity).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { Button(action: toggle) { Image(systemName: kept ? "checkmark.circle.fill" : "circle").font(.title3).symbolRenderingMode(.palette).foregroundStyle(kept ? Color.green : Color.secondary, Color.white) }.buttonStyle(.plain).accessibilityLabel(kept ? "取消保留" : "保留照片").padding(8) }
            HStack { Text(asset.name).lineLimit(1).font(.system(size: 12, weight: .medium)); Spacer(minLength: 2); Text(asset.formats.joined(separator: "+")).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
        }.padding(8).background(selected ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)).contentShape(Rectangle())
    }
}
struct Thumbnail: View {
    let url: URL; let pixels: Int
    @ViewState private var image: NSImage?
    @ViewState private var loaded = false
    var body: some View {
        Group { if let image { Image(nsImage: image).resizable().scaledToFit() } else if loaded { VStack { Image(systemName: "photo.badge.exclamationmark"); Text("无法预览").font(.caption); Text(url.lastPathComponent).font(.caption2).lineLimit(1) }.foregroundStyle(.secondary) } else { ProgressView().controlSize(.small) } }
            .task(id: "\(url.path):\(pixels)") { image = nil; loaded = false; let value = await PreviewService.shared.load(url, pixels: pixels); guard !Task.isCancelled else { return }; image = value; loaded = true }
    }
}
struct KeyHandler: NSViewRepresentable {
    let handler: (String) -> Bool
    func makeNSView(context: Context) -> NSView { let view = NSView(); context.coordinator.handler = handler; context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        guard event.window == view.window, !event.modifierFlags.contains(.command), !(event.window?.firstResponder is NSTextView) else { return event }
        return context.coordinator.handler?(event.charactersIgnoringModifiers ?? "") == true ? nil : event
    }; return view }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.handler = handler }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var monitor: Any?; var handler: ((String) -> Bool)?; deinit { if let monitor { NSEvent.removeMonitor(monitor) } } }
}
