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
            HStack { Button("取消", role: .cancel) { dismiss() }.buttonStyle(StudioButtonStyle()); Spacer(); Button("选择位置并导出…") {
                guard let plan else { return }
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "导出到这里"
                if panel.runModal() == .OK, let folder = panel.url { dismiss(); store.export(plan, parent: folder) }
            }.buttonStyle(StudioButtonStyle(prominent: true)).disabled(plan == nil) }
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
    let onClose: () -> Void
    @EnvironmentObject var store: AppStore
    @ViewState private var pair: [PhotoAsset] = []
    @ViewState private var chosen: Set<String> = []
    @ViewState private var linked = true
    @ViewState private var pinned = false
    @ViewState private var zoom: CGFloat = 0
    @ViewState private var center = CGPoint(x: 0.5, y: 0.5)
    private var pool: [PhotoAsset] { assets.count > 2 ? assets : store.assets }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(action: onClose) { Label("返回选片", systemImage: "arrow.left") }.buttonStyle(StudioButtonStyle())
                Text(pair.isEmpty ? "多图对比 · \(assets.count) 张" : pair.count == 1 ? "照片详情" : "双图对比").font(.system(size: 13, weight: .semibold))
                Spacer()
                if pair.count == 2 {
                    Toggle("联动", isOn: $linked).toggleStyle(.switch).controlSize(.mini)
                    Button { pinned.toggle() } label: { Label("固定左图", systemImage: pinned ? "pin.fill" : "pin") }.buttonStyle(StudioButtonStyle(prominent: pinned))
                }
                if !pair.isEmpty {
                    HStack(spacing: 1) { FormatChip(title: "适应", active: zoom == 0) { zoom = 0; center = CGPoint(x: 0.5, y: 0.5) }; FormatChip(title: "100%", active: zoom == 1) { zoom = 1 } }
                    Button { cycle(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(StudioButtonStyle())
                    Button { cycle(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(StudioButtonStyle())
                }
                if assets.count > 2 && !pair.isEmpty { Button("返回组") { pair = []; chosen = [] }.buttonStyle(StudioButtonStyle()) }
            }.font(.system(size: 12)).padding(.horizontal, 24).padding(.top, 38).padding(.bottom, 18)
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 1)
            if pair.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 20) {
                        ForEach(assets) { asset in PhotoCard(asset: asset, selected: chosen.contains(asset.id), kept: store.session?.current.kept.contains(asset.id) ?? false, size: 290) { store.toggle(asset.id) }.onTapGesture { if chosen.contains(asset.id) { chosen.remove(asset.id) } else if chosen.count < 2 { chosen.insert(asset.id) } } }
                    }.padding(26)
                }
                HStack { Text("选择两张，检查焦点与细节").foregroundStyle(.secondary); Spacer(); Button("双图对比") { pair = assets.filter { chosen.contains($0.id) } }.disabled(chosen.count != 2).buttonStyle(StudioButtonStyle(prominent: true)) }.padding(24)
            } else {
                HStack(spacing: 12) {
                    ForEach(pair) { asset in
                        VStack(spacing: 0) {
                            ZoomPhoto(asset: asset, linked: linked, zoom: $zoom, center: $center)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            HStack(spacing: 8) {
                                if pinned && pair.first?.id == asset.id { Image(systemName: "pin.fill").foregroundStyle(Color.studioAccent) }
                                Text(asset.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(asset.formats.joined(separator: " + ")).font(.system(size: 10)).foregroundStyle(.tertiary)
                                Spacer()
                                Button { store.toggle(asset.id) } label: { Label(store.session?.current.kept.contains(asset.id) == true ? "已保留" : "保留", systemImage: store.session?.current.kept.contains(asset.id) == true ? "checkmark" : "plus") }.buttonStyle(StudioButtonStyle(prominent: store.session?.current.kept.contains(asset.id) == true))
                            }.padding(.top, 14)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(20)
                HStack(spacing: 7) { KeyboardHint(title: "← →"); Text("切换照片"); KeyboardHint(title: "双击"); Text("检查焦点"); Text("· 拖动平移 · 捏合缩放"); Spacer(); KeyboardHint(title: "ESC"); Text("返回") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 18)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.studioCanvas)
        .onAppear { if assets.count <= 2 { pair = assets } }
        .task(id: pair.map(\.id)) {
            guard let current = pair.last, let index = pool.firstIndex(where: { $0.id == current.id }), pool.count > 1 else { return }
            let urls = [pool[(index + 1) % pool.count].previewURL, pool[(index + pool.count - 1) % pool.count].previewURL]
            await PreviewService.shared.prefetch(urls)
        }
        .background { KeyHandler { key in
            switch key {
            case "\u{f702}": cycle(-1)
            case "\u{f703}": cycle(1)
            case "\u{1b}": onClose()
            case "p", "u": if let current = pair.last { store.mark([current.id], kept: key == "p") }
            default: return false
            }; return true
        } }
    }
    private func cycle(_ delta: Int) {
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
    let asset: PhotoAsset; let linked: Bool
    @Binding var zoom: CGFloat
    @Binding var center: CGPoint
    @Environment(\.displayScale) private var displayScale
    @ViewState private var frame: PreviewFrame?
    @ViewState private var displayedID: String?
    @ViewState private var loading = true
    @ViewState private var failed = false
    @ViewState private var localZoom: CGFloat = 0
    @ViewState private var localCenter = CGPoint(x: 0.5, y: 0.5)
    @ViewState private var dragOrigin: CGPoint?
    @ViewState private var pinchOrigin: CGFloat?
    private var factor: CGFloat { linked ? zoom : localZoom }
    private var position: CGPoint { linked ? center : localCenter }
    var body: some View {
        GeometryReader { geo in
            let pixels = max(2560, Int(ceil(max(geo.size.width, geo.size.height) * displayScale / 512)) * 512)
            ZStack {
                Color.primary.opacity(0.035)
                if let frame {
                    let native = frame.nativeSize
                    let fit = min(geo.size.width / native.width, geo.size.height / native.height)
                    let scale = factor == 0 ? fit : factor / displayScale
                    let width = native.width * scale, height = native.height * scale
                    Image(nsImage: frame.nsImage).resizable().interpolation(.high).frame(width: width, height: height)
                        .position(x: geo.size.width / 2 + (0.5 - position.x) * max(0, width - geo.size.width), y: geo.size.height / 2 + (0.5 - position.y) * max(0, height - geo.size.height))
                        .frame(width: geo.size.width, height: geo.size.height).contentShape(Rectangle()).clipped()
                        .gesture(DragGesture().onChanged { value in
                            if dragOrigin == nil { dragOrigin = position }
                            let start = dragOrigin!
                            setCenter(CGPoint(x: min(1, max(0, start.x - value.translation.width / max(1, width - geo.size.width))), y: min(1, max(0, start.y - value.translation.height / max(1, height - geo.size.height)))))
                        }.onEnded { _ in dragOrigin = nil })
                        .simultaneousGesture(MagnificationGesture().onChanged { value in
                            if pinchOrigin == nil { pinchOrigin = factor == 0 ? fit * displayScale : factor }
                            setZoom(min(4, max(fit * displayScale, pinchOrigin! * value)))
                        }.onEnded { _ in pinchOrigin = nil })
                        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                            if factor == 0 {
                                let imageX = (value.location.x - (geo.size.width - width) / 2) / width
                                let imageY = (value.location.y - (geo.size.height - height) / 2) / height
                                let fullW = native.width / displayScale, fullH = native.height / displayScale
                                setCenter(CGPoint(x: min(1, max(0, (imageX * fullW - geo.size.width / 2) / max(1, fullW - geo.size.width))), y: min(1, max(0, (imageY * fullH - geo.size.height / 2) / max(1, fullH - geo.size.height)))))
                                setZoom(1)
                            } else { setZoom(0); setCenter(CGPoint(x: 0.5, y: 0.5)) }
                        })
                } else if failed { ContentUnavailableView("无法预览", systemImage: "photo.badge.exclamationmark", description: Text("检查源文件与系统 RAW 支持。")) }
                else { ProgressView().controlSize(.small) }
            }.overlay(alignment: .topLeading) {
                if loading || (factor > 0 && frame?.originalResolution != true) {
                    HStack(spacing: 6) { if loading { ProgressView().controlSize(.mini) }; Text(loading ? (factor > 0 ? "正在载入原尺寸…" : "正在载入清晰预览…") : "当前显示预览，原尺寸不可用").font(.system(size: 10)) }.padding(9).background(.regularMaterial, in: Capsule()).padding(12)
                }
            }
            .task(id: "\(asset.id):\(factor == 0 ? pixels : 0)") {
                if displayedID != asset.id { frame = nil; displayedID = asset.id }
                loading = true; failed = false
                if frame == nil {
                    if let quick = await PreviewService.shared.load(asset.previewURL, quality: .thumbnail(768)) { guard !Task.isCancelled else { return }; frame = quick }
                }
                let url = factor > 0 ? asset.files.first(where: PhotoAsset.isRAW) ?? asset.previewURL : asset.previewURL
                let sharp = await PreviewService.shared.load(url, quality: factor > 0 ? .original : .screen(pixels))
                guard !Task.isCancelled else { return }
                if let sharp { frame = sharp }; failed = frame == nil; loading = false
            }
        }.clipped()
        .onChange(of: zoom) { _, value in localZoom = value }
        .onChange(of: linked) { _, _ in localZoom = zoom; localCenter = center }
    }
    private func setZoom(_ value: CGFloat) { if linked { zoom = value } else { localZoom = value } }
    private func setCenter(_ value: CGPoint) { if linked { center = value } else { localCenter = value } }
}
