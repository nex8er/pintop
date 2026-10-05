import AppKit

@MainActor
final class PinManager {
    static let shared = PinManager()

    private(set) var pinned: [PinnedWindow] = []
    /// Called whenever the set of pinned windows changes.
    var onChange: (() -> Void)?

    private var pending: Set<CGWindowID> = []
    private var timer: Timer?
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(updateFocus: true) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(updateFocus: true, relayout: true) }
        })
    }

    var hasPinnedWindows: Bool { !pinned.isEmpty }

    func isPinned(_ windowID: CGWindowID) -> Bool {
        pinned.contains { $0.windowID == windowID }
    }

    /// Pins the active window, or unpins it when it is already pinned.
    func toggleActiveWindow() {
        guard Permissions.ensureGranted() else { return }
        guard let target = WindowTarget.frontmost() else {
            NSSound.beep()
            return
        }
        if let existing = pinned.first(where: { $0.windowID == target.windowID }) {
            unpin(existing)
            Sounds.playUnpin()
        } else {
            pin(target)
            Sounds.playPin()
        }
    }

    func pin(_ target: WindowTarget) {
        guard !isPinned(target.windowID), !pending.contains(target.windowID) else { return }
        pending.insert(target.windowID)

        let window = PinnedWindow(target: target)
        window.onClose = { [weak self] window in self?.unpin(window) }
        window.onNeedsRefresh = { [weak self] focusChanged in self?.refresh(updateFocus: focusChanged) }
        pinned.append(window)
        startTimer()
        onChange?()

        Task { @MainActor in
            defer { pending.remove(target.windowID) }
            do {
                try await window.start()
            } catch {
                unpin(window)
                showPinError(error)
            }
        }
    }

    func unpin(_ window: PinnedWindow) {
        window.stop()
        guard let index = pinned.firstIndex(where: { $0 === window }) else { return }
        pinned.remove(at: index)
        if pinned.isEmpty { stopTimer() }
        onChange?()
    }

    func unpin(windowID: CGWindowID) {
        if let window = pinned.first(where: { $0.windowID == windowID }) {
            unpin(window)
            Sounds.playUnpin()
        }
    }

    func unpinAll(playSound: Bool = true) {
        guard !pinned.isEmpty else { return }
        pinned.forEach { $0.stop() }
        pinned.removeAll()
        stopTimer()
        onChange?()
        if playSound { Sounds.playUnpin() }
    }

    func applyAppearance() {
        pinned.forEach { $0.applyAppearance() }
    }

    func refresh(updateFocus: Bool, relayout: Bool = false) {
        guard !pinned.isEmpty else { return }
        let infos = WindowServer.info(for: pinned.map(\.windowID))
        for window in pinned {
            if updateFocus { window.updateFocusState() }
            if relayout { window.applyAppearance() }
            window.update(with: infos[window.windowID])
        }
    }

    // MARK: - Polling

    /// AX notifications cover most changes; the timer is a safety net and keeps the
    /// border glued to the window while it is being dragged (mouse button held).
    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        ticks &+= 1
        if ticks % 15 == 0 {
            refresh(updateFocus: true)
        } else if NSEvent.pressedMouseButtons != 0 {
            refresh(updateFocus: false)
        }
    }

    private func showPinError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Could not pin the window"
        if !Permissions.hasScreenRecording {
            alert.informativeText = "Screen Recording access is required. Enable PinTop in System Settings › Privacy & Security › Screen & System Audio Recording, then restart PinTop."
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }
}
