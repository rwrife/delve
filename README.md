# Delve

**An offline fixed-dungeon puzzle crawler, now playable on Windows with Godot 4.4.1. Explore all three wings (45 rooms), keep a clue journal, and export or restore your saves. The original native iPhone project is retained as a reference.**

## Run the Godot game

1. Install [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/) (the standard, non-.NET build).
2. In the Godot Project Manager, **Import** this repository's `project.godot`, open the project, and press **F5** to play. Alternatively, run `godot --path .` from the repository root.
3. Choose **New delve** or **Resume delve**. Use the on-screen buttons or keys **1–9** for exits, **J** for the journal, and **P** or **Esc** to pause.

Each accepted action is saved locally. On Windows, the Godot save is in `%APPDATA%\Godot\app_userdata\Delve\delve.json`; it is separate from the original iPhone app's SQLite database. **Your data** exports JSON backups and journal CSV, and previews changes before replacing local data. The JSON archive uses the native app's versioned ledger format; transfer from the iPhone app requires exporting a JSON backup there first. Cross-app restore has not yet been verified on an iPhone.

If an interrupted write leaves a `delve.json.lock` directory, close any other running copy of Delve before removing that directory and retrying. Do not remove the save itself.

Godot's Windows Desktop export preset includes the original dungeon JSON; install Godot export templates before exporting an executable. The Godot port's iOS export, device accessibility, and TestFlight release have not been verified.

## Product direction

Delve is a single-player adventure game about one fixed, handcrafted dungeon. There is no procedural generation and no loot treadmill: the tomb is a puzzle space. The quest UI presents the cryptic quest data without spelling out the route; some challenges only open in a certain order, so the real gameplay loop is *explore → observe → hypothesize → backtrack → try the other route first*. The Godot game presents the journal as a separate screen; the retained native project contains the earlier iPhone Duo layout seam.

## Motivation

Most mobile "dungeon" games are procedural roguelites or gacha loot grinders — no two runs are alike, so nothing you learn transfers, and the meta is monetized. The classic board-game dungeon crawl (and arcade maze-crawler feel) was the opposite: one fixed map, memorized room relationships, secrets gated by *knowledge and order of operations*, and a quest you had to interpret. That design rewards planning and note-taking — exactly what a phone (and later a dual-screen phone with a persistent journal surface) is good at. Delve brings that loop back as an original, offline, one-purchase-style game with zero network dependency.

## Target users

- Players who liked fixed-map exploration puzzles, classic board-game dungeon crawls, and "unlock the sequence" adventure logic.
- Note-takers who keep a scratch map and theories while playing.
- Anyone who wants a substantial offline game for flights and commutes with no accounts, ads, IAP, or data collection.

## Planned product use cases

1. **Session play:** open the app, resume mid-depth on the same dungeon save, push a new wing, find a sealed door that needs a lever pulled three rooms away, jot a clue note, and log out in one tap.
2. **Order-of-operations solving:** hit a blocked goal, form a hypothesis ("the braziers must be lit before the idol moves"), backtrack deliberately, and verify — the game tracks what you've observed so the quest hint state stays honest.
3. **Clue journaling:** pin notes per room ("cracked floor tile east corner"), pin quest-goal progress, and re-read the whole journal at the entrance screen to plan the next run.
4. **Backup:** export a versioned JSON archive of the save + journal, restore it on a new phone with a previewed, confirmed replace.

## How to use (intended end-to-end workflow)

1. Start a new delve from the entrance screen.
2. Explore the fixed map room-by-room with one-thumb movement controls; every room layout is deterministic — nothing reshuffles between visits.
3. Read the vague quest text; goals show only `unknown / in-progress / achieved` states derived from your actual event ledger, never from hidden hints.
4. Open the clue journal: keep free-text notes pinned to rooms and quest-goal checkmarks you own.
5. Pause and resume an active run, or die or retreat — completed run history and journal entries remain in backups.
6. Finish the delve → epilogue screen with your personal run record (steps, sessions, discoveries) derived honestly from the ledger.
7. Export a JSON backup or CSV journal; restore a backup with a previewed replace.

## Planned full MVP feature list

- One handcrafted dungeon: ~40–60 rooms across 3 wings, fixed layout and fixed puzzle placements, original theme and art direction (no third-party IP).
- Deterministic room-state engine: switches, locks, keys, sight-lines, simple enemy patrol patterns; same inputs + same save → identical world state.
- Order-of-operations puzzle core: at least one goal chain where the naive route dead-ends and deliberate backtracking is required (dead-ends are always recoverable, never save-scumming bait).
- Vague quest system: layered goal text with unknown-safe progress states derived only from recorded events.
- Clue journal: per-room pinned notes + quest-goal checkmarks, fully user-owned text.
- One-thumb exploration controls, large touch targets, pause-anywhere, session auto-save.
- Append-only run ledger; resume-after-quit; personal run record with unknown-safe derivation (never counted as zero).
- Versioned JSON backup with previewed restore; CSV journal/quest export.
- Accessibility: labeled controls and keyboard navigation on desktop; device screen-reader and mobile accessibility validation remain outstanding for the Godot port.

## Explicit non-goals

- No procedural generation, no daily-challenge servers, no leaderboards.
- No accounts, cloud sync, analytics, ads, IAP, loot boxes, or energy timers. **Zero network — enforced by CI contract gate.**
- Godot 4 is the game runtime; the original SwiftUI/SpriteKit app is retained separately. No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, or Unity.
- No Android target. The legacy native app is iPhone-only; Godot mobile exports are not yet configured or validated.
- No franchise names, characters, or assets from HeroQuest, Gauntlet, or any other property — original IP only.
- No multiplayer, no AI-generated voice, no camera/microphone permissions.
- Not a game engine, level editor, or mod platform (a future seedable custom-room export is out of MVP scope).

## Privacy, permissions, and data storage

- 100% offline. The app uses no network and requests no permissions.
- The Godot game stores versioned run ledgers and journal entries in a local JSON save, writing a replacement before publishing each change. The retained native app uses GRDB/SQLite. Each has a Your data screen for JSON backup and journal/quest CSV export.
- JSON restore previews changes and requires explicit confirmation; replacement is atomic and rejects stale previews. Archive v1 migrates to v2 defaults; unknown versions fail safely.
- No identifiers, telemetry, or ad SDKs — CI enforces an empty network allowlist.

## Legacy iPhone Duo dual-screen design target

Today: standard iPhone app, iPad support disabled (`TARGETED_DEVICE_FAMILY = 1`, built `UIDeviceFamily == [1]`). The dungeon view and native exploration controls compose through `DelveWorkspaceLayout`; the clue/quest journal is implemented as a sheet routed through that same seam (issue #5); the full contract is `docs/dual-screen-migration.md`. When dual-screen SDK support matures, the migration path is to bind that seam to the second display — dungeon on the primary surface, persistent journal/quest control surface on the companion — with selection/scroll continuity across fold/unfold. No current code depends on unavailable fold APIs.

## Bundle ID & App Store Connect

- Bundle identifier: `com.infinityball.delve` (matches `PRODUCT_BUNDLE_IDENTIFIER`, App Store Connect registered: `CREATED com.infinityball.delve`).
- Implemented release workflow (not yet executed for this worktree): TestFlight via GitHub Actions using the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only — values never logged), ported from the proven fleet template (rwrife/cook-console `release.yml`): `v*` tag or manual dispatch → macos-26 job → iOS 26+ SDK enforcement → signed IPA archive → TestFlight upload via the App Store Connect API → GitHub release.

## Current status and milestones

The Godot project reuses the versioned dungeon and quest files from DelveKit. It implements deterministic movement, keys and locks, location-bound switches, patrol deaths, discoveries, ordered quest evidence, notes, player marks, pause/resume, terminal run records, and backup/restore. Room scenes use original geometric placeholder art. Godot desktop gameplay is separate from the retained native implementation.

Both implementations pin runs to a content version and fingerprint. The Godot game replays its saved ledger, writes accepted events before updating the display, and records patrol contact and death together. Starting a new run preserves the previous run in backup history.

The legacy iPhone app, icon, and release workflow remain in the repository. See [issue #7 validation](docs/issue-7-validation.md) and [the release runbook](docs/release.md) for their native/TestFlight limitations, and [the migration contract](docs/dual-screen-migration.md) for the earlier dual-screen design.

## Development / build quickstart

- Godot 4.4.1: `godot --headless --editor --path . --quit`, then `godot --headless --path . --script res://godot/tests/test_game.gd` and `godot --headless --path . --script res://godot/tests/test_ui.gd`.
- The Godot CI workflow also tests a packed build without the source tree. The game reads the shared content files from `Packages/DelveKit/Sources/DelveKit/Resources`; the Windows export preset includes them.
- `toolchain.json`, `Delve.xcodeproj`, the Swift packages, and the pinned iOS CI describe the retained native app: Xcode 26.0.1 (17A400), iOS SDK 26.0, Swift 6.
- Legacy package tests on Linux/macOS: `swift test --package-path Packages/DelveKit && swift test --package-path Packages/DelveStore`.
- Source gates: `bash scripts/check_zero_network.sh`, `scripts/check_native_only.sh`, and `scripts/check_delvekit_purity.sh`; full native simulator validation uses `Scripts/ci.sh <sha>` on macOS.
- Regenerate the legacy store fixture with `python3 Packages/DelveStore/Tools/regenerate_v1_fixture.py` only after intentional schema migrations.
