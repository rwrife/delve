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
    var run: StoredRun?
    var exploring = false
    var paused = false
    var error: String?
    var ending: String?

    init() { open() }

    func open() {
        perform {
            let tables = try RuleTables.wingOne()
            _ = try QuestEngine.wingOne(tables: tables)
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try DelveStore.atPath(directory.appendingPathComponent("delve.sqlite").path)
            let run = try store.activeRun(tables: tables)
            self.tables = tables
            self.store = store
            self.run = run
        }
    }

    func start() {
        guard let store, let tables else { return }
        perform {
            let next = try store.start(tables: tables)
            publish(next)
            ending = nil
        }
    }

    func resume() {
        guard let store, let tables else { return }
        perform {
            if let next = try store.activeRun(tables: tables) { publish(next) }
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
            ending = next.world.isDead ? "The patrol ended your delve. Your run is preserved." : "You retreated. Your run is preserved."
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

/// The single composition seam. A future companion surface belongs here;
/// issue #5's journal is deliberately not implemented by this exploration slice.
struct DelveWorkspaceLayout<Dungeon: View, Controls: View>: View {
    @ViewBuilder var dungeon: () -> Dungeon
    @ViewBuilder var controls: () -> Controls
    var body: some View {
        VStack(spacing: 16) { dungeon(); controls() }
    }
}

struct BootstrapHomeView: View {
    @State private var model = ExplorationModel()
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
                            Text("Explore the first wing of a fixed dungeon.")
                            if let ending = model.ending { Text(ending).accessibilityIdentifier("run.ending") }
                            control("New delve", id: "entrance.new") { model.start() }
                                .disabled(model.store == nil)
                            if model.run != nil {
                                control("Resume delve", id: "entrance.resume") { model.resume() }
                            }
                            Text("Original geometric placeholder art. Clue journal and further wings are planned.").font(.footnote)
                        }.padding()
                    }.accessibilityIdentifier("entrance")
                }
            }
            .padding()
            .navigationTitle(model.exploring ? "Exploration" : "Entrance")
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
                        }
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
