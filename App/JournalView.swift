import SwiftUI
import DelveKit
import DelveStore

struct JournalView: View {
    let run: StoredRun
    let store: DelveStore
    let tables: RuleTables
    let quest: QuestEngine
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [String: String] = [:]
    @State private var markedGoals: Set<String> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                NavigationLink("Room notes") { notesPage }
                    .accessibilityIdentifier("journal.notes")
                NavigationLink("Quest inscriptions") { questsPage }
                    .accessibilityIdentifier("journal.quests")
                NavigationLink("Run record") { recordPage }
                    .accessibilityIdentifier("journal.record")
                // System toolbar text caps Dynamic Type; keep dismissal in the scalable list.
                Button { dismiss() } label: {
                    Text("Done").foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain) // Keep the label's primary color instead of List's tinted button style.
                .accessibilityIdentifier("journal.done")
            }
            .navigationTitle("Journal")
            .task { reload() }
        }
    }

    private var notesPage: some View {
        List {
            Text("One pinned note per visited room. Notes belong to you, not the dungeon engine.")
            ForEach(run.world.visitedRooms.sorted(), id: \.self) { room in
                NavigationLink {
                    RoomNoteEditor(room: room, initial: notes[room] ?? "") { text in
                        try store.setNote(text, roomID: room, runID: run.id, tables: tables)
                        reload()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title(room)).font(.headline)
                        Text(notes[room] ?? "No note recorded").font(.body)
                    }
                }
                .accessibilityIdentifier("note.room.\(room)")
            }
        }.navigationTitle("Room notes")
    }

    private var questsPage: some View {
        List {
            Text("Your checkmarks are theories. Dungeon state is derived separately from recorded events.")
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(quest.goals, id: \.id) { goal in
                VStack(alignment: .leading, spacing: 12) {
                    Text(goal.text).font(.headline)
                    Button {
                        let marked = !markedGoals.contains(goal.id)
                        do {
                            try store.setGoalMarked(marked, goalID: goal.id, runID: run.id, quest: quest, tables: tables)
                            reload()
                        } catch { self.error = "Could not save your mark: \(error.localizedDescription)" }
                    } label: {
                        Label(markedGoals.contains(goal.id) ? "Marked by you" : "Not marked by you",
                              systemImage: markedGoals.contains(goal.id) ? "checkmark.square" : "square")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quest.mark.\(goal.id)")
                    Text("Dungeon state: \(progress(goal.id))")
                        .accessibilityIdentifier("quest.engine.\(goal.id)")
                }.padding(.vertical, 8)
            }
        }.navigationTitle("Quest inscriptions")
    }

    private var recordPage: some View {
        List {
            Text("Ledger facts. Missing evidence is Unknown, never a guessed zero. Steps include the initial entrance visit.")
            if let record = try? RunRecord.derive(from: run.ledger, tables: tables) {
                Text("Rooms visited: \(RunRecord.display(record.roomsVisited))").accessibilityIdentifier("record.rooms")
                Text("Movement steps: \(RunRecord.display(record.steps))").accessibilityIdentifier("record.steps")
                Text("Sessions played: \(RunRecord.display(record.sessions))").accessibilityIdentifier("record.sessions")
                Section("Discoveries recorded") {
                    switch record.discoveries {
                    case .unknown: Text("Unknown")
                    case .known(let ids):
                        if ids.isEmpty { Text("None recorded yet") }
                        ForEach(ids, id: \.self) { Text(title($0)) }
                    }
                }
            } else { Text("Run record unavailable. No counts inferred.") }
        }.navigationTitle("Run record")
    }

    private func progress(_ id: String) -> String {
        switch try? quest.progress(for: id, ledger: run.ledger, tables: tables) {
        case .unknown: return "Unknown"
        case .inProgress: return "In progress"
        case .achieved: return "Achieved"
        case nil: return "Unavailable"
        }
    }

    private func reload() {
        do {
            let journal = try store.journal(runID: run.id, tables: tables)
            notes = journal.notes
            markedGoals = journal.markedGoals
            error = nil
        } catch { self.error = "Could not load journal: \(error.localizedDescription)" }
    }

    private func title(_ id: String) -> String { id.replacingOccurrences(of: "-", with: " ").capitalized }
}

private struct RoomNoteEditor: View {
    let room: String
    let save: @MainActor @Sendable (String) throws -> Void
    @State private var draft: String
    @State private var message: String?
    @FocusState private var editorFocused: Bool

    init(room: String, initial: String, save: @escaping @MainActor @Sendable (String) throws -> Void) {
        self.room = room
        self.save = save
        _draft = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pinned room note, up to 10,000 characters. Save before leaving; Delete removes the saved note.")
                if let message {
                    Text(message)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("note.status")
                }
                Button { persist(draft) } label: {
                    Text("Save").foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.save")
                Button { persist("") } label: {
                    Text("Delete note").foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.delete")
                TextEditor(text: $draft)
                    .focused($editorFocused)
                    .frame(minHeight: 200)
                    .accessibilityLabel("Room note")
                    .accessibilityIdentifier("note.editor")
            }.padding()
        }
        .navigationTitle(room.replacingOccurrences(of: "-", with: " ").capitalized)
    }

    private func persist(_ text: String) {
        // Drop first responder so the keyboard never covers the status message.
        editorFocused = false
        do {
            try save(text)
            draft = text
            message = text.isEmpty ? "Note deleted" : "Note saved"
        } catch { message = "Could not save note. Your draft is unchanged. \(error.localizedDescription)" }
    }
}
