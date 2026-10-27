import SwiftUI
import UniformTypeIdentifiers
import DelveKit
import DelveStore

private struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataOwnershipView: View {
    let store: DelveStore
    let restored: () -> Void
    @State private var importing = false
    @State private var exporting = false
    @State private var exportData = Data()
    @State private var exportType = UTType.json
    @State private var exportName = "Delve-backup"
    @State private var shareURL: URL?
    @State private var preview: RestorePreview?
    @State private var confirming = false
    @State private var message: String?
    @State private var confirmNewRun = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Back up and export") {
                    Text("JSON includes every saved run ledger, room note, quest mark, and setting. CSV includes notes and quest progress for all saved runs.")
                    Button("Prepare JSON backup") { prepare(csv: false) }.accessibilityIdentifier("data.backup")
                    Button("Prepare journal and quest CSV") { prepare(csv: true) }.accessibilityIdentifier("data.csv")
                    if let shareURL {
                        ShareLink("Share prepared file", item: shareURL)
                        Button("Save prepared file to Files") { exporting = true }
                    }
                }
                Section("Restore") {
                    Text("Restore replaces all local saves and settings. Export a backup first. Choose a JSON file to review changes before confirming.")
                    Button("Choose backup for preview") { preview = nil; importing = true }.accessibilityIdentifier("data.import")
                    if let preview {
                        let diff = preview.diff
                        Text("Runs: \(diff.added.count) added, \(diff.removed.count) removed, \(diff.changed.count) changed, \(diff.unchanged.count) unchanged")
                        diffRows("Added", diff.added)
                        diffRows("Removed", diff.removed)
                        diffRows("Changed", diff.changed)
                        Text("Ledger events: \(diff.eventsBefore) → \(diff.eventsAfter)")
                        Text("Room notes: \(diff.notesBefore) → \(diff.notesAfter)")
                        Text("Quest marks: \(diff.marksBefore) → \(diff.marksAfter)")
                        Text("Active run: \(diff.activeBefore ?? "None") → \(diff.activeAfter ?? "None")")
                        Text("Settings: \(diff.settingsChanged ? "will change" : "unchanged")")
                        Text("Confirm new delve: \(diff.settingsBefore.confirmNewRun ? "On" : "Off") → \(diff.settingsAfter.confirmNewRun ? "On" : "Off")")
                        Button("Review complete — restore…", role: .destructive) { confirming = true }
                            .accessibilityIdentifier("data.restore")
                        Button("Cancel preview") { self.preview = nil }
                    }
                }
                Section("Settings") {
                    Toggle("Confirm before replacing an active delve", isOn: $confirmNewRun)
                        .onChange(of: confirmNewRun) { _, value in
                            do { try store.setSettings(BackupSettings(confirmNewRun: value)) }
                            catch { message = error.localizedDescription }
                        }
                }
                if let message { Section { Text(message).accessibilityIdentifier("data.status") } }
            }
            .navigationTitle("Your data")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                do { confirmNewRun = try store.backup(versions: RuleTables.bundledVersions()).settings.confirmNewRun }
                catch { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= BackupCodec.maximumBytes else { throw BackupError.tooLarge }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    preview = try store.previewRestore(data, versions: RuleTables.bundledVersions())
                    message = nil
                } catch { message = "Backup could not be previewed: \(error.localizedDescription)" }
            }
            .fileExporter(isPresented: $exporting, document: ExportDocument(data: exportData), contentType: exportType, defaultFilename: exportName) { result in
                switch result {
                case .success: message = "File saved."
                case .failure(let error): message = "File could not be saved: \(error.localizedDescription)"
                }
            }
            .confirmationDialog("Replace all local data with this backup?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Replace all local data", role: .destructive) {
                    guard let preview else { return }
                    do {
                        try store.restore(preview, confirmed: true, versions: RuleTables.bundledVersions())
                        self.preview = nil
                        restored()
                        dismiss()
                    } catch {
                        self.preview = nil
                        message = "Restore failed; local data was preserved. Preview again. \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func diffRows(_ label: String, _ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { id in Text("\(label): \(id)").font(.caption) }
    }

    private func prepare(csv: Bool) {
        do {
            let versions = try RuleTables.bundledVersions()
            let archive = try store.backup(versions: versions)
            let data = try csv ? JournalCSV.export(archive, versions: versions) : BackupCodec.encode(archive, versions: versions)
            // A unique name keeps already-presented share items stable.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Delve-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = csv ? "Delve-journal.csv" : "Delve-backup.json"
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            exportData = data; exportType = csv ? .commaSeparatedText : .json
            exportName = name; shareURL = url; message = "Ready to share or save to Files."
        } catch { message = "Export failed: \(error.localizedDescription)" }
    }
}
