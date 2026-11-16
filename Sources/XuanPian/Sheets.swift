import SwiftUI
import AppKit

struct ExportSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @ViewState private var prefix = ""
    @ViewState private var choice = ExportChoice.both
    var plan: ExportPlan? { try? ExportPlan(assets: store.keptAssets, prefix: prefix, choice: choice) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("给这一组好照片起个名字").font(.title2.bold())
            Text("导出本轮全部 \(store.keptAssets.count) 张保留照片，原片保持不变。").foregroundStyle(.secondary)
            TextField("例如：嘉定湖", text: $prefix).textFieldStyle(.roundedBorder)
            Picker("RAW / JPEG 配对文件", selection: $choice) { ForEach(ExportChoice.allCases) { Text($0.rawValue).tag($0) } }
            Text("单文件照片按原格式导出；配对文件共用编号。").font(.caption).foregroundStyle(.secondary)
            if let plan {
                List(Array(plan.items.enumerated()), id: \.offset) { _, item in HStack { Text(item.source.lastPathComponent).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.right"); Spacer(); Text(item.name) } }.frame(height: 260)
            } else { ContentUnavailableView("输入名称以预览", systemImage: "character.cursor.ibeam", description: Text("名称不能包含 / 或 :，长度需少于 180 字节。")).frame(height: 260) }
            HStack { Button("取消", role: .cancel) { dismiss() }; Spacer(); Button("选择位置并导出…") {
                guard let plan else { return }
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "导出到这里"
                if panel.runModal() == .OK, let folder = panel.url { dismiss(); store.export(plan, parent: folder) }
            }.buttonStyle(.borderedProminent).disabled(plan == nil) }
        }.padding(28).frame(width: 620)
    }
}
struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @ViewState private var restoreIndex: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("轮次历史").font(.title2.bold())
            Text("恢复旧轮会替换后续轮次，可以使用 ⌘Z 撤销。").foregroundStyle(.secondary)
            List(Array((store.session?.rounds ?? []).enumerated()), id: \.offset) { index, round in
                HStack { VStack(alignment: .leading) { Text("第 \(index + 1) 轮").bold(); Text("\(round.candidates.count) 张 → 保留 \(round.kept.count) 张").foregroundStyle(.secondary) }; Spacer(); Button("从这轮继续") { restoreIndex = index } }
            }.frame(height: 280)
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 500)
        .alert("从这一轮重新继续？", isPresented: Binding(get: { restoreIndex != nil }, set: { if !$0 { restoreIndex = nil } })) { Button("取消", role: .cancel) { restoreIndex = nil }; Button("继续") { if let index = restoreIndex { store.restore(index); dismiss() } } } message: { Text("后续轮次将被替换，源文件不受影响。") }
    }
}
struct CompareView: View {
    let assets: [PhotoAsset]
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @ViewState private var pair: [PhotoAsset] = []
    @ViewState private var chosen: Set<String> = []
    @ViewState private var linked = true
    @ViewState private var pinned = false
    @ViewState private var zoom: CGFloat = 0
    @ViewState private var center = CGPoint(x: 0.5, y: 0.5)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(pair.isEmpty ? "多图对比 · \(assets.count) 张" : pair.count == 1 ? "照片详情" : "双图对比").font(.headline)
                Spacer()
                if pair.count == 2 {
                    Toggle("联动缩放", isOn: $linked).toggleStyle(.checkbox)
                    Toggle("固定左图", isOn: $pinned).toggleStyle(.checkbox)
                    Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
                    Button { cycle(1) } label: { Image(systemName: "chevron.right") }
                }
                if !pair.isEmpty { Button("适应") { zoom = 0; center = CGPoint(x: 0.5, y: 0.5) }; Button("100%") { zoom = 1 } }
                if assets.count > 2 && !pair.isEmpty { Button("返回组") { pair = []; chosen = [] } }
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            if pair.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                        ForEach(assets) { asset in PhotoCard(asset: asset, selected: chosen.contains(asset.id), kept: store.session?.current.kept.contains(asset.id) ?? false, size: 290) { store.toggle(asset.id) }.onTapGesture { if chosen.contains(asset.id) { chosen.remove(asset.id) } else if chosen.count < 2 { chosen.insert(asset.id) } } }
                    }.padding(20)
                }
                HStack { Text("选择两张，检查焦点与细节").foregroundStyle(.secondary); Spacer(); Button("双图对比") { pair = assets.filter { chosen.contains($0.id) } }.disabled(chosen.count != 2).buttonStyle(.borderedProminent) }.padding(18)
            } else {
                HStack(spacing: 1) {
                    ForEach(pair) { asset in
                        VStack {
                            ZoomPhoto(url: asset.files.first(where: PhotoAsset.isRAW) ?? asset.previewURL, linked: linked, zoom: $zoom, center: $center)
                            HStack { Text(asset.name).lineLimit(1); Text(asset.formats.joined(separator: "+")).foregroundStyle(.secondary); Spacer(); Button { store.toggle(asset.id) } label: { Label(store.session?.current.kept.contains(asset.id) == true ? "已保留" : "保留", systemImage: store.session?.current.kept.contains(asset.id) == true ? "checkmark.circle.fill" : "circle") }.tint(store.session?.current.kept.contains(asset.id) == true ? .green : .accentColor) }.padding(14)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }.frame(width: 1000, height: 680)
        .onAppear { if assets.count <= 2 { pair = assets } }
        .background { KeyHandler { key in if key == "\u{f702}" { cycle(-1); return true }; if key == "\u{f703}" { cycle(1); return true }; return false } }
    }
    private func cycle(_ delta: Int) {
        let pool = assets.count > 2 ? assets : store.assets
        guard !pair.isEmpty, pool.count > pair.count else { return }
        let slot = pair.count - 1
        guard let current = pool.firstIndex(where: { $0.id == pair[slot].id }) else { return }
        for step in 1...pool.count {
            let next = pool[(current + delta * step % pool.count + pool.count) % pool.count]
            if pair.count == 1 || next.id != pair[0].id { if !pinned && pair.count == 2 { pair[0] = pair[1] }; pair[slot] = next; break }
        }
    }
}
struct ZoomPhoto: View {
    let url: URL; let linked: Bool
    @Binding var zoom: CGFloat
    @Binding var center: CGPoint
    @ViewState private var image: NSImage?
    @ViewState private var failed = false
    @ViewState private var localZoom: CGFloat = 0
    @ViewState private var localCenter = CGPoint(x: 0.5, y: 0.5)
    @ViewState private var dragOrigin: CGPoint?
    var body: some View {
        GeometryReader { geo in
            if let image {
                let factor = (linked ? zoom : localZoom)
                let fit = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                let scale = factor == 0 ? fit : factor / (NSScreen.main?.backingScaleFactor ?? 2)
                let width = image.size.width * scale, height = image.size.height * scale
                let pos = linked ? center : localCenter
                Image(nsImage: image).resizable().frame(width: width, height: height)
                    .position(x: geo.size.width / 2 + (0.5 - pos.x) * max(0, width - geo.size.width), y: geo.size.height / 2 + (0.5 - pos.y) * max(0, height - geo.size.height))
                    .frame(width: geo.size.width, height: geo.size.height).contentShape(Rectangle()).clipped()
                    .gesture(DragGesture().onChanged { value in
                        if dragOrigin == nil { dragOrigin = pos }
                        let start = dragOrigin!
                        let p = CGPoint(x: min(1, max(0, start.x - value.translation.width / max(1, width - geo.size.width))), y: min(1, max(0, start.y - value.translation.height / max(1, height - geo.size.height))))
                        if linked { center = p } else { localCenter = p }
                    }.onEnded { _ in dragOrigin = nil })
                    .onTapGesture(count: 2) { if linked { zoom = zoom == 0 ? 1 : 0 } else { localZoom = localZoom == 0 ? 1 : 0 } }
            } else if failed { ContentUnavailableView("无法读取高清图片", systemImage: "photo.badge.exclamationmark", description: Text("检查源文件是否在线，或当前 macOS 是否支持此 RAW。")) }
            else { ProgressView("正在加载高清图…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(Color.black.opacity(0.06)).clipped()
        .task(id: "\(url.path):\((linked ? zoom : localZoom) == 0 ? 2800 : 16000)") { image = nil; failed = false; let value = await PreviewService.shared.load(url, pixels: (linked ? zoom : localZoom) == 0 ? 2800 : 16000); guard !Task.isCancelled else { return }; image = value; failed = value == nil }
        .onChange(of: zoom) { _, value in localZoom = value }
    }
}
