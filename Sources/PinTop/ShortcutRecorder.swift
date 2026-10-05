import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Captures the next key combination typed in the Settings window.
@MainActor
final class ShortcutRecordingController {
    static let shared = ShortcutRecordingController()

    private var monitor: Any?
    private let settings = AppSettings.shared

    func start(_ action: HotKeyAction) {
        stop()
        settings.recordingAction = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if settings.recordingAction != nil {
            settings.recordingAction = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard let action = settings.recordingAction else { return stop() }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)

        if flags.isEmpty, keyCode == kVK_Escape {
            return stop()
        }
        if flags.isEmpty, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            settings.setHotKey(nil, for: action)
            return stop()
        }

        let hotKey = HotKey(event: event)
        let usedElsewhere = HotKeyAction.allCases.contains { $0 != action && settings.hotKey(for: $0) == hotKey }
        guard hotKey.isValid, !usedElsewhere else {
            NSSound.beep()
            return
        }
        settings.setHotKey(hotKey, for: action)
        stop()
    }
}

struct ShortcutRecorder: View {
    let action: HotKeyAction
    @ObservedObject private var settings = AppSettings.shared

    private var isRecording: Bool { settings.recordingAction == action }
    private var hotKey: HotKey? { settings.hotKey(for: action) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    if isRecording {
                        ShortcutRecordingController.shared.stop()
                    } else {
                        ShortcutRecordingController.shared.start(action)
                    }
                } label: {
                    Text(isRecording ? "Type shortcut…" : (hotKey?.displayString ?? "Record Shortcut"))
                        .monospacedDigit()
                        .foregroundStyle(isRecording || hotKey == nil ? .secondary : .primary)
                        .frame(minWidth: 110)
                }
                .help(isRecording ? "Press a key combination. Esc cancels, ⌫ clears." : "Click to record a new shortcut")

                Button {
                    ShortcutRecordingController.shared.stop()
                    settings.setHotKey(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .opacity(hotKey == nil || isRecording ? 0 : 1)
                .disabled(hotKey == nil || isRecording)
            }
            if settings.unavailableActions.contains(action), !isRecording {
                Text("Already in use by another app")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
