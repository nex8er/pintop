import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum HotKeyID {
        static let toggle: UInt32 = 1
        static let unpinAll: UInt32 = 2
    }

    private var statusItem: NSStatusItem!
    private let settings = AppSettings.shared
    private let manager = PinManager.shared
    private let settingsWindow = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = "PinTop"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        manager.onChange = { [weak self] in self?.updateStatusIcon() }
        updateStatusIcon()

        HotKeyCenter.shared.install()
        Publishers.CombineLatest3(settings.$toggleHotKey, settings.$unpinAllHotKey, settings.$recordingAction)
            .sink { [weak self] toggle, unpinAll, recording in
                self?.registerHotKeys(toggle: toggle, unpinAll: unpinAll, suspended: recording != nil)
            }
            .store(in: &cancellables)

        // objectWillChange fires before the new value is stored; hop to the next run loop pass to read it.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.manager.applyAppearance() }
            .store(in: &cancellables)

        Permissions.requestOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.unpinAll(playSound: false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    // MARK: - Hot keys

    private func registerHotKeys(toggle: HotKey?, unpinAll: HotKey?, suspended: Bool) {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        guard !suspended else { return }

        var unavailable: Set<HotKeyAction> = []
        if let toggle, !center.register(toggle, id: HotKeyID.toggle, handler: { [weak self] in
            self?.manager.toggleActiveWindow()
        }) {
            unavailable.insert(.toggle)
        }
        if let unpinAll, !center.register(unpinAll, id: HotKeyID.unpinAll, handler: { [weak self] in
            self?.manager.unpinAll()
        }) {
            unavailable.insert(.unpinAll)
        }
        if settings.unavailableActions != unavailable {
            settings.unavailableActions = unavailable
        }
    }

    // MARK: - Status item

    private func updateStatusIcon() {
        let count = manager.pinned.count
        statusItem.button?.image = count > 0 ? Icons.pinned : Icons.idle
        statusItem.button?.toolTip = count > 0 ? "PinTop — \(count) pinned" : "PinTop"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let target = WindowTarget.frontmost()
        let targetIsPinned = target.map { manager.isPinned($0.windowID) } ?? false
        let toggleItem = NSMenuItem(
            title: targetIsPinned ? "Unpin Active Window" : "Pin Active Window",
            action: #selector(toggleActiveWindow), keyEquivalent: ""
        )
        toggleItem.target = self
        // Without permissions the item stays enabled so that clicking it explains what is missing.
        toggleItem.isEnabled = target != nil || !Permissions.hasAccessibility
        if let target {
            toggleItem.toolTip = target.appName
        }
        applyShortcut(settings.toggleHotKey, to: toggleItem)
        menu.addItem(toggleItem)

        let unpinAllItem = NSMenuItem(title: "Unpin All Windows", action: #selector(unpinAll), keyEquivalent: "")
        unpinAllItem.target = self
        unpinAllItem.isEnabled = manager.hasPinnedWindows
        applyShortcut(settings.unpinAllHotKey, to: unpinAllItem)
        menu.addItem(unpinAllItem)

        if manager.hasPinnedWindows {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Pinned Windows"))
            for window in manager.pinned {
                let item = NSMenuItem(title: window.displayName, action: #selector(unpinWindow(_:)), keyEquivalent: "")
                item.target = self
                item.state = .on
                item.toolTip = "Click to unpin"
                item.representedObject = NSNumber(value: window.windowID)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit PinTop", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func applyShortcut(_ hotKey: HotKey?, to item: NSMenuItem) {
        guard let hotKey, let key = hotKey.menuKeyEquivalent else { return }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = hotKey.modifierFlags
    }

    // MARK: - Actions

    @objc private func toggleActiveWindow() {
        manager.toggleActiveWindow()
    }

    @objc private func unpinAll() {
        manager.unpinAll()
    }

    @objc private func unpinWindow(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        manager.unpin(windowID: number.uint32Value)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
