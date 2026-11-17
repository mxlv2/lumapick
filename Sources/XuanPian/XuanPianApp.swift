import SwiftUI
import AppKit

// Explicit property-wrapper alias supports SDKs that also declare a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct XuanPianApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("留影") { ContentView().environmentObject(store).frame(minWidth: 900, minHeight: 620) }
            .defaultSize(width: 1280, height: 820)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) { Button("打开文件夹…") { store.open() }.keyboardShortcut("o").disabled(store.busy) }
                CommandGroup(after: .pasteboard) {
                    Button("全选照片") { store.selected = Set(store.assets.map(\.id)) }.keyboardShortcut("a").disabled(store.busy)
                    Button("取消所选保留") { store.mark(store.selected, kept: false) }.disabled(store.busy || store.selected.isEmpty)
                }
                CommandGroup(replacing: .undoRedo) { Button("撤销") { store.undo() }.keyboardShortcut("z").disabled(store.busy) }
            }
    }
}
struct ViewerSelection: Identifiable { let id = UUID(); let assets: [PhotoAsset] }
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var size: Double = 220
    @ViewState private var showExport = false
    @ViewState private var viewer: ViewerSelection?
    @ViewState private var history = false
    @ViewState private var dropTarget = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                if let session = store.session {
                    header(session)
                    Rectangle().fill(.primary.opacity(0.06)).frame(height: 1)
                    grid(session)
                    footer(session)
                } else { welcome }
            }.background(Color.studioCanvas)
        }
        .accessibilityHidden(viewer != nil)
        .tint(.studioAccent)
        .onCommand(#selector(NSText.selectAll(_:))) { if !store.busy { store.selected = Set(store.assets.map(\.id)) } }
        .disabled(store.busy)
        .overlay {
            if let selection = viewer {
                CompareView(assets: selection.assets) { withAnimation(motion) { viewer = nil } }
                    .environmentObject(store).background(Color.studioCanvas).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985)))
            }
        }
        .overlay {
            if store.busy {
                Color.black.opacity(0.08).ignoresSafeArea()
                VStack(spacing: 14) { ProgressView().controlSize(.small); Text(store.status).font(.headline); if store.status.contains("复制") { Text("已复制 \(store.exportProgress) 个文件").foregroundStyle(.secondary); Button("取消导出", role: .cancel) { store.cancelExport() }.buttonStyle(StudioButtonStyle()) } }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).shadow(color: .black.opacity(0.08), radius: 24, y: 10)
            }
        }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.studioAccent, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(10).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in var dir: ObjCBool = false; if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue { store.load(url) } } } }; return true
        }
        .background { KeyHandler { key in
            guard !showExport, viewer == nil, !history, !store.busy else { return false }
            switch key {
            case "p": withAnimation(motion) { store.mark(store.selected, kept: true) }
            case "u": withAnimation(motion) { store.mark(store.selected, kept: false) }
            case " ": openViewer()
            case "\u{1b}": withAnimation(motion) { store.isolation = nil; store.selected = [] }
            case "\u{f702}": step(-1)
            case "\u{f703}": step(1)
            default: return false
            }; return true
        } }
        .sheet(isPresented: $showExport) { ExportSheet().environmentObject(store) }
        .sheet(isPresented: $history) { HistoryView().environmentObject(store) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好", role: .cancel) {} } message: { Text(store.error ?? "") }
    }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86) }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 11) { StudioMark(); VStack(alignment: .leading, spacing: 3) { Text("留影").font(.system(size: 21, weight: .semibold, design: .rounded)); Text("LUMAPICK").font(.system(size: 9, weight: .medium)).tracking(2.5).foregroundStyle(.tertiary) } }.padding(.top, 38)
            Button(action: store.open) { Label("打开照片文件夹", systemImage: "folder.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(StudioButtonStyle())
            if let session = store.session {
                VStack(alignment: .leading, spacing: 12) {
                    Text("当前拍摄").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    Label(session.folder.lastPathComponent, systemImage: "folder").font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text("\(session.assets.count) 张照片").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("筛选历程").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary); Spacer(); Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.plain).foregroundStyle(.secondary).help("查看与恢复轮次") }
                    ForEach(Array(session.rounds.enumerated()).suffix(5), id: \.offset) { index, round in
                        HStack(spacing: 10) {
                            Text(String(index + 1)).font(.system(size: 10, weight: .semibold, design: .rounded)).frame(width: 24, height: 24).background(index == session.rounds.count - 1 ? Color.studioAccent : .primary.opacity(0.05), in: Circle()).foregroundStyle(index == session.rounds.count - 1 ? .white : .secondary)
                            Text(index == 0 ? "粗筛" : index == 1 ? "精筛" : "第 \(index + 1) 轮").font(.system(size: 12, weight: .medium))
                            Spacer(); Text("\(round.candidates.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }
                }
                Button("重新定位来源", systemImage: "externaldrive.badge.questionmark") { store.relocate() }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("包含子文件夹", isOn: $store.recursive).toggleStyle(.switch).controlSize(.mini).font(.caption).help("下次打开文件夹时生效")
            HStack(spacing: 6) { Circle().fill(Color.studioAccent).frame(width: 5, height: 5); Text("本地选片 · 原片保留").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(.bottom, 18)
        }.padding(.horizontal, 20).frame(width: 184).frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }
    private func header(_ session: CullingSession) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text(store.isolation == nil ? session.folder.lastPathComponent : "专注这一组").font(.system(size: 25, weight: .semibold, design: .rounded)).lineLimit(1); Text(store.isolation == nil ? "\(store.roundName) · 留下值得再看一眼的照片" : "隔离选片 · 保留标记同步当前轮").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                if store.isolation != nil { Button { withAnimation(motion) { store.isolation = nil; store.selected = [] } } label: { Label("返回本轮", systemImage: "arrow.uturn.backward") }.buttonStyle(StudioButtonStyle()) }
            }
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 2) { ForEach(store.formats, id: \.self) { format in FormatChip(title: format, active: store.format == format) { withAnimation(motion) { store.format = format; store.selected = [] } } } } }
                HStack(spacing: 6) { Image(systemName: "square.grid.2x2").font(.system(size: 11)).foregroundStyle(.tertiary); Slider(value: $size, in: 160...320, step: 20).controlSize(.mini).frame(width: 80) }.help("调整照片大小")
            }
        }.padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 18)
    }
    private func grid(_ session: CullingSession) -> some View {
        Group {
            if store.assets.isEmpty { ContentUnavailableView("这里暂时没有照片", systemImage: "photo.on.rectangle", description: Text("试试切换格式，或打开新的照片文件夹。")) }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: size), spacing: 18)], spacing: 20) {
                            ForEach(store.assets) { asset in
                                PhotoCard(asset: asset, selected: store.selected.contains(asset.id), kept: session.current.kept.contains(asset.id), size: size) { withAnimation(motion) { store.toggle(asset.id) } }
                                    .id(asset.id).onTapGesture(count: 2) { withAnimation(motion) { viewer = ViewerSelection(assets: [asset]) } }.onTapGesture { select(asset) }
                                    .contextMenu { Button("加入对比选择") { store.selected.insert(asset.id) }; Button("保留") { store.mark([asset.id], kept: true) }; Button("取消保留") { store.mark([asset.id], kept: false) }; Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(asset.files) } }
                            }
                        }.padding(26)
                    }.onChange(of: store.selected) { _, ids in if ids.count == 1, let id = ids.first { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) } } }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func footer(_ session: CullingSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 7) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.studioAccent); Text("\(session.current.kept.count)").font(.system(size: 17, weight: .semibold, design: .rounded)).contentTransition(.numericText()); Text("/ \(session.current.candidates.count) 张保留").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { withAnimation(motion) { store.isolation = store.assets.filter { store.selected.contains($0.id) }.map(\.id); store.selected = [] } } label: { Label("隔离", systemImage: "viewfinder") }.buttonStyle(StudioButtonStyle()).disabled(store.selected.count < 2)
                Button(action: openViewer) { Label("对比", systemImage: "rectangle.split.2x1") }.buttonStyle(StudioButtonStyle()).disabled(store.selected.isEmpty)
                if session.completed {
                    if let result = store.result { Button("打开结果", systemImage: "arrow.up.right") { NSWorkspace.shared.open(result) }.buttonStyle(StudioButtonStyle(prominent: true)) }
                    else { Label("已完成", systemImage: "checkmark.seal").font(.caption).foregroundStyle(Color.studioAccent) }
                } else if store.isolation == nil {
                    Button("下一轮", systemImage: "arrow.right") { withAnimation(motion) { store.advance() } }.buttonStyle(StudioButtonStyle()).disabled(store.keptAssets.isEmpty)
                    Button("命名并导出", systemImage: "square.and.arrow.up") { showExport = true }.buttonStyle(StudioButtonStyle(prominent: true)).disabled(store.keptAssets.isEmpty)
                }
            }
            HStack(spacing: 7) { KeyboardHint(title: "P"); Text("保留"); KeyboardHint(title: "U"); Text("取消"); KeyboardHint(title: "SPACE"); Text("查看"); Spacer(); Text(store.status.isEmpty ? (store.selected.isEmpty ? "⌘ 点击多选照片" : "已选中 \(store.selected.count) 张") : store.status) }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 26).padding(.vertical, 18).background(.regularMaterial)
    }
    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                ForEach(0..<3) { i in RoundedRectangle(cornerRadius: 22).fill(Color.studioAccent.opacity(Double(i + 1) * 0.035)).frame(width: 182, height: 224).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.studioAccent.opacity(0.12))).rotationEffect(.degrees(Double(i - 1) * 12)).offset(x: CGFloat(i - 1) * 32, y: CGFloat(abs(i - 1)) * 10) }
                Image(systemName: "camera.macro").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(Color.studioAccent)
            }.frame(height: 260).padding(.bottom, 24)
            Text("让好照片，留下来。").font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.7)
            Text("从一整次拍摄，到值得精修的几张。\n一轮一轮，找到你的心动之作。").font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(7).multilineTextAlignment(.center).padding(.top, 16)
            Button(action: store.open) { Label("选择照片文件夹", systemImage: "folder.badge.plus").padding(.horizontal, 12).padding(.vertical, 3) }.buttonStyle(StudioButtonStyle(prominent: true)).padding(.top, 30)
            Text("或将文件夹拖入窗口").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 14)
            Spacer()
            HStack(spacing: 28) { Label("RAW 预览", systemImage: "camera.aperture"); Label("多轮精选", systemImage: "square.stack"); Label("原片导出", systemImage: "arrow.up.right.square") }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.bottom, 40)
        }.frame(maxWidth: .infinity)
    }
    private func openViewer() { let chosen = store.assets.filter { store.selected.contains($0.id) }; if !chosen.isEmpty { withAnimation(motion) { viewer = ViewerSelection(assets: chosen) } } }
    private func step(_ delta: Int) {
        let items = store.assets; guard !items.isEmpty else { return }
        let current = items.firstIndex { store.selected.contains($0.id) } ?? (delta > 0 ? -1 : items.count)
        store.selected = [items[min(items.count - 1, max(0, current + delta))].id]
    }
    private func select(_ asset: PhotoAsset) {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if flags.contains(.command) { if store.selected.contains(asset.id) { store.selected.remove(asset.id) } else { store.selected.insert(asset.id) } }
        else if flags.contains(.shift), let first = store.assets.firstIndex(where: { store.selected.contains($0.id) }), let last = store.assets.firstIndex(of: asset) { store.selected.formUnion(store.assets[min(first,last)...max(first,last)].map(\.id)) }
        else { store.selected = [asset.id] }
    }
}
struct PhotoCard: View {
    let asset: PhotoAsset; let selected: Bool; let kept: Bool; let size: Double; let toggle: () -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var hovering = false
    private var pixels: Int { Int(ceil(size * displayScale / 256)) * 256 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Thumbnail(url: asset.previewURL, pixels: pixels).frame(height: size * 0.75).frame(maxWidth: .infinity).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button(action: toggle) { Image(systemName: kept ? "checkmark" : "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(kept ? .white : .primary).frame(width: 27, height: 27).background(kept ? AnyShapeStyle(Color.studioAccent) : AnyShapeStyle(.regularMaterial), in: Circle()).shadow(color: .black.opacity(0.08), radius: 4, y: 2) }.buttonStyle(.plain).accessibilityLabel(kept ? "取消保留" : "保留照片").help(kept ? "取消保留 · U" : "保留照片 · P").padding(9)
                }
            HStack(spacing: 6) { Text(asset.name).lineLimit(1).font(.system(size: 11, weight: .medium)); Spacer(minLength: 2); Text(asset.formats.joined(separator: " + ")).font(.system(size: 8, weight: .semibold)).tracking(0.3).foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 3).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4)) }
        }.padding(9)
            .background(selected ? Color.studioAccent.opacity(0.055) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Color.studioAccent : Color.primary.opacity(hovering ? 0.12 : 0.04), lineWidth: selected ? 2 : 1))
            .shadow(color: .black.opacity(hovering ? 0.07 : 0.025), radius: hovering ? 12 : 5, y: hovering ? 5 : 2)
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: 18)).onHover { hovering = $0 }
    }
}
struct Thumbnail: View {
    let url: URL; let pixels: Int
    @ViewState private var image: NSImage?
    @ViewState private var loaded = false
    @ViewState private var displayedURL: URL?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            else if loaded { VStack(spacing: 7) { Image(systemName: "photo.badge.exclamationmark"); Text("无法预览").font(.system(size: 10)) }.foregroundStyle(.tertiary) }
            else { Rectangle().fill(.primary.opacity(0.025)).overlay(Image(systemName: "photo").font(.system(size: 24, weight: .ultraLight)).foregroundStyle(.quaternary)) }
        }
        .task(id: "\(url.path):\(pixels)") {
            if displayedURL != url { image = nil; displayedURL = url }
            loaded = false
            if image == nil, let quick = await PreviewService.shared.load(url, quality: .embedded(pixels)) { guard !Task.isCancelled else { return }; image = quick.nsImage }
            let sharp = await PreviewService.shared.load(url, quality: .thumbnail(pixels))
            guard !Task.isCancelled else { return }
            if let sharp { image = sharp.nsImage }; loaded = true
        }
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
