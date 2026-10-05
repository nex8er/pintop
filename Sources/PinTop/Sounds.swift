import AppKit

/// Pin/unpin feedback sounds (Kenney "Interface Sounds", CC0 – see Resources/Sounds).
@MainActor
enum Sounds {
    private static let pin = load("pin")
    private static let unpin = load("unpin")

    static func playPin() { play(pin) }
    static func playUnpin() { play(unpin) }

    private static func play(_ sound: NSSound?) {
        guard AppSettings.shared.playSounds, let sound else { return }
        sound.stop()
        sound.play()
    }

    private static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Sounds") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }
}
