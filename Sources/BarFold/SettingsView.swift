import AppKit
import SwiftUI
import BarFoldCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""

    private var filtered: [MenuApp] {
        model.items.filter {
            search.isEmpty
            || $0.name.localizedCaseInsensitiveContains(search)
            || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("菜单栏收纳").font(.title2.bold())
                    Text("拖动应用到分组，或点击应用更改显示方式").foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.expanded ? "收起图标" : "展开图标", action: model.toggle)
                    .disabled(!model.canConfigure || model.paused)
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            if !model.installedCorrectly {
                notice("请将 BarFold 移到系统的“应用程序”文件夹后重新打开，才能启用图标管理。", symbol: "folder") { EmptyView() }
            }
            if !model.hasPermission {
                notice("允许辅助功能访问后，才能读取和管理菜单栏图标。", symbol: "hand.raised") {
                    Button("打开权限设置", action: model.requestPermission)
                }
            }
            if !model.supported {
                notice("当前系统的图标管理接口不可用。配置会保留，图标保持显示。", symbol: "info.circle") { EmptyView() }
            }
            if let error = model.error {
                notice(error, symbol: "exclamationmark.triangle") {
                    Button("恢复管理", action: model.resume).disabled(!model.canConfigure)
                }
            }
            if let app = model.conflictingApp {
                notice("\(app) 也在管理菜单栏。使用收纳前，请先退出它，避免显隐冲突。", symbol: "info.circle") { EmptyView() }
            }

            HStack(spacing: 16) {
                Toggle("登录时启动", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )).disabled(!model.installedCorrectly)

                Spacer()

                HStack(spacing: 6) {
                    Text("自动收起").foregroundStyle(.secondary)
                    Picker("自动收起", selection: Binding(
                        get: { model.preferences.autoCollapse },
                        set: { model.setAutoCollapse($0) }
                    )) {
                        ForEach(AutoCollapseDelay.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 112)
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用或 Bundle ID", text: $search).textFieldStyle(.plain).accessibilityLabel("搜索应用")
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("\(model.items.count) 个应用").foregroundStyle(.secondary)
            }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 24).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Placement.allCases, id: \.self) { placement in
                        AppPlacementGroup(
                            model: model,
                            placement: placement,
                            items: filtered.filter { model.placement(for: $0.id) == placement },
                            searching: !search.isEmpty
                        )
                    }
                }.padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("隐藏组中的应用在展开时仍隐藏，可随时拖回其他分组。")
                Text("隐藏期间，“专注模式”等部分系统状态图标也可能消失。Wi‑Fi、音量、电池、时钟和控制中心会保留。")
            }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            HStack {
                if model.applying || model.scanning { ProgressView().controlSize(.small) }
                Text(model.stateText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.paused ? "恢复管理" : "暂停并恢复图标") {
                    if model.paused { model.resume() } else { model.pause() }
                }.disabled(!model.canConfigure)
                Button("发现隐藏图标") { Task { await model.discoverAllIcons() } }
                    .disabled(!model.canConfigure || model.scanning)
                    .help("短暂恢复全部菜单栏图标以扫描新启动的应用，随后自动恢复隐藏规则")
                Button("刷新图标") { Task { await model.refresh() } }.disabled(model.scanning)
            }.padding(16)
        }.frame(minWidth: 680, minHeight: 520)
    }

    private func notice<Content: View>(_ message: String, symbol: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action()
        }.font(.callout).padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24).padding(.bottom, 12)
    }
}

private extension Placement {
    var groupTitle: String {
        switch self {
        case .visible: "常驻"
        case .collapsed: "收起"
        case .hidden: "隐藏"
        }
    }

    var groupDescription: String {
        switch self {
        case .visible: "始终显示"
        case .collapsed: "展开时显示"
        case .hidden: "展开时仍隐藏"
        }
    }
}

private struct AppPlacementGroup: View {
    @ObservedObject var model: AppModel
    let placement: Placement
    let items: [MenuApp]
    let searching: Bool
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(placement.groupTitle).font(.headline)
                Text(placement.groupDescription).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)").foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.top, 8)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(items) { item in
                        PlacementAppCard(model: model, item: item)
                            .frame(width: 80)
                    }
                    if items.isEmpty {
                        Text(searching ? "无匹配应用" : "拖入应用")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, height: 60)
                    }
                }.padding(.horizontal, 6).padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.4), lineWidth: isTargeted ? 2 : 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(placement.groupTitle)分组")
        .dropDestination(for: String.self) { ids, _ in
            guard model.canConfigure, ids.count == 1, let id = ids.first,
                  let item = model.items.first(where: { $0.id == id }) else { return false }
            model.setPlacement(placement, for: item)
            return true
        } isTargeted: { isTargeted = $0 && model.canConfigure }
    }
}

private struct PlacementAppCard: View {
    @ObservedObject var model: AppModel
    let item: MenuApp
    @State private var showingActions = false

    var body: some View {
        VStack(spacing: 4) {
            AppIcon(bundleID: item.id).frame(width: 24, height: 24)
            VStack(spacing: 2) {
                Text(item.name).font(.caption).fontWeight(.medium).lineLimit(2)
                    .multilineTextAlignment(.center)
                if !item.running {
                    Text("未运行").font(.caption2).foregroundStyle(.secondary)
                } else if item.count > 1 {
                    Text("\(item.count) 个图标").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { if model.canConfigure { showingActions = true } }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if model.canConfigure { showingActions = true } }
        .disabled(!model.canConfigure)
        .help("\(item.name)\n拖动到目标分组，或点击更改显示方式")
        .accessibilityLabel("\(item.name)，\(model.placement(for: item.id).groupTitle)")
        .draggable(item.id)
        .popover(isPresented: $showingActions) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.headline).padding(.bottom, 4)
                ForEach(Placement.allCases, id: \.self) { placement in
                    Button {
                        showingActions = false
                        model.setPlacement(placement, for: item)
                    } label: {
                        HStack {
                            Text("移到\(placement.groupTitle)")
                            Spacer()
                            if model.placement(for: item.id) == placement {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }.frame(width: 150).padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                if !item.running {
                    Divider()
                    Button("移除保留配置", role: .destructive) {
                        showingActions = false
                        model.removeOfflineRule(for: item.id)
                    }.buttonStyle(.plain).padding(.top, 4)
                }
            }.padding(16)
        }
    }
}

@MainActor
enum AppIconCache {
    private static var thumbnails: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = thumbnails[bundleID] { return cached }
        guard let url = AppBundleMetadata.iconURL(forBundleIdentifier: bundleID) else { return nil }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: 32, height: 32)
        let thumbnail = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        thumbnails[bundleID] = thumbnail
        return thumbnail
    }

    static func clear() {
        thumbnails.removeAll(keepingCapacity: false)
    }
}

private struct AppIcon: View {
    let bundleID: String
    var body: some View {
        if let image = AppIconCache.icon(for: bundleID) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
        }
    }
}
