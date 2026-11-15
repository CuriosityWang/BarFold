import AppKit
import SwiftUI
import Combine

@main
struct BarFoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: model.ownID).count <= 1 else {
            NSApplication.shared.terminate(nil); return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "BarFoldToggle"
        statusItem = item
        let statusIcon = NSImage(named: "AppIcon")?.copy() as? NSImage
        statusIcon?.size = NSSize(width: 20, height: 20)
        statusIcon?.isTemplate = false
        item.button?.image = statusIcon
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        Publishers.CombineLatest4(model.$expanded, model.$paused, model.$applying, model.$hasPermission)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in self?.updateButton() }
            .store(in: &subscriptions)
        updateButton()
        model.start()
        if model.shouldOpenSettingsOnLaunch {
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }

    private func updateButton() {
        let action = model.paused ? "恢复管理" : (model.expanded ? "收起图标" : "展开图标")
        statusItem?.button?.alphaValue = model.paused ? 0.5 : 1
        statusItem?.button?.toolTip = "菜单栏收纳 · \(model.stateText)\n右键打开配置"
        statusItem?.button?.setAccessibilityLabel("菜单栏收纳，\(action)")
    }

    @objc private func clicked() {
        guard let event = NSApplication.shared.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let menu = NSMenu()
            add("配置图标…", to: menu, action: #selector(showSettings))
            add(model.expanded ? "收起图标" : "展开图标", to: menu, action: #selector(toggle))
            add(model.paused ? "恢复管理" : "暂停并恢复图标", to: menu, action: #selector(togglePause))
            menu.addItem(.separator())
            let loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            loginItem.target = self
            loginItem.state = model.launchAtLogin ? .on : .off
            loginItem.isEnabled = model.installedCorrectly
            menu.addItem(loginItem)
            menu.addItem(.separator())
            add("退出收纳", to: menu, action: #selector(quit))
            if let button = statusItem?.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else if !model.canConfigure { showSettings() }
        else { model.toggle() }
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    @objc private func toggle() { model.toggle() }
    @objc private func togglePause() { if model.paused { model.resume() } else { model.pause() } }
    @objc private func toggleLaunchAtLogin() { model.setLaunchAtLogin(!model.launchAtLogin) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let panel = NSWindow(contentViewController: controller)
            panel.title = "菜单栏收纳"
            panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            panel.setContentSize(NSSize(width: 720, height: 660))
            panel.minSize = NSSize(width: 680, height: 520)
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.setSettingsWindowOpen(true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        model.setSettingsWindowOpen(false)
        window?.contentViewController = nil
        window = nil
        AppIconCache.clear()
    }
}
