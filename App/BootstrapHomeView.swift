import Foundation
import Observation
import DelveKit
import DelveStore
import SwiftUI
import SpriteKit

@MainActor
@Observable
final class ExplorationModel {
    var store: DelveStore?
    var tables: RuleTables?
    var quest: QuestEngine?
    var run: StoredRun?
    var lastRecord: RunRecord?
    var exploring = false
    var paused = false
    var error: String?
    var ending: String?

    init() { open() }

    func open() {
        perform {
            let versions = try RuleTables.bundledVersions()
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try DelveStore.atPath(directory.appendingPathComponent("delve.sqlite").path)
            let matched = try store.activeRun(matching: versions)
            let fallback = try RuleTables.fullDungeon()
            let chosen = matched?.tables ?? fallback
            let chosenQuest = try QuestEngine.bundledFor(tables: chosen)
            self.tables = chosen
            self.quest = chosenQuest
            self.store = store
            self.run = matched?.run
        }
    }

    func start() {
        perform {
            guard let store else { return }
            let tables = try RuleTables.fullDungeon()
            let quest = try QuestEngine.bundledFor(tables: tables)
            let next = try store.start(tables: tables)
            self.tables = tables
            self.quest = quest
            publish(next)
            ending = nil
            lastRecord = nil
        }
    }

    func resume() {
        guard let store, let tables else { return }
        perform {
            if let active = try store.activeRun(tables: tables) {
                let recorded = try store.resumeSession(active, tables: tables)
                publish(recorded)
            }
        }
    }

    func act(_ event: GameEvent) {
        guard !paused, let run, let store, let tables else { return }
        perform { publish(try store.advance(run, event: event, tables: tables)) }
    }

    @discardableResult
    func save() -> Bool {
        guard let run, !run.world.isTerminal, let store, let tables else { return true }
        return perform { try store.save(run, tables: tables) }
    }

    private func publish(_ next: StoredRun) {
        run = next
        paused = false
        exploring = !next.world.isTerminal
        if next.world.isTerminal {
            if let tables { lastRecord = try? RunRecord.derive(from: next.ledger, tables: tables) }
            ending = next.world.finished ? "You reached the dawn well. The delve is complete."
                : next.world.isDead ? "The patrol ended your delve. Your run is preserved."
                : "You retreated. Your run is preserved."
            run = nil
        }
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do { try work(); error = nil; return true }
        catch {
            self.error = "Could not save or load the delve. Progress has not changed. \(error.localizedDescription)"
            return false
        }
    }
}

/// The single composition seam: journal is a sheet today, a companion
/// surface in the documented dual-screen design. No unavailable SDK APIs.
struct DelveWorkspaceLayout<Dungeon: View, Controls: View, JournalSurface: View>: View {
    @ViewBuilder var dungeon: () -> Dungeon
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var journal: () -> JournalSurface
    @State private var journalPresented = false
    var body: some View {
        VStack(spacing: 16) {
            Button("Clue journal") { journalPresented = true }
                .frame(minHeight: 56).buttonStyle(.bordered)
                .accessibilityIdentifier("journal.open")
            dungeon()
            controls()
        }
        // ponytail: full-screen journal keeps iOS 26's translucent sheet
        // chrome from lowering row contrast; return to sheet once audited.
        .fullScreenCover(isPresented: $journalPresented) {
            journal().presentationBackground(Color(uiColor: .systemBackground))
        }
    }
}

struct BootstrapHomeView: View {
    @State private var model = ExplorationModel()
    @State private var dataPresented = false
    @State private var newRunConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack {
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("save.error")
                    control("Retry store", id: "store.retry") { model.open() }
                }
                if model.exploring, let run = model.run, let tables = model.tables {
                    exploration(run, tables: tables)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("Delve").font(.largeTitle.bold())
                            Text("Explore a fixed three-wing dungeon.")
                            if let ending = model.ending { Text(ending).accessibilityIdentifier("run.ending") }
                            if let record = model.lastRecord { epilogue(record) }
                            control("New delve", id: "entrance.new") {
                                do {
                                    if model.run != nil, let store = model.store,
                                       try store.backup(versions: RuleTables.bundledVersions()).settings.confirmNewRun {
                                        newRunConfirmation = true
                                    } else { model.start() }
                                } catch { model.error = error.localizedDescription }
                            }
                                .disabled(model.store == nil)
                            if model.run != nil {
                                control("Resume delve", id: "entrance.resume") { model.resume() }
                            }
                            Text("Original geometric placeholder art.").font(.footnote)
                        }.padding()
                    }.accessibilityIdentifier("entrance")
                }
            }
            .padding()
            .navigationTitle(model.exploring ? "Exploration" : "Entrance")
            .toolbar {
                Button("Your data") { dataPresented = true }
                    .disabled(model.store == nil)
                    .accessibilityIdentifier("data.open")
            }
            .sheet(isPresented: $dataPresented) {
                if let store = model.store {
                    DataOwnershipView(store: store) {
                        model.exploring = false; model.paused = false
                        model.lastRecord = nil; model.ending = nil
                        model.open()
                    }
                }
            }
            .confirmationDialog("Start a new delve? Your previous run stays in the backup history.", isPresented: $newRunConfirmation, titleVisibility: .visible) {
                Button("Start new delve") { model.start() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                if model.save(), model.exploring { model.paused = true }
            }
        }
    }

    private func exploration(_ run: StoredRun, tables: RuleTables) -> some View {
        VStack(spacing: 8) {
            // Pause remains outside scrolling content, reachable in every room.
            control(model.paused ? "Continue delve" : "Pause", id: "exploration.pause") {
                if model.save() { model.paused.toggle() }
            }
            ScrollView {
                DelveWorkspaceLayout {
                    VStack {
                        Text(title(run.world.currentRoom ?? "entrance"))
                            .font(.title.bold()).accessibilityIdentifier("room.title")
                        Text("\(run.world.visitedRooms.count) rooms visited · \(run.ledger.entries.count) events saved")
                        SpriteView(scene: RoomScene(world: run.world, tables: tables))
                            .frame(height: 200).accessibilityHidden(true)
                        Text("Original geometric placeholder art: circle = explorer, squares = doors, diamonds = items, triangles = puzzles, stars = discoveries.")
                            .font(.caption)
                        ForEach(run.world.keys.sorted(), id: \.self) { key in
                            Label("Collected \(title(key))", systemImage: "checkmark.diamond")
                        }
                    }
                } controls: {
                    VStack(spacing: 8) {
                        if model.paused {
                            Text("Paused — progress saved").font(.headline).accessibilityIdentifier("exploration.paused")
                            control("Return to entrance", id: "pause.entrance") { model.exploring = false }
                        } else {
                            ForEach(tables.graph.connections(from: run.world.currentRoom ?? "").map(\.neighbor), id: \.self) { neighbor in
                                let allowed = RuleEngine.stepResult(run.world, .visit(room: neighbor), tables: tables).accepted
                                control("\(allowed ? "◇" : "▣") Move to \(title(neighbor))\(allowed ? "" : " — locked")", id: "move.\(neighbor)") {
                                    model.act(.visit(room: neighbor))
                                }.disabled(!allowed)
                            }
                            ForEach((tables.switchRooms ?? [:]).keys.sorted().filter { tables.switchRooms?[$0] == run.world.currentRoom }, id: \.self) { element in
                                let effects = tables.switchEffects[element] ?? []
                                let on = effects.allSatisfy(run.world.flags.contains)
                                control("\(on ? "✓ On" : "○ Off") · Use \(title(element))", id: "interact.\(element)") {
                                    model.act(.action(element: element, effects: effects))
                                }
                            }
                            ForEach(tables.discoverySpawns.keys.sorted().filter { tables.discoverySpawns[$0] == run.world.currentRoom }, id: \.self) { id in
                                let found = run.world.discoveries.contains(id)
                                control("\(found ? "✓ Recorded" : "◇ Discover") \(title(id))", id: "discover.\(id)") { model.act(.discovery(id: id)) }
                                    .disabled(found)
                            }
                            control("Retreat to entrance", id: "exploration.retreat") { model.act(.retreat) }
                            if run.world.currentRoom == tables.goalRoom, tables.contentVersion >= 3 {
                                control("Finish the delve", id: "exploration.finish") { model.act(.finish) }
                            }
                        }
                    }
                } journal: {
                    if let store = model.store, let quest = model.quest {
                        JournalView(run: run, store: store, tables: tables, quest: quest)
                    }
                }
            }
        }
    }

    private func control(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func epilogue(_ record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run record").font(.headline)
            Text("Rooms visited: \(RunRecord.display(record.roomsVisited))")
            Text("Steps: \(RunRecord.display(record.steps))")
                .accessibilityIdentifier("epilogue.steps")
            Text("Sessions: \(RunRecord.display(record.sessions))")
                .accessibilityIdentifier("epilogue.sessions")
            switch record.discoveries {
            case .unknown: Text("Discoveries: unknown").accessibilityIdentifier("epilogue.discoveries")
            case .known(let ids): Text("Discoveries: \(ids.isEmpty ? "none recorded" : ids.map(title).joined(separator: ", "))")
                .accessibilityIdentifier("epilogue.discoveries")
            }
        }
    }

    private func title(_ id: String) -> String { id.replacingOccurrences(of: "-", with: " ").capitalized }
}

@MainActor
final class RoomScene: SKScene {
    init(world: WorldState, tables: RuleTables) {
        super.init(size: CGSize(width: 340, height: 200))
        scaleMode = .aspectFit
        backgroundColor = .darkGray
        let room = world.currentRoom ?? tables.spawnRoom
        let floor = SKShapeNode(rect: CGRect(x: 12, y: 12, width: 316, height: 176), cornerRadius: 12)
        floor.strokeColor = .white
        addChild(floor)
        let hero = SKShapeNode(circleOfRadius: 14)
        hero.position = CGPoint(x: 170, y: 90)
        hero.fillColor = .white
        addChild(hero)
        for (index, connection) in tables.graph.connections(from: room).enumerated() {
            let door = SKShapeNode(rectOf: CGSize(width: 24, height: 24))
            door.position = CGPoint(x: CGFloat(40 + index * 65), y: 160)
            door.strokeColor = .white
            addChild(door)
            let allowed = RuleEngine.stepResult(world, .visit(room: connection.neighbor), tables: tables).accepted
            let label = SKLabelNode(text: allowed ? "◇" : "▣")
            label.position = door.position
            label.fontSize = 16
            addChild(label)
        }
        for (index, id) in tables.discoverySpawns.keys.sorted().filter({ tables.discoverySpawns[$0] == room }).enumerated() {
            let discovery = SKLabelNode(text: world.discoveries.contains(id) ? "✧ ✓" : "✧ ?")
            discovery.position = CGPoint(x: CGFloat(60 + index * 50), y: 90)
            addChild(discovery)
        }
        for (index, key) in tables.keySpawns.keys.sorted().filter({ tables.keySpawns[$0] == room }).enumerated() {
            let item = SKLabelNode(text: world.keys.contains(key) ? "✓" : "◆")
            item.position = CGPoint(x: CGFloat(70 + index * 40), y: 40)
            addChild(item)
        }
        for (index, element) in (tables.switchRooms ?? [:]).keys.sorted().filter({ tables.switchRooms?[$0] == room }).enumerated() {
            let on = (tables.switchEffects[element] ?? []).allSatisfy(world.flags.contains)
            let puzzle = SKLabelNode(text: on ? "▲ ✓" : "△ ○")
            puzzle.position = CGPoint(x: CGFloat(240 + index * 40), y: 40)
            addChild(puzzle)
        }
    }
    required init?(coder: NSCoder) { fatalError("RoomScene is constructed from world state") }
}
