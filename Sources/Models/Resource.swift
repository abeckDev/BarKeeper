import Foundation

enum ResourceType: String, Codable, CaseIterable, Sendable {
    case button
    case toggle
    case report
}

/// Output schema produced by the embedded `foundry-check` CLI (and other
/// future report-style tools). A report resource's actionScript is expected
/// to print this JSON to stdout on exit code 0.
struct ReportPayload: Codable, Sendable, Hashable {
    struct Item: Codable, Sendable, Hashable {
        var name: String
        var subtitle: String?
        var detail: String?
        var isNew: Bool
    }

    var title: String?
    var checkedAt: String?
    var items: [Item]
    var newCount: Int

    /// Decode a generic ReportPayload from the foundry-check JSON shape, or
    /// fall back to a permissive shape for user-defined report scripts.
    static func decode(from data: Data) -> ReportPayload? {
        if let foundry = try? JSONDecoder().decode(FoundryCheckReport.self, from: data) {
            return foundry.toPayload()
        }
        return try? JSONDecoder().decode(ReportPayload.self, from: data)
    }
}

/// Internal mirror of foundry-check output for decoding.
private struct FoundryCheckReport: Codable {
    struct Model: Codable {
        var name: String
        var releaseDate: String
        var availableIn: [String]
        var isNew: Bool
    }
    var deployment: String?
    var checkedAt: String
    var regions: [String]
    var models: [Model]
    var newSinceLastCheck: [String]

    func toPayload() -> ReportPayload {
        let items = models.map { m in
            ReportPayload.Item(
                name: m.name,
                subtitle: m.releaseDate.isEmpty ? nil : m.releaseDate,
                detail: m.availableIn.joined(separator: ", "),
                isNew: m.isNew
            )
        }
        let title = "\(deployment ?? "Foundry") · \(regions.joined(separator: ", "))"
        return ReportPayload(
            title: title,
            checkedAt: checkedAt,
            items: items,
            newCount: newSinceLastCheck.count
        )
    }
}

struct Resource: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var type: ResourceType

    // Button & Report: single action script (Report's stdout must be JSON).
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

    /// Example: list Foundry models available in EU Data Zone Standard regions.
    /// Uses the embedded `foundry-check` helper resolved at runtime via
    /// `$FOUNDRY_CHECK` (substituted by ResourceManager).
    static func foundryEUDataZoneExample() -> Resource {
        let regions = [
            "swedencentral", "westeurope", "germanywestcentral",
            "francecentral", "polandcentral", "italynorth",
            "spaincentral", "switzerlandnorth", "norwayeast"
        ].joined(separator: ",")

        let script = """
        "$FOUNDRY_CHECK" \
          --deployment data-zone-standard \
          --regions \(regions) \
          --cache "$HOME/Library/Application Support/BarKeeper/foundry-cache.json" \
          --format json
        """
        return Resource(
            name: "Foundry Models · EU DZ Standard",
            type: .report,
            actionScript: script
        )
    }
}
