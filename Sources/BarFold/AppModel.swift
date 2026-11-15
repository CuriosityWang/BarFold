import AppKit
@preconcurrency import ApplicationServices
import Combine
import ServiceManagement
import BarFoldCore
import MenuBarBridge

@MainActor
final class AppModel: ObservableObject {
    let ownID = Bundle.main.bundleIdentifier ?? "local.barfold.app"
    @Published private(set) var items: [MenuApp] = []
    @Published private(set) var rules: [String: SavedRule] = [:]
    @Published private(set) var preferences: Preferences
    @Published private(set) var launchAtLogin = false
    @Published private(set) var expanded = false
    @Published private(set) var applying = false
    @Published private(set) var scanning = false
    @Published private(set) var hasPermission = AXIsProcessTrusted()
    @Published private(set) var supported = BFMenuBarSession.supported
    @Published private(set) var error: String?
    @Published private(set) var paused = false
    @Published private(set) var conflictingApp: String?
    let installedCorrectly = Bundle.main.bundleURL.path.hasPrefix("/Applications/")

    private let store = RuleStore()
    private let preferencesStore = PreferencesStore()
    private let inventory = MenuBarInventory()
    private let mover = MenuBarMover()
    private let session = BFMenuBarSession()
    private var hotKey: GlobalHotKey?
    private var known: [String: DiscoveredApp] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var lastPlan: VisibilityPlan?
    private var lastEligibleRunning: Set<String> = []
    private var resolvedNames: [String: String] = [:]
    private var settingsWindowOpen = false
    private var orderingFailed = false
    private var overflowFailed = false
    private var discovering = false
    private var storageFailed = false
    private var stopped = false
    private var runningObservation: NSKeyValueObservation?

    init() {
        preferences = preferencesStore.load()
        do { rules = try store.load() }
        catch { storageFailed = true; self.error = "配置读取失败，已暂停管理。原配置未被覆盖。"; paused = true }
    }

    var canConfigure: Bool { hasPermission && supported && installedCorrectly && !storageFailed && !stopped }
    var shouldOpenSettingsOnLaunch: Bool {
        LaunchPolicy.shouldOpenSettingsOnLaunch(canConfigure: canConfigure, hasSavedRules: !rules.isEmpty)
    }

    var stateText: String {
        if !supported { return "当前系统暂不支持图标管理" }
        if !installedCorrectly { return "请先移入应用程序文件夹" }
        if !hasPermission { return "需要辅助功能权限" }
        if paused { return "已暂停，图标已恢复" }
        if applying { return "正在更新菜单栏" }
        if orderingFailed { return "图标位置待调整" }
        if overflowFailed { return "系统溢出区待调整" }
        return expanded ? "已展开收起的图标" : "已收起图标"
    }

    func start() {
        refreshLaunchAtLoginStatus()
        let hk = GlobalHotKey { [weak self] in self?.toggle() }
        hk.setEnabled(preferences.hotkeyEnabled)
        hotKey = hk
        lastEligibleRunning = currentEligibleRunning()

        let workspace = NSWorkspace.shared.notificationCenter
        // Menu-bar-only apps do not reliably emit didLaunchApplicationNotification.
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                let eligible = self.currentEligibleRunning()
                guard eligible != self.lastEligibleRunning else { return }
                self.lastEligibleRunning = eligible
                self.scheduleApply()
                if self.settingsWindowOpen { self.scheduleDebouncedRefresh() }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            let isWake = (name == NSWorkspace.didWakeNotification)
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.stopped else { return }
                    if isWake { self.lastPlan = nil }
                    self.scheduleApply()
                    if self.settingsWindowOpen { self.scheduleDebouncedRefresh() }
                }
            })
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            appObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.stopped, self.settingsWindowOpen else { return }
                    self.scheduleDebouncedRefresh()
                }
            })
        }
        scheduleApply()
    }

    func setSettingsWindowOpen(_ isOpen: Bool) {
        settingsWindowOpen = isOpen
        if isOpen {
            refreshLaunchAtLoginStatus()
            Task { await refresh() }
        } else {
            refreshDebounceTask?.cancel()
            refreshDebounceTask = nil
        }
        rescheduleAutoCollapse()
    }

    func placement(for id: String) -> Placement { rules[id]?.placement ?? .visible }

    func setPlacement(_ placement: Placement, for item: MenuApp) {
        guard canConfigure else { return }
        var next = rules
        if placement == .visible { next.removeValue(forKey: item.id) }
        else { next[item.id] = SavedRule(name: item.name, placement: placement) }
        do { try store.save(next); rules = next }
        catch { self.error = "配置保存失败，请重试"; return }
        if !item.running && placement == .visible {
            known.removeValue(forKey: item.id)
            rebuildItems(discovered: [])
        }
        scheduleApply()
    }

    func removeOfflineRule(for id: String) {
        var next = rules
        guard next.removeValue(forKey: id) != nil else { return }
        do { try store.save(next); rules = next }
        catch { self.error = "配置保存失败，请重试"; return }
        known.removeValue(forKey: id)
        rebuildItems(discovered: [])
    }

    func setAutoCollapse(_ delay: AutoCollapseDelay) {
        guard preferences.autoCollapse != delay else { return }
        preferences.autoCollapse = delay
        preferencesStore.save(preferences)
        rescheduleAutoCollapse()
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        guard preferences.hotkeyEnabled != enabled else { return }
        preferences.hotkeyEnabled = enabled
        preferencesStore.save(preferences)
        hotKey?.setEnabled(enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard installedCorrectly else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            self.error = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        guard canConfigure else { return }
        if paused { resume(); return }
        expanded.toggle()
        scheduleApply()
        rescheduleAutoCollapse()
    }

    func pause() {
        paused = true
        revision += 1
        mover.cancel()
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        session.restore()
        lastPlan = nil
    }

    func resume() {
        guard canConfigure else { return }
        paused = false
        error = nil
        scheduleApply()
        rescheduleAutoCollapse()
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func scheduleDebouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func rescheduleAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        guard AutoCollapsePolicy.shouldSchedule(expanded: expanded, paused: paused, delay: preferences.autoCollapse),
              let seconds = preferences.autoCollapse.seconds
        else { return }
        autoCollapseTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                guard AutoCollapsePolicy.shouldSchedule(expanded: self.expanded, paused: self.paused, delay: self.preferences.autoCollapse) else { return }
                if AutoCollapsePolicy.shouldDeferCollapse(settingsVisible: self.settingsWindowOpen, pointerInMenuBar: Self.isPointerInMenuBar()) {
                    continue
                }
                self.expanded = false
                self.scheduleApply()
                return
            }
        }
    }

    private static func isPointerInMenuBar() -> Bool {
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(loc) {
            let menuBarBottom = screen.visibleFrame.maxY
            let topEdge = screen.frame.maxY
            let threshold = max(topEdge - menuBarBottom, 32)
            if topEdge - loc.y <= threshold { return true }
        }
        return false
    }

    func discoverAllIcons() async {
        guard canConfigure, !discovering else { return }
        discovering = true
        revision += 1
        mover.cancel()
        await worker?.value
        defer {
            discovering = false
            if !stopped && !paused { scheduleApply() }
        }
        while scanning && !stopped {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !stopped else { return }
        if !paused {
            session.restore()
            lastPlan = nil
            try? await Task.sleep(for: .milliseconds(350))
            guard !stopped else { return }
        }
        await refresh()
    }

    func refresh() async {
        guard !stopped, !scanning else { return }
        hasPermission = AXIsProcessTrusted()
        supported = BFMenuBarSession.supported
        conflictingApp = NSWorkspace.shared.runningApplications.first {
            let name = $0.localizedName ?? ""
            return name.hasPrefix("Bartender") || name == "Ice" || name == "Hidden Bar" || name == "Dimble"
        }?.localizedName
        guard hasPermission, supported else {
            session.restore()
            lastPlan = nil
            rebuildItems(discovered: [])
            return
        }
        scanning = true
        defer { scanning = false }
        do {
            let discovered = try await inventory.scan(ownID: ownID)
            guard !stopped else { return }
            for item in discovered {
                known[item.id] = item
                resolvedNames[item.id] = item.name
            }
            rebuildItems(discovered: discovered)
            if !paused && !orderingFailed && !overflowFailed { error = nil }
            scheduleApply()
        } catch {
            guard !stopped else { return }
            self.error = "图标列表读取失败，已恢复图标。请刷新重试。"
            pause()
        }
    }

    private func currentEligibleRunning() -> Set<String> {
        let candidates = NSWorkspace.shared.runningApplications.map {
            (bundleID: $0.bundleIdentifier, isProhibited: $0.activationPolicy == .prohibited)
        }
        return ProcessEligibility.eligibleBundleIDs(from: candidates)
    }

    private func rebuildItems(discovered: [DiscoveredApp]) {
        let running = currentEligibleRunning()
        lastEligibleRunning = running
        items = InventoryCatalog.buildRows(
            known: known,
            discovered: discovered,
            rules: rules,
            running: running,
            nameResolver: { [weak self] id, fallback in
                if let cached = self?.resolvedNames[id] { return cached }
                let resolved = AppBundleMetadata.displayName(forBundleIdentifier: id, fallback: fallback)
                self?.resolvedNames[id] = resolved
                return resolved
            }
        )
    }

    private func scheduleApply() {
        revision += 1
        mover.cancel()
        if !stopped && canConfigure && !paused && !discovering {
            let running = currentEligibleRunning()
            let immediatePlan = VisibilityPlan(rules: rules, expanded: expanded, running: running, ownID: ownID)
            if immediatePlan.hidden.isEmpty && worker != nil {
                session.restore()
                lastPlan = immediatePlan
            }
        }
        guard !stopped, !discovering, worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            self.applying = true
            defer { self.applying = false; self.worker = nil }
            while !self.stopped {
                let version = self.revision
                guard self.canConfigure, !self.paused, !self.discovering else {
                    self.session.restore(); self.lastPlan = nil
                    break
                }
                var overflowSucceeded = true
                if !self.expanded {
                    overflowSucceeded = await self.synchronizeOverflow(expanded: false, version: version)
                }
                if self.stopped || self.paused { break }
                if self.revision != version { continue }
                // Move currently visible items before hiding them so the next reveal uses the correct side.
                var orderingSucceeded = await self.reconcileOrder(version: version)
                if self.stopped || self.paused { break }
                if self.revision != version { continue }
                let running = self.currentEligibleRunning()
                let plan = VisibilityPlan(rules: self.rules, expanded: self.expanded, running: running, ownID: self.ownID)
                let revealing = !plan.allowed.subtracting(self.lastPlan?.allowed ?? []).isEmpty
                if plan.hidden.isEmpty {
                    self.session.restore(); self.lastPlan = plan
                } else if plan != self.lastPlan {
                    let succeeded = await self.apply(plan)
                    if self.stopped || self.paused { break }
                    if succeeded { self.lastPlan = plan }
                    else if self.revision != version { continue }
                    else {
                        self.error = "显隐设置未能应用，已恢复图标。请点击“恢复管理”重试。"
                        self.pause()
                        break
                    }
                }
                if revealing {
                    try? await Task.sleep(for: .milliseconds(180))
                    if self.stopped || self.paused { break }
                    if self.revision != version { continue }
                }
                if self.expanded {
                    overflowSucceeded = await self.synchronizeOverflow(expanded: true, version: version)
                    if self.stopped || self.paused { break }
                    if self.revision != version { continue }
                }
                if revealing || self.expanded {
                    // Newly revealed items were absent from the previous accessibility layout.
                    let revealedOrderSucceeded = await self.reconcileOrder(version: version)
                    orderingSucceeded = orderingSucceeded && revealedOrderSucceeded
                }
                if self.stopped || self.paused { break }
                if self.revision == version {
                    let hadLayoutError = self.orderingFailed || self.overflowFailed
                    self.orderingFailed = !orderingSucceeded
                    self.overflowFailed = !overflowSucceeded
                    if !overflowSucceeded {
                        self.error = "系统溢出区调整未完成。请松开鼠标和修饰键后，点击“恢复管理”重试。"
                    } else if !orderingSucceeded {
                        self.error = "图标位置调整未完成。请松开鼠标和修饰键后，点击“恢复管理”重试。"
                    } else if hadLayoutError {
                        self.error = nil
                    }
                    break
                }
            }
        }
    }

    private func synchronizeOverflow(expanded: Bool, version: Int) async -> Bool {
        do {
            var controls = try await inventory.overflowControls()
            let limit = controls.count
            for _ in 0..<limit {
                guard controls.contains(where: { $0.isExpanded != expanded }) else { return true }
                try await mover.waitForIdle { !self.stopped && !self.paused && !self.discovering && self.revision == version }
                controls = try await inventory.overflowControls()
                guard !stopped, !paused, !discovering, revision == version else { return false }
                guard let control = controls.first(where: { $0.isExpanded != expanded }) else { return true }
                try await mover.click(at: CGPoint(x: control.frame.midX, y: control.frame.midY)) {
                    !self.stopped && !self.paused && !self.discovering && self.revision == version
                }
                // Re-read the identifier, since clicking an already open control would close it.
                for _ in 0..<4 {
                    try await Task.sleep(for: .milliseconds(60))
                    controls = try await inventory.overflowControls()
                    if !controls.contains(where: { $0.frame == control.frame && $0.isExpanded != expanded }) { break }
                }
                if controls.contains(where: { $0.frame == control.frame && $0.isExpanded != expanded }) {
                    throw MenuBarMoveError.rejected
                }
            }
            return controls.allSatisfy { $0.isExpanded == expanded }
        } catch {
            if !stopped && !paused && revision == version {
                NSLog("BarFold overflow failed: %@", String(describing: error))
            }
            return false
        }
    }

    private func reconcileOrder(version: Int) async -> Bool {
        do {
            var layout = try await inventory.layout(ownID: ownID)
            let limit = layout.count
            for _ in 0..<limit {
                guard !stopped, !paused, !discovering, revision == version else { return false }
                guard MenuBarOrder.nextMove(items: layout, rules: rules, ownID: ownID) != nil else {
                    return true
                }
                try await mover.waitForIdle { !self.stopped && !self.paused && !self.discovering && self.revision == version }
                layout = try await inventory.layout(ownID: ownID)
                guard !stopped, !paused, !discovering, revision == version else { return false }
                guard let move = MenuBarOrder.nextMove(items: layout, rules: rules, ownID: ownID) else { continue }
                try await mover.move(move) { !self.stopped && !self.paused && self.revision == version }
                try await Task.sleep(for: .milliseconds(180))
                layout = try await inventory.layout(ownID: ownID)
                if MenuBarOrder.nextMove(items: layout, rules: rules, ownID: ownID) == move {
                    throw MenuBarMoveError.rejected
                }
            }
            guard MenuBarOrder.nextMove(items: layout, rules: rules, ownID: ownID) == nil else {
                throw MenuBarMoveError.rejected
            }
            return true
        } catch {
            if !stopped && !paused && revision == version {
                NSLog("BarFold ordering failed: %@", String(describing: error))
            }
            return false
        }
    }

    private func apply(_ plan: VisibilityPlan) async -> Bool {
        await withCheckedContinuation { continuation in
            session.applyAllowedBundles(plan.allowed.sorted()) { error in
                if let error { NSLog("BarFold visibility: %@", error.localizedDescription) }
                continuation.resume(returning: error == nil)
            }
        }
    }

    func stop() {
        stopped = true
        mover.cancel()
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        hotKey?.unregister()
        hotKey = nil
        runningObservation?.invalidate()
        runningObservation = nil
        session.restore()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()
    }
}
