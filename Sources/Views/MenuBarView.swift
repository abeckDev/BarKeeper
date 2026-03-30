import SwiftUI

struct MenuBarView: View {
    @Environment(ResourceManager.self) private var manager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if manager.resources.isEmpty {
                emptyState
            } else {
                resourceList
            }
            Divider().padding(.vertical, 4)
            bottomActions
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No resources configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open Settings to add one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var resourceList: some View {
        VStack(spacing: 6) {
            ForEach(manager.resources) { state in
                ResourceRowView(state: state)
            }
        }
    }

    private var bottomActions: some View {
        HStack {
            Button {
                Task { await manager.refreshAllStatuses() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                openSettings()
                // Bring the settings window to the front on the current screen
                DispatchQueue.main.async {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    for window in NSApplication.shared.windows where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
