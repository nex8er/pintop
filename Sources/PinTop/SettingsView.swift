import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasScreenRecording = Permissions.hasScreenRecording

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                Toggle("Play sounds when pinning and unpinning", isOn: $settings.playSounds)
            }

            Section {
                LabeledContent("Toggle always on top") {
                    ShortcutRecorder(action: .toggle)
                }
                LabeledContent("Unpin all windows") {
                    ShortcutRecorder(action: .unpinAll)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("The toggle shortcut pins or unpins the active window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PermissionRow(title: "Accessibility", detail: "Find, track and focus windows",
                              granted: hasAccessibility, url: Permissions.accessibilitySettingsURL)
                PermissionRow(title: "Screen Recording", detail: "Show pinned windows above others",
                              granted: hasScreenRecording, url: Permissions.screenRecordingSettingsURL)
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(permissionTimer) { _ in
            hasAccessibility = Permissions.hasAccessibility
            hasScreenRecording = Permissions.hasScreenRecording
            launchAtLogin = LoginItem.isEnabled
        }
    }
}

struct BorderSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                BorderPreview(style: settings.borderStyle)
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())
            }

            Section("Shape") {
                LabeledContent("Width") {
                    valueSlider($settings.borderWidth, in: AppSettings.borderWidthRange, step: 1,
                                label: "\(Int(settings.borderWidth)) pt")
                }
                LabeledContent("Opacity") {
                    valueSlider($settings.borderOpacity, in: 0.1...1, step: 0.05,
                                label: "\(Int((settings.borderOpacity * 100).rounded()))%")
                }
                LabeledContent("Glow") {
                    valueSlider($settings.glowIntensity, in: 0...1, step: 0.05,
                                label: settings.glowIntensity > 0 ? "\(Int((settings.glowIntensity * 100).rounded()))%" : "Off")
                }
            }

            Section("Color") {
                ColorPicker("Color", selection: colorBinding(\.borderColor), supportsOpacity: false)
                Toggle("Gradient", isOn: $settings.gradientEnabled)
                ColorPicker("Gradient color", selection: colorBinding(\.gradientColor), supportsOpacity: false)
                    .disabled(!settings.gradientEnabled)
                Toggle("Animate gradient", isOn: $settings.animateGradient)
                    .disabled(!settings.gradientEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func valueSlider(_ value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: String) -> some View {
        HStack {
            Slider(value: value, in: range, step: step)
                .frame(width: 180)
            Text(label)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, NSColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = NSColor($0) }
        )
    }
}

/// A mock window showing the current border style.
private struct BorderPreview: NSViewRepresentable {
    let style: BorderStyle

    func makeNSView(context: Context) -> BorderPreviewView { BorderPreviewView() }

    func updateNSView(_ view: BorderPreviewView, context: Context) {
        view.style = style
    }
}

private final class BorderPreviewView: NSView {
    private let windowLayer = CALayer()
    private let titleBarLayer = CALayer()
    private let lightLayers = (0..<3).map { _ in CALayer() }
    private let borderLayer = BorderLayer()

    var style: BorderStyle? {
        didSet { if style != oldValue { needsLayout = true } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        windowLayer.masksToBounds = true
        windowLayer.addSublayer(titleBarLayer)
        let lightColors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (light, color) in zip(lightLayers, lightColors) {
            light.backgroundColor = color.cgColor
            light.cornerRadius = 6
            windowLayer.addSublayer(light)
        }
        layer?.addSublayer(windowLayer)
        layer?.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            windowLayer.backgroundColor = NSColor.textBackgroundColor.cgColor
            titleBarLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        guard let style else { return }
        let radius = BorderStyle.defaultCornerRadius
        let windowRect = bounds.insetBy(dx: 90, dy: 32)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        windowLayer.frame = windowRect
        windowLayer.cornerRadius = radius
        titleBarLayer.frame = CGRect(x: 0, y: windowRect.height - 28, width: windowRect.width, height: 28)
        for (index, light) in lightLayers.enumerated() {
            light.frame = CGRect(x: 12 + CGFloat(index) * 20, y: windowRect.height - 20, width: 12, height: 12)
        }
        borderLayer.frame = bounds
        borderLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        borderLayer.update(windowRect: windowRect, cornerRadius: radius, style: style)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let url: URL

    var body: some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings…") { Permissions.open(url) }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// System Settings–style window with toolbar tabs; the window height follows the selected tab.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(Self.tab(GeneralSettingsView(), label: "General", symbol: "gearshape"))
            tabs.addTabViewItem(Self.tab(BorderSettingsView(), label: "Border Appearance", symbol: "paintbrush"))

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private static func tab<Content: View>(_ view: Content, label: String, symbol: String) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        hosting.title = label // Shown as the window title while the tab is selected.
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutRecordingController.shared.stop()
    }

    func windowDidResignKey(_ notification: Notification) {
        ShortcutRecordingController.shared.stop()
    }
}
