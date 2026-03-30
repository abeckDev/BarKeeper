import Foundation

struct ConfigStore: Sendable {
    private static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BarKeeper", isDirectory: true)
    }()

    private static let configFileURL: URL = {
        appSupportDir.appendingPathComponent("config.json")
    }()

    /// Loads the configuration from disk, or returns the default if none exists.
    static func load() -> AppConfiguration {
        ensureDirectoryExists()
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return .defaultConfig
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            return try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            print("⚠️ Failed to load config: \(error). Using defaults.")
            return .defaultConfig
        }
    }

    /// Saves the configuration to disk.
    static func save(_ config: AppConfiguration) {
        ensureDirectoryExists()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            print("⚠️ Failed to save config: \(error)")
        }
    }

    /// Exports configuration as a JSON Data blob (for sharing / backup).
    static func exportJSON(from config: AppConfiguration) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    /// Imports configuration from JSON Data.
    static func importJSON(from data: Data) -> AppConfiguration? {
        try? JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    private static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: appSupportDir,
            withIntermediateDirectories: true
        )
    }
}
