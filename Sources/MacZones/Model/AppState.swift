import AppKit
import Combine

struct Config: Codable {
    var settings = Settings()
    var layouts = DefaultLayouts.make()
    /// Display UUID → layout id.
    var assignments: [String: UUID] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = c.value(.settings, Settings())
        layouts = c.value(.layouts, DefaultLayouts.make())
        assignments = c.value(.assignments, [:])
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case layouts, behavior, appearance, shortcuts, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layouts: "Layouts"
        case .behavior: "Behavior"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .layouts: "rectangle.split.3x1"
        case .behavior: "hand.draw"
        case .appearance: "paintpalette"
        case .shortcuts: "command"
        case .general: "gearshape"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: Settings
    @Published var layouts: [ZoneLayout]
    @Published var assignments: [String: UUID]
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var pane: Pane = .layouts

    /// Screen ids that should briefly show their zones.
    let flashRequests = PassthroughSubject<String, Never>()
    let isFirstLaunch: Bool

    private var bag = Set<AnyCancellable>()

    static let configURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacZones", isDirectory: true).appendingPathComponent("config.json")
    }()

    private init() {
        let data = try? Data(contentsOf: Self.configURL)
        isFirstLaunch = data == nil
        let config = data.flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        settings = config.settings
        layouts = config.layouts.isEmpty ? DefaultLayouts.make() : config.layouts
        assignments = config.assignments

        Publishers.CombineLatest3($settings, $layouts, $assignments)
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &bag)
    }

    func save() {
        var config = Config()
        config.settings = settings
        config.layouts = layouts
        config.assignments = assignments
        do {
            try FileManager.default.createDirectory(at: Self.configURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: Self.configURL, options: .atomic)
        } catch {
            NSLog("MacZones: failed to save config: \(error)")
        }
    }

    // MARK: - Layouts

    func layout(for screen: NSScreen) -> ZoneLayout? {
        if let id = assignments[screen.stableID], let layout = layouts.first(where: { $0.id == id }) {
            return layout
        }
        return layouts.first
    }

    /// Zone rects for a screen in Cocoa global coordinates.
    func zoneRects(for screen: NSScreen) -> [CGRect] {
        guard let layout = layout(for: screen) else { return [] }
        return ZoneGeometry.rects(for: layout.zones, in: screen.visibleFrame, spacing: settings.zoneSpacing)
    }

    func assign(_ layoutID: UUID, to screen: NSScreen) {
        assignments[screen.stableID] = layoutID
        if settings.flashOnLayoutChange { flash(screen) }
    }

    func flash(_ screen: NSScreen) {
        flashRequests.send(screen.stableID)
    }

    func upsert(_ layout: ZoneLayout) {
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[i] = layout
        } else {
            layouts.append(layout)
        }
    }

    func duplicate(_ layout: ZoneLayout) {
        var copy = layout
        copy.id = UUID()
        copy.name = "\(layout.name) Copy"
        copy.zones = layout.zones.map { Zone($0.rect) }
        let index = (layouts.firstIndex(where: { $0.id == layout.id }) ?? layouts.count - 1) + 1
        layouts.insert(copy, at: index)
    }

    func delete(_ layout: ZoneLayout) {
        guard layouts.count > 1 else { return }
        layouts.removeAll { $0.id == layout.id }
        assignments = assignments.filter { $0.value != layout.id }
    }

    func move(_ layout: ZoneLayout, by offset: Int) {
        guard let i = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        let j = i + offset
        guard layouts.indices.contains(j) else { return }
        layouts.swapAt(i, j)
    }

    func resetLayouts() {
        layouts = DefaultLayouts.make()
        assignments = [:]
    }
}
