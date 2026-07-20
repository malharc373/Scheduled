import Foundation

/// A single recurring daily-routine entry (e.g. "meal prep" at 07:00).
struct RoutineItem: Codable {
    var title: String
    /// Local time of day "HH:mm", or nil for an anytime/untimed habit.
    var time: String?
    var notes: String?
}

/// The user's personal daily routine — habits that aren't necessarily on the
/// calendar (gym, meal prep, journaling…). Merged into the daily checklist.
struct Routine: Codable {
    var items: [RoutineItem]
    static let empty = Routine(items: [])
}

/// Persists the routine template as JSON. On macOS this lives at
/// ~/.config/scheduled/routine.json (convenient for the CLI); on iOS it lives in
/// the app's sandboxed Application Support directory.
enum RoutineStore {
    static var configDir: URL {
#if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("scheduled", isDirectory: true)
#else
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("scheduled", isDirectory: true)
#endif
    }

    static var fileURL: URL {
        configDir.appendingPathComponent("routine.json")
    }

    static func load() -> Routine {
        guard let data = try? Data(contentsOf: fileURL),
              let routine = try? JSONDecoder().decode(Routine.self, from: data) else {
            return .empty
        }
        return routine
    }

    @discardableResult
    static func save(_ routine: Routine) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(routine)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Human-readable one-line-per-item description.
    static func describe(_ routine: Routine) -> String {
        guard !routine.items.isEmpty else { return "(routine is empty)" }
        return routine.items.map { item in
            if let t = item.time { return "  • \(t)  \(item.title)" }
            return "  •  —    \(item.title)"
        }.joined(separator: "\n")
    }
}
