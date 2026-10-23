import AppKit

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case none, shift, control, option, command

    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .none: []
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }

    var symbol: String {
        switch self {
        case .none: ""
        case .shift: "⇧"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .shift: "Shift"
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        }
    }

    var label: String { self == .none ? title : "\(symbol) \(title)" }

    func isHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        self != .none && flags.contains(self.flags)
    }
}

enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    /// Zones show only while the activation key is held.
    case holdKey
    /// Zones always show while dragging; holding the activation key suppresses them.
    case always

    var id: String { rawValue }
}

struct Settings: Codable, Equatable {
    var enabled = true
    var activationKey: ModifierKey = .shift
    var activationMode: ActivationMode = .holdKey
    var rightClickToggles = true
    var spanKey: ModifierKey = .control
    var spanByProximity = false
    var restoreSizeOnUnsnap = true
    var showOnAllDisplays = false
    var zoneSpacing: Double = 8
    var showZoneNumbers = true
    var flashOnLayoutChange = true
    var zoneColor = "#1E2230"
    var highlightColor = "#0A84FF"
    var borderColor = "#FFFFFF"
    var overlayOpacity: Double = 0.55
    var shortcutsEnabled = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = c.value(.enabled, d.enabled)
        activationKey = c.value(.activationKey, d.activationKey)
        activationMode = c.value(.activationMode, d.activationMode)
        rightClickToggles = c.value(.rightClickToggles, d.rightClickToggles)
        spanKey = c.value(.spanKey, d.spanKey)
        spanByProximity = c.value(.spanByProximity, d.spanByProximity)
        restoreSizeOnUnsnap = c.value(.restoreSizeOnUnsnap, d.restoreSizeOnUnsnap)
        showOnAllDisplays = c.value(.showOnAllDisplays, d.showOnAllDisplays)
        zoneSpacing = c.value(.zoneSpacing, d.zoneSpacing)
        showZoneNumbers = c.value(.showZoneNumbers, d.showZoneNumbers)
        flashOnLayoutChange = c.value(.flashOnLayoutChange, d.flashOnLayoutChange)
        zoneColor = c.value(.zoneColor, d.zoneColor)
        highlightColor = c.value(.highlightColor, d.highlightColor)
        borderColor = c.value(.borderColor, d.borderColor)
        overlayOpacity = c.value(.overlayOpacity, d.overlayOpacity)
        shortcutsEnabled = c.value(.shortcutsEnabled, d.shortcutsEnabled)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back on missing or malformed data so old/foreign configs never fail to load.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}
