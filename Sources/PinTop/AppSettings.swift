import AppKit
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let toggleHotKey = "toggleHotKey"
        static let unpinAllHotKey = "unpinAllHotKey"
        static let borderWidth = "borderWidth"
        static let borderOpacity = "borderOpacity"
        static let borderColor = "borderColor"
        static let gradientEnabled = "gradientEnabled"
        static let gradientColor = "gradientColor"
        static let glowIntensity = "glowIntensity"
        static let animateGradient = "animateGradient"
        static let playSounds = "playSounds"
    }

    /// Wrapper so that a deliberately cleared shortcut (nil) can be told apart from "never set".
    private struct StoredHotKey: Codable {
        var hotKey: HotKey?
    }

    static let borderWidthRange: ClosedRange<Double> = 1...20

    private let defaults = UserDefaults.standard

    @Published var toggleHotKey: HotKey? {
        didSet { storeHotKey(toggleHotKey, key: Keys.toggleHotKey) }
    }
    @Published var unpinAllHotKey: HotKey? {
        didSet { storeHotKey(unpinAllHotKey, key: Keys.unpinAllHotKey) }
    }
    @Published var borderWidth: Double {
        didSet { defaults.set(borderWidth, forKey: Keys.borderWidth) }
    }
    @Published var borderOpacity: Double {
        didSet { defaults.set(borderOpacity, forKey: Keys.borderOpacity) }
    }
    @Published var borderColor: NSColor {
        didSet { storeColor(borderColor, key: Keys.borderColor) }
    }
    @Published var gradientEnabled: Bool {
        didSet { defaults.set(gradientEnabled, forKey: Keys.gradientEnabled) }
    }
    @Published var gradientColor: NSColor {
        didSet { storeColor(gradientColor, key: Keys.gradientColor) }
    }
    @Published var glowIntensity: Double {
        didSet { defaults.set(glowIntensity, forKey: Keys.glowIntensity) }
    }
    @Published var animateGradient: Bool {
        didSet { defaults.set(animateGradient, forKey: Keys.animateGradient) }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }

    /// The shortcut currently being recorded in Settings; global hot keys are suspended meanwhile.
    @Published var recordingAction: HotKeyAction?
    /// Shortcuts that failed to register (already used by another app).
    @Published var unavailableActions: Set<HotKeyAction> = []

    private init() {
        toggleHotKey = Self.loadHotKey(Keys.toggleHotKey, from: defaults) ?? .some(.defaultToggle)
        unpinAllHotKey = Self.loadHotKey(Keys.unpinAllHotKey, from: defaults) ?? .some(.defaultUnpinAll)
        borderWidth = defaults.object(forKey: Keys.borderWidth) as? Double ?? 4
        borderOpacity = defaults.object(forKey: Keys.borderOpacity) as? Double ?? 0.85
        borderColor = Self.loadColor(Keys.borderColor, from: defaults)
            ?? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
        gradientEnabled = defaults.object(forKey: Keys.gradientEnabled) as? Bool ?? true
        gradientColor = Self.loadColor(Keys.gradientColor, from: defaults)
            ?? NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1.0)
        glowIntensity = defaults.object(forKey: Keys.glowIntensity) as? Double ?? 0.5
        animateGradient = defaults.object(forKey: Keys.animateGradient) as? Bool ?? false
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
    }

    var borderStyle: BorderStyle {
        BorderStyle(
            width: CGFloat(borderWidth),
            opacity: CGFloat(borderOpacity),
            color: borderColor,
            gradientColor: gradientEnabled ? gradientColor : nil,
            glow: CGFloat(glowIntensity),
            animated: gradientEnabled && animateGradient
        )
    }

    func hotKey(for action: HotKeyAction) -> HotKey? {
        switch action {
        case .toggle: toggleHotKey
        case .unpinAll: unpinAllHotKey
        }
    }

    func setHotKey(_ hotKey: HotKey?, for action: HotKeyAction) {
        switch action {
        case .toggle: toggleHotKey = hotKey
        case .unpinAll: unpinAllHotKey = hotKey
        }
    }

    private func storeHotKey(_ hotKey: HotKey?, key: String) {
        defaults.set(try? JSONEncoder().encode(StoredHotKey(hotKey: hotKey)), forKey: key)
    }

    private func storeColor(_ color: NSColor, key: String) {
        defaults.set(try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true), forKey: key)
    }

    /// Returns nil when nothing is stored, `.some(nil)` when the shortcut was cleared.
    private static func loadHotKey(_ key: String, from defaults: UserDefaults) -> HotKey?? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredHotKey.self, from: data) else { return nil }
        return .some(stored.hotKey)
    }

    private static func loadColor(_ key: String, from defaults: UserDefaults) -> NSColor? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
}
