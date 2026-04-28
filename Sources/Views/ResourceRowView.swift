import SwiftUI

struct ResourceRowView: View {
    @Environment(ResourceManager.self) private var manager
    let state: ResourceState

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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

            if state.type == .feed, isExpanded, let feed = state.lastFeed {
                feedItems(feed)
                    .padding(.leading, 24)
                    .padding(.bottom, 4)
            }
        }
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
        case .feed:
            Button {
                if state.lastFeed != nil { isExpanded.toggle() }
            } label: {
                Image(systemName: state.lastFeed != nil
                      ? (isExpanded ? "chevron.down" : "chevron.right")
                      : "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(feedIndicatorColor)
            }
            .buttonStyle(.plain)
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

        case .feed:
            HStack(spacing: 4) {
                if let feed = state.lastFeed, feed.newCount > 0 {
                    Text("\(feed.newCount) new")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Button {
                    manager.runFeed(state.id)
                    isExpanded = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func feedItems(_ feed: FeedPayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if feed.items.isEmpty {
                Text("No matching items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(feed.items.prefix(20)), id: \.self) { item in
                    HStack(spacing: 6) {
                        if item.isNew {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.green)
                        }
                        Text(item.name)
                            .font(.caption)
                        if let sub = item.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .help(item.detail ?? "")
                }
                if feed.items.count > 20 {
                    Text("… + \(feed.items.count - 20) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var hoverBackground: some ShapeStyle {
        .quaternary.opacity(0.5)
    }

    private var statusColor: Color {
        if state.lastError != nil { return .red }
        return state.isOn ? .green : .gray
    }

    private var feedIndicatorColor: Color {
        if state.lastError != nil { return .red }
        if let f = state.lastFeed, f.newCount > 0 { return .green }
        return .secondary
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
