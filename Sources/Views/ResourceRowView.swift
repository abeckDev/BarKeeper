import SwiftUI

struct ResourceRowView: View {
    @Environment(ResourceManager.self) private var manager
    let state: ResourceState

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
            Text(state.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else {
                actionControl
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(tooltipText)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIndicator: some View {
        switch state.type {
        case .toggle:
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        case .button:
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        switch state.type {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { state.isOn },
                set: { _ in manager.toggle(state.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

        case .button:
            Button {
                manager.runAction(state.id)
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var hoverBackground: some ShapeStyle {
        .quaternary.opacity(0.5)
    }

    private var statusColor: Color {
        if state.lastError != nil { return .red }
        return state.isOn ? .green : .gray
    }

    private var tooltipText: String {
        var parts: [String] = []
        if let error = state.lastError {
            parts.append("Error: \(error)")
        }
        if let checked = state.lastChecked {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            parts.append("Checked \(formatter.localizedString(for: checked, relativeTo: Date()))")
        }
        return parts.joined(separator: "\n")
    }
}
