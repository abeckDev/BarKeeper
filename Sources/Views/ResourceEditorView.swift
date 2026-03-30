import SwiftUI

struct ResourceEditorView: View {
    let resource: Resource?
    let onSave: (Resource) -> Void

    @State private var name: String = ""
    @State private var type: ResourceType = .toggle
    @State private var actionScript: String = ""
    @State private var statusScript: String = ""
    @State private var onScript: String = ""
    @State private var offScript: String = ""

    @Environment(\.dismiss) private var dismiss

    // Track if this is a standalone sheet (new resource) vs inline editor
    private var isNewResource: Bool { resource == nil }

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    Label("Button", systemImage: "bolt.fill").tag(ResourceType.button)
                    Label("Toggle", systemImage: "switch.2").tag(ResourceType.toggle)
                }
            }

            if type == .button {
                Section("Action Script") {
                    scriptEditor(text: $actionScript, placeholder: "echo \"Hello from BarKeeper\"")
                }
            } else {
                Section("Status Script") {
                    scriptEditor(text: $statusScript, placeholder: "Exit code 0 = ON, non-zero = OFF")
                }
                Section("On Script") {
                    scriptEditor(text: $onScript, placeholder: "Script to turn resource ON")
                }
                Section("Off Script") {
                    scriptEditor(text: $offScript, placeholder: "Script to turn resource OFF")
                }
            }

            if isNewResource {
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add") { save(); dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.isEmpty)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .padding(isNewResource ? 20 : 0)
        .frame(minWidth: isNewResource ? 450 : nil, minHeight: isNewResource ? 400 : nil)
        .onAppear { loadFromResource() }
        .onChange(of: name) { _, _ in saveIfInline() }
        .onChange(of: type) { _, _ in saveIfInline() }
        .onChange(of: actionScript) { _, _ in saveIfInline() }
        .onChange(of: statusScript) { _, _ in saveIfInline() }
        .onChange(of: onScript) { _, _ in saveIfInline() }
        .onChange(of: offScript) { _, _ in saveIfInline() }
    }

    // MARK: - Helpers

    private func scriptEditor(text: Binding<String>, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 60, maxHeight: 120)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .font(.system(.body, design: .monospaced))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
    }

    private func loadFromResource() {
        guard let r = resource else { return }
        name = r.name
        type = r.type
        actionScript = r.actionScript ?? ""
        statusScript = r.statusScript ?? ""
        onScript = r.onScript ?? ""
        offScript = r.offScript ?? ""
    }

    private func buildResource() -> Resource {
        Resource(
            id: resource?.id ?? UUID(),
            name: name,
            type: type,
            actionScript: type == .button ? actionScript.nilIfEmpty : nil,
            statusScript: type == .toggle ? statusScript.nilIfEmpty : nil,
            onScript: type == .toggle ? onScript.nilIfEmpty : nil,
            offScript: type == .toggle ? offScript.nilIfEmpty : nil
        )
    }

    private func save() {
        onSave(buildResource())
    }

    /// For inline editing (detail panel), auto-save on changes.
    private func saveIfInline() {
        guard !isNewResource, !name.isEmpty else { return }
        onSave(buildResource())
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
