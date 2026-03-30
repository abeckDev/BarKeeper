import SwiftUI

@main
struct BarKeeperApp: App {
    @State private var resourceManager = ResourceManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(resourceManager)
        } label: {
            MenuBarLabel()
                .environment(resourceManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(resourceManager)
                .frame(minWidth: 600, minHeight: 450)
        }
    }
}

struct MenuBarLabel: View {
    @Environment(ResourceManager.self) private var manager

    var body: some View {
        Image(systemName: menuBarIconName)
            .symbolRenderingMode(.hierarchical)
    }

    private var menuBarIconName: String {
            if manager.resources.contains(where: { $0.lastError != nil }) {
                return "exclamationmark.circle.fill"
            }
            if manager.resources.contains(where: { $0.type == .toggle && $0.isOn }) {
                return "slider.horizontal.below.square.filled.and.square"
            }
            return "slider.horizontal.3"
        }
}
