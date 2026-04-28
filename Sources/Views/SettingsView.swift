import SwiftUI

struct SettingsView: View {
    @Environment(ResourceManager.self) private var manager
    @State private var selectedResourceId: UUID?
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var importError: String?
    @State private var showAddSheet = false

    var body: some View {
        HSplitView {
            sidebarList
                .frame(minWidth: 180, idealWidth: 200)

            detailPanel
                .frame(minWidth: 380)
        }
        .sheet(isPresented: $showAddSheet) {
            ResourceEditorView(resource: nil) { newResource in
                manager.addResource(newResource)
                selectedResourceId = newResource.id
            }
        }
        .alert("Import Error", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebarList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedResourceId) {
                ForEach(manager.resources) { state in
                    Label(state.name, systemImage: state.type == .toggle ? "switch.2" : "bolt.fill")
                        .tag(state.id)
                }
                .onMove { source, destination in
                    manager.moveResources(from: source, to: destination)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        manager.deleteResource(id: manager.resources[index].id)
                    }
                }
            }

            Divider()

            HStack {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add resource")

                if let selectedId = selectedResourceId {
                    Button {
                        manager.deleteResource(id: selectedId)
                        selectedResourceId = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Remove resource")
                }

                Spacer()

                Menu {
                    Button("Import JSON…") { showingImporter = true }
                    Button("Export JSON…") { showingExporter = true }
                    Divider()
                    Button("Add Fabric Capacity Example") {
                        let example = AppConfiguration.fabricCapacityExample()
                        manager.addResource(example)
                        selectedResourceId = example.id
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
            .padding(8)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: JSONDocument(data: manager.exportConfig()),
                contentType: .json,
                defaultFilename: "BarKeeper-config.json"
            ) { _ in }
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedId = selectedResourceId,
           let state = manager.resources.first(where: { $0.id == selectedId }) {
            ResourceEditorView(resource: state.resource) { updated in
                manager.updateResource(updated)
            }
        } else {
            VStack(spacing: 16) {
                pollingSettings
                Spacer()
                Text("Select a resource or add a new one")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
        }
    }

    private var pollingSettings: some View {
        GroupBox("Polling") {
            HStack {
                Text("Check status every:")
                Picker("", selection: Binding(
                    get: { manager.pollingIntervalSeconds },
                    set: { manager.updatePollingInterval($0) }
                )) {
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                    Text("Never").tag(0)
                }
                .frame(width: 140)
            }
            .padding(4)
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Cannot access file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                if !manager.importConfig(from: data) {
                    importError = "Invalid BarKeeper configuration file."
                }
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - JSON Document for file exporter

import UniformTypeIdentifiers

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data?

    init(data: Data?) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data ?? Data())
    }
}
