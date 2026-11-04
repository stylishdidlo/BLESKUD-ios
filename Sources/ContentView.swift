import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var client = BleSkudClient()
    @StateObject private var store = ProfileStore()

    @State private var activeProfile: AccessProfile?
    @State private var editingProfile: AccessProfile?
    @State private var showingEditor = false
    @State private var showingImporter = false
    @State private var showingExporter = false

    var body: some View {
        NavigationView {
            List {
                Section("Профили") {
                    if store.profiles.isEmpty {
                        Text("(нет профилей — нажмите +)")
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.profiles) { p in
                        Button {
                            activeProfile = p
                        } label: {
                            HStack {
                                Text(activeProfile?.id == p.id ? "●" : "○")
                                VStack(alignment: .leading) {
                                    Text(p.name).font(.headline)
                                    Text(p.skudUuid).font(.caption).foregroundColor(.secondary)
                                    Text("KeyID \(p.keyId), RSSI ≥ \(p.rssiThreshold)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.delete(id: p.id)
                                if activeProfile?.id == p.id { activeProfile = nil }
                            } label: { Label("Удалить", systemImage: "trash") }
                            Button {
                                editingProfile = p
                                showingEditor = true
                            } label: { Label("Изм.", systemImage: "pencil") }
                            .tint(.blue)
                        }
                    }
                }

                Section {
                    HStack {
                        Button("Start") { start() }
                            .buttonStyle(.borderedProminent)
                            .disabled(activeProfile == nil)
                        Button("Stop") { client.stop() }
                            .buttonStyle(.bordered)
                    }
                }

                Section("Статус") {
                    Text(stateText).font(.headline)
                    Text(client.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("BLE SKUD")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("+ Новый профиль") {
                            editingProfile = nil
                            showingEditor = true
                        }
                        Button("Импорт из файла") { showingImporter = true }
                        Button("Экспорт в файл") { showingExporter = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                ProfileEditorView(
                    profile: editingProfile,
                    onSave: { p in
                        store.upsert(p)
                        if activeProfile?.id == p.id { activeProfile = p }
                        if activeProfile == nil { activeProfile = p }
                        showingEditor = false
                    },
                    onCancel: { showingEditor = false },
                    onDelete: editingProfile.map { p in
                        { store.delete(id: p.id); if activeProfile?.id == p.id { activeProfile = nil }; showingEditor = false }
                    }
                )
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let json = try? String(contentsOf: url) {
                        _ = store.importJSON(json)
                    }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: JSONDocument(text: store.exportJSON()),
                contentType: .json,
                defaultFilename: "ble_skud_profiles.json"
            ) { _ in }
        }
    }

    private func start() {
        guard let p = activeProfile else { return }
        client.startScan(profile: p)
    }

    private var stateText: String {
        switch client.state {
        case .idle: return "Idle"
        case .scanning: return "Scanning..."
        case .connecting(let u): return "Connecting \(u)"
        case .connected(let u, let r): return "Connected \(u) \(r)"
        case .success: return "OPEN SIGNAL SENT"
        case .failed(let r): return "FAIL: \(r)"
        }
    }
}

// ─── JSON document для fileExporter ───
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
