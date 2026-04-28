import Foundation

enum ResourceType: String, Codable, CaseIterable, Sendable {
    case button
    case toggle
    case feed
}

/// Output schema for `.feed` resources. A feed resource's actionScript is
/// expected to print this JSON to stdout on exit code 0.
///
/// The schema is intentionally simple: a list of items with optional
/// subtitle/detail and an `isNew` flag, plus a `newCount` summary the UI
/// uses to render a badge. `schemaVersion` lets the payload evolve without
/// breaking older clients.
struct FeedPayload: Codable, Sendable, Hashable {
    struct Item: Codable, Sendable, Hashable {
        var name: String
        var subtitle: String?
        var detail: String?
        var isNew: Bool
    }

    /// Currently understood schema version. Bump when the payload shape
    /// changes in a non-backward-compatible way.
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int = FeedPayload.currentSchemaVersion
    var title: String?
    var checkedAt: String?
    var items: [Item]
    var newCount: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion, title, checkedAt, items, newCount
    }

    init(
        schemaVersion: Int = FeedPayload.currentSchemaVersion,
        title: String? = nil,
        checkedAt: String? = nil,
        items: [Item],
        newCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.checkedAt = checkedAt
        self.items = items
        self.newCount = newCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerate missing schemaVersion → treat as 1.
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.checkedAt = try c.decodeIfPresent(String.self, forKey: .checkedAt)
        self.items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        self.newCount = try c.decodeIfPresent(Int.self, forKey: .newCount) ?? 0

        if self.schemaVersion > FeedPayload.currentSchemaVersion {
            FileHandle.standardError.write(Data(
                "BarKeeper: feed payload schemaVersion \(self.schemaVersion) is newer than supported (\(FeedPayload.currentSchemaVersion)); attempting to decode anyway.\n".utf8
            ))
        }
    }

    /// Decode a `FeedPayload` from raw script stdout.
    ///
    /// Strategy (in order):
    /// 1. Try decoding the entire stdout (fast path for well-behaved scripts).
    /// 2. Fall back to scanning for the **last** balanced top-level `{...}`
    ///    block in stdout and decoding that. This survives noisy login-shell
    ///    chatter (Homebrew nags, nvm, direnv, etc.) printed before the JSON.
    /// 3. Otherwise return `nil`.
    static func decode(from data: Data) -> FeedPayload? {
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(FeedPayload.self, from: data) {
            return payload
        }
        guard let text = String(data: data, encoding: .utf8),
              let jsonRange = lastTopLevelJSONObject(in: text),
              let jsonData = String(text[jsonRange]).data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(FeedPayload.self, from: jsonData)
    }

    /// Returns the range of the last balanced top-level `{...}` object in the
    /// string, ignoring braces that appear inside JSON string literals.
    private static func lastTopLevelJSONObject(in text: String) -> Range<String.Index>? {
        var lastRange: Range<Int>?
        var depth = 0
        var start = -1
        var inString = false
        var escape = false
        var i = 0
        for ch in text.unicodeScalars {
            defer { i += 1 }
            if escape { escape = false; continue }
            if inString {
                if ch == "\\" { escape = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = i }
                depth += 1
            case "}":
                if depth > 0 {
                    depth -= 1
                    if depth == 0, start >= 0 {
                        lastRange = start..<(i + 1)
                        start = -1
                    }
                }
            default:
                break
            }
        }
        guard let r = lastRange else { return nil }
        let scalars = text.unicodeScalars
        let lo = scalars.index(scalars.startIndex, offsetBy: r.lowerBound)
        let hi = scalars.index(scalars.startIndex, offsetBy: r.upperBound)
        return lo..<hi
    }
}

struct Resource: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var type: ResourceType

    // Button & Feed: single action script (Feed's stdout must be JSON).
    var actionScript: String?

    // Toggle: status/on/off scripts
    var statusScript: String?
    var onScript: String?
    var offScript: String?

    init(
        id: UUID = UUID(),
        name: String,
        type: ResourceType,
        actionScript: String? = nil,
        statusScript: String? = nil,
        onScript: String? = nil,
        offScript: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.actionScript = actionScript
        self.statusScript = statusScript
        self.onScript = onScript
        self.offScript = offScript
    }
}

struct AppConfiguration: Codable, Sendable {
    var resources: [Resource]
    var pollingIntervalSeconds: Int

    static let defaultConfig = AppConfiguration(
        resources: [],
        pollingIntervalSeconds: 3600
    )

    /// Example config for Azure Fabric Capacity
    static func fabricCapacityExample(
        capacityName: String = "MyDemoCapacity",
        resourceGroup: String = "rg-demos"
    ) -> Resource {
        Resource(
            name: "Fabric: \(capacityName)",
            type: .toggle,
            statusScript: """
            az fabric capacity show \
              --capacity-name "\(capacityName)" \
              --resource-group "\(resourceGroup)" \
              --query "state" -o tsv | grep -qi "Active"
            """,
            onScript: """
            az fabric capacity resume \
              --capacity-name "\(capacityName)" \
              --resource-group "\(resourceGroup)"
            """,
            offScript: """
            az fabric capacity suspend \
              --capacity-name "\(capacityName)" \
              --resource-group "\(resourceGroup)"
            """
        )
    }
}
