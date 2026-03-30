import Foundation

enum ResourceType: String, Codable, CaseIterable, Sendable {
    case button
    case toggle
}

struct Resource: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var type: ResourceType

    // Button: single action script
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
              --query "properties.state" -o tsv | grep -qi "Active"
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
