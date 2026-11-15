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
                    Text("选择哪些应用常驻显示、收起或永久隐藏").foregroundStyle(.secondary)
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

                Divider().frame(height: 14)

                Toggle("全局快捷键 ⌥⌘B", isOn: Binding(
                    get: { model.preferences.hotkeyEnabled },
                    set: { model.setHotkeyEnabled($0) }
                )).disabled(!model.canConfigure)

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
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .opacity(0.75)
                                .accessibilityHidden(true)
                            Text(model.scanning ? "正在读取图标" : (search.isEmpty ? "暂无可配置的应用图标" : "未找到相关应用"))
                            if !model.scanning && search.isEmpty { Text("确认权限后，点击下方“刷新图标”").foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity).padding(50)
                    }
                    ForEach(filtered) { item in
                        HStack(spacing: 12) {
                            AppIcon(bundleID: item.id).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).fontWeight(.medium)
                                if !item.running { Text("未运行 · 保留配置").font(.caption).foregroundStyle(.secondary) }
                                else if item.count > 1 { Text("\(item.count) 个图标一起显隐").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 12)
                            if !item.running {
                                Button {
                                    model.removeOfflineRule(for: item.id)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("移除此未运行应用的保留配置")
                            }
                            Picker("\(item.name) 的显示方式", selection: Binding(
                                get: { model.placement(for: item.id) },
                                set: { model.setPlacement($0, for: item) }
                            )) {
                                ForEach(Placement.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.labelsHidden().pickerStyle(.segmented).frame(width: 260).disabled(!model.canConfigure)
                        }.padding(.vertical, 12).padding(.horizontal, 16)
                        Divider().padding(.leading, 60)
                    }
                }.background(.background, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("收起：展开时显示。永久隐藏：展开时仍隐藏，可随时在这里恢复。")
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
