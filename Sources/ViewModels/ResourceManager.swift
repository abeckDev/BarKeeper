import Foundation
import SwiftUI

@Observable
@MainActor
final class ResourceManager {
    private(set) var resources: [ResourceState] = []
    var pollingIntervalSeconds: Int = 3600

    private let shell = ShellExecutor()
    private var pollingTimer: Timer?

    init() {
        loadConfig()
        startPolling()
    }

    // MARK: - Configuration

    func loadConfig() {
        let config = ConfigStore.load()
        pollingIntervalSeconds = config.pollingIntervalSeconds
        resources = config.resources.map { ResourceState(resource: $0) }
        Task { await refreshAllStatuses() }
    }

    func saveConfig() {
        let config = AppConfiguration(
            resources: resources.map(\.resource),
            pollingIntervalSeconds: pollingIntervalSeconds
        )
        ConfigStore.save(config)
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
        let state = ResourceState(resource: resource)
        state.isOn = resources[index].isOn
        resources[index] = state
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
            pollingIntervalSeconds: pollingIntervalSeconds
        )
        return ConfigStore.exportJSON(from: config)
    }

    func importConfig(from data: Data) -> Bool {
        guard let config = ConfigStore.importJSON(from: data) else { return false }
        pollingIntervalSeconds = config.pollingIntervalSeconds
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

            let script = state.isOn ? state.resource.offScript : state.resource.onScript
            guard let script, !script.isEmpty else {
                state.lastError = "No \(state.isOn ? "off" : "on") script configured"
                state.isLoading = false
                return
            }

            do {
                let result = try await shell.run(script)
                if result.succeeded {
                    // After toggling, refresh the actual status
                    await refreshStatus(for: resourceId)
                } else {
                    state.lastError = result.stderr.isEmpty ? "Script failed (exit code \(result.exitCode))" : result.stderr
                    state.isLoading = false
                }
            } catch {
                state.lastError = error.localizedDescription
                state.isLoading = false
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
                state.lastError = "No action script configured"
                state.isLoading = false
                return
            }

            do {
                let result = try await shell.run(script)
                if !result.succeeded {
                    state.lastError = result.stderr.isEmpty ? "Script failed (exit code \(result.exitCode))" : result.stderr
                }
            } catch {
                state.lastError = error.localizedDescription
            }
            state.isLoading = false
        }
    }

    /// Runs a `.report` resource: executes the script (with $FOUNDRY_CHECK set
    /// to the embedded helper), parses stdout as JSON, stores the payload.
    func runReport(_ resourceId: UUID) {
        guard let state = resources.first(where: { $0.id == resourceId }),
              state.type == .report else { return }

        Task {
            state.isLoading = true
            state.lastError = nil
            defer { state.isLoading = false; state.lastChecked = Date() }

            guard let script = state.resource.actionScript, !script.isEmpty else {
                state.lastError = "No script configured"
                return
            }

            var env: [String: String] = [:]
            if let helper = Self.embeddedFoundryCheckPath() {
                env["FOUNDRY_CHECK"] = helper
            }

            do {
                let result = try await shell.run(script, extraEnvironment: env)
                guard result.succeeded else {
                    state.lastError = result.stderr.isEmpty ? "Script failed (exit code \(result.exitCode))" : result.stderr
                    return
                }
                guard let data = result.stdout.data(using: .utf8),
                      let payload = ReportPayload.decode(from: data) else {
                    state.lastError = "Could not parse report JSON"
                    return
                }
                state.lastReport = payload
            } catch {
                state.lastError = error.localizedDescription
            }
        }
    }

    /// Resolves the bundled `foundry-check` helper inside the .app bundle.
    /// Falls back to `nil` (script can use a system-installed copy via PATH).
    private static func embeddedFoundryCheckPath() -> String? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "foundry-check") {
            return url.path
        }
        // Dev fallback: look next to the running executable.
        let exeDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let candidate = exeDir.appendingPathComponent("foundry-check").path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
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
