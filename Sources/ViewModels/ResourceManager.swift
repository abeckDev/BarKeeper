import Foundation
import SwiftUI

@Observable
@MainActor
final class ResourceManager {
    private(set) var resources: [ResourceState] = []
    var pollingIntervalSeconds: Int = 3600
    var enableNotifications: Bool = true

    private let shell = ShellExecutor()
    private let notificationService = NotificationService()
    private var pollingTimer: Timer?

    init() {
        loadConfig()
        startPolling()
        Task { await notificationService.requestAuthorization() }
    }

    // MARK: - Configuration

    func loadConfig() {
        let config = ConfigStore.load()
        pollingIntervalSeconds = config.pollingIntervalSeconds
        enableNotifications = config.enableNotifications
        resources = config.resources.map { ResourceState(resource: $0) }
        Task { await refreshAllStatuses() }
    }

    func saveConfig() {
        let config = AppConfiguration(
            resources: resources.map(\.resource),
            pollingIntervalSeconds: pollingIntervalSeconds,
            enableNotifications: enableNotifications
        )
        ConfigStore.save(config)
    }

    func requestNotificationPermission() async {
        await notificationService.requestAuthorization()
    }

    func addResource(_ resource: Resource) {
        resources.append(ResourceState(resource: resource))
        saveConfig()
        if resource.type == .toggle {
            Task { await refreshStatus(for: resource.id) }
        }
    }

    func updateResource(_ resource: Resource) {
        guard let index = resources.firstIndex(where: { $0.id == resource.id }) else { return }
        resources[index].resource = resource
        saveConfig()
        if resource.type == .toggle {
            Task { await refreshStatus(for: resource.id) }
        }
    }

    func deleteResource(id: UUID) {
        resources.removeAll { $0.id == id }
        saveConfig()
    }

    func moveResources(from source: IndexSet, to destination: Int) {
        resources.move(fromOffsets: source, toOffset: destination)
        saveConfig()
    }

    // MARK: - Import / Export

    func exportConfig() -> Data? {
        let config = AppConfiguration(
            resources: resources.map(\.resource),
            pollingIntervalSeconds: pollingIntervalSeconds,
            enableNotifications: enableNotifications
        )
        return ConfigStore.exportJSON(from: config)
    }

    func importConfig(from data: Data) -> Bool {
        guard let config = ConfigStore.importJSON(from: data) else { return false }
        pollingIntervalSeconds = config.pollingIntervalSeconds
        enableNotifications = config.enableNotifications
        resources = config.resources.map { ResourceState(resource: $0) }
        saveConfig()
        restartPolling()
        Task { await refreshAllStatuses() }
        return true
    }

    // MARK: - Script Execution

    func toggle(_ resourceId: UUID) {
        guard let state = resources.first(where: { $0.id == resourceId }),
              state.type == .toggle else { return }

        Task {
            state.isLoading = true
            state.lastError = nil

            let wasOn = state.isOn
            let script = state.isOn ? state.resource.offScript : state.resource.onScript
            guard let script, !script.isEmpty else {
                let errorMessage = "No \(state.isOn ? "off" : "on") script configured"
                state.lastError = errorMessage
                state.isLoading = false
                sendNotification(
                    title: state.name,
                    message: errorMessage,
                    type: .error
                )
                return
            }

            do {
                let result = try await shell.run(script)
                if result.succeeded {
                    // After toggling, refresh the actual status
                    await refreshStatus(for: resourceId)
                    sendNotification(
                        title: state.name,
                        message: wasOn ? "Script stopped successfully." : "Script started successfully.",
                        type: .success
                    )
                } else {
                    let errorMessage = result.stderr.isEmpty ? "Script failed (exit code \(result.exitCode))" : result.stderr
                    state.lastError = errorMessage
                    state.isLoading = false
                    sendNotification(title: state.name, message: errorMessage, type: .error)
                }
            } catch {
                state.lastError = error.localizedDescription
                state.isLoading = false
                sendNotification(title: state.name, message: error.localizedDescription, type: .error)
            }
        }
    }

    func runAction(_ resourceId: UUID) {
        guard let state = resources.first(where: { $0.id == resourceId }),
              state.type == .button else { return }

        Task {
            state.isLoading = true
            state.lastError = nil

            guard let script = state.resource.actionScript, !script.isEmpty else {
                let errorMessage = "No action script configured"
                state.lastError = errorMessage
                state.isLoading = false
                sendNotification(title: state.name, message: errorMessage, type: .error)
                return
            }

            do {
                let result = try await shell.run(script)
                if result.succeeded {
                    sendNotification(
                        title: state.name,
                        message: "Action completed successfully.",
                        type: .success
                    )
                } else {
                    let errorMessage = result.stderr.isEmpty ? "Script failed (exit code \(result.exitCode))" : result.stderr
                    state.lastError = errorMessage
                    sendNotification(title: state.name, message: errorMessage, type: .error)
                }
            } catch {
                state.lastError = error.localizedDescription
                sendNotification(title: state.name, message: error.localizedDescription, type: .error)
            }
            state.isLoading = false
        }
    }

    /// Runs a `.feed` resource: executes the script, parses stdout as
    /// `FeedPayload` JSON, and stores the result on `state.lastFeed`.
    ///
    /// MARK: - Feed polling policy
    ///
    /// `.feed` resources are **manual-refresh only** in v1 — they are
    /// triggered exclusively by the refresh button in `ResourceRowView` and
    /// are intentionally **not** wired into the toggle status-polling loop
    /// (see `refreshAllStatuses`). Auto-polling for feeds is a sensible
    /// follow-up but is out of scope for this change.
    func runFeed(_ resourceId: UUID) {
        guard let state = resources.first(where: { $0.id == resourceId }),
              state.type == .feed else { return }

        Task {
            state.isLoading = true
            state.lastError = nil
            defer { state.isLoading = false; state.lastChecked = Date() }

            guard let script = state.resource.actionScript, !script.isEmpty else {
                let errorMessage = "No script configured"
                state.lastError = errorMessage
                sendNotification(title: state.name, message: errorMessage, type: .error)
                return
            }

            do {
                let result = try await shell.run(script)
                guard result.succeeded else {
                    let errorMessage = result.stderr.isEmpty ? "Script failed (exit code \(result.exitCode))" : result.stderr
                    state.lastError = errorMessage
                    sendNotification(title: state.name, message: errorMessage, type: .error)
                    return
                }
                guard let data = result.stdout.data(using: .utf8),
                      let payload = FeedPayload.decode(from: data) else {
                    let errorMessage = "Could not parse feed JSON"
                    state.lastError = errorMessage
                    sendNotification(title: state.name, message: errorMessage, type: .error)
                    return
                }
                state.lastFeed = payload
                let newCount = payload.newCount
                if newCount > 0 {
                    let itemWord = newCount == 1 ? "item" : "items"
                    sendNotification(
                        title: state.name,
                        message: "\(newCount) new \(itemWord) available.",
                        type: .success
                    )
                }
            } catch {
                state.lastError = error.localizedDescription
                sendNotification(title: state.name, message: error.localizedDescription, type: .error)
            }
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, message: String, type: NotificationService.NotificationType) {
        guard enableNotifications else { return }
        notificationService.notify(title: title, message: message, type: type)
    }

    // MARK: - Status Polling

    func refreshAllStatuses() async {
        await withTaskGroup(of: Void.self) { group in
            for state in resources where state.type == .toggle {
                group.addTask { [weak self] in
                    await self?.refreshStatus(for: state.id)
                }
            }
        }
    }

    func refreshStatus(for resourceId: UUID) async {
        guard let state = resources.first(where: { $0.id == resourceId }),
              let script = state.resource.statusScript, !script.isEmpty else { return }

        state.isLoading = true
        defer {
            state.isLoading = false
            state.lastChecked = Date()
        }

        do {
            let result = try await shell.run(script)
            state.isOn = result.succeeded  // Exit code 0 = ON
            state.lastError = nil
        } catch {
            state.lastError = error.localizedDescription
        }
    }

    func startPolling() {
        stopPolling()
        guard pollingIntervalSeconds > 0 else { return }
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(pollingIntervalSeconds),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAllStatuses()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func restartPolling() {
        startPolling()
    }

    func updatePollingInterval(_ seconds: Int) {
        pollingIntervalSeconds = seconds
        saveConfig()
        restartPolling()
    }
}
