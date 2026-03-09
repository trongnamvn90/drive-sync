import Foundation

/// Reads/writes ~/.config/drivesync/config.toml
/// Simple flat TOML — no nested tables, no arrays.
@MainActor
final class ConfigManager {
    static let shared = ConfigManager()

    private let fileURL: URL
    private var sections: [String: [(key: String, value: String)]] = [:]

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/drivesync")
        self.fileURL = dir.appendingPathComponent("config.toml")
        load()
    }

    // MARK: - Read

    func string(section: String, key: String) -> String? {
        sections[section]?.first(where: { $0.key == key })?.value
    }

    func int(section: String, key: String) -> Int? {
        string(section: section, key: key).flatMap(Int.init)
    }

    func bool(section: String, key: String) -> Bool? {
        guard let val = string(section: section, key: key) else { return nil }
        return val == "true"
    }

    // MARK: - Write

    func set(section: String, key: String, value: String) {
        if sections[section] == nil {
            sections[section] = []
        }
        if let idx = sections[section]!.firstIndex(where: { $0.key == key }) {
            sections[section]![idx] = (key, value)
        } else {
            sections[section]!.append((key, value))
        }
        save()
    }

    func set(section: String, key: String, value: Int) {
        set(section: section, key: key, value: String(value))
    }

    func set(section: String, key: String, value: Bool) {
        set(section: section, key: key, value: value ? "true" : "false")
    }

    // MARK: - Load / Save

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        var currentSection = ""
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
                currentSection = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                if sections[currentSection] == nil {
                    sections[currentSection] = []
                }
                continue
            }

            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            var val = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

            // Strip quotes
            if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 {
                val = String(val.dropFirst().dropLast())
            }

            if sections[currentSection] == nil {
                sections[currentSection] = []
            }
            sections[currentSection]!.append((key, val))
        }
    }

    private func save() {
        var lines: [String] = []
        let sectionOrder = ["google", "sync", "app"]

        // Write known sections in order, then any extras
        let allSections = sectionOrder + sections.keys.filter { !sectionOrder.contains($0) }.sorted()
        var written = Set<String>()

        for section in allSections {
            guard !written.contains(section), let pairs = sections[section], !pairs.isEmpty else { continue }
            written.insert(section)

            if !lines.isEmpty { lines.append("") }
            lines.append("[\(section)]")
            for pair in pairs {
                let needsQuote = !isNumeric(pair.value) && pair.value != "true" && pair.value != "false"
                if needsQuote {
                    lines.append("\(pair.key) = \"\(pair.value)\"")
                } else {
                    lines.append("\(pair.key) = \(pair.value)")
                }
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func isNumeric(_ s: String) -> Bool {
        Int(s) != nil
    }
}
