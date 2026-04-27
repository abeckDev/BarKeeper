import Foundation

/// Runtime state for a resource, separate from the persisted configuration.
@Observable
final class ResourceState: Identifiable, @unchecked Sendable {
    let resource: Resource
    var isOn: Bool = false
    var isLoading: Bool = false
    var lastError: String?
    var lastChecked: Date?

    /// Most recent report payload for `.report` resources.
    var lastReport: ReportPayload?

    var id: UUID { resource.id }
    var name: String { resource.name }
    var type: ResourceType { resource.type }

    init(resource: Resource) {
        self.resource = resource
    }
}
