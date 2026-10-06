# Delve

**An offline iPhone fixed-dungeon puzzle crawler. The current slice explores wing one; the clue journal and full product features below are planned.**

## Product direction

Delve is a single-player adventure game about one fixed, handcrafted dungeon. There is no procedural generation and no loot treadmill: the tomb is a puzzle space. The planned quest UI will present the existing cryptic quest data without spelling out the route; some challenges only open in a certain order, so the real gameplay loop is *explore → observe → hypothesize → backtrack → try the other route first*. A dual-screen battle-style layout (dungeon view on one surface, persistent quest/clue journal as the companion surface) is the iPhone Duo design target, targeted through a workspace-layout seam; the journal and dual-screen integration are planned.

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

1. Start a new delve from the entrance screen; pick a hero name (purely cosmetic, stored locally).
2. Explore the fixed map room-by-room with one-thumb movement controls; every room layout is deterministic — nothing reshuffles between visits.
3. Read the vague quest text; goals show only `unknown / in-progress / achieved` states derived from your actual event ledger, never from hidden hints.
4. Keep the clue journal open as a companion sheet (today) / companion screen (iPhone Duo design target): free-text notes pinned to rooms, quest-goal checkmarks you own.
5. Die or retreat — progress that matters (visited rooms, flags, notes, achieved goals) persists; the run state machine is append-only and resumable.
6. Finish the delve → epilogue screen with your personal run record (steps, sessions, discoveries) derived honestly from the ledger.
7. Back up via Files-app JSON export; restore with previewed replace.

## Planned full MVP feature list

- One handcrafted dungeon: ~40–60 rooms across 3 wings, fixed layout and fixed puzzle placements, original theme and art direction (no third-party IP).
- Deterministic room-state engine: switches, locks, keys, sight-lines, simple enemy patrol patterns; same inputs + same save → identical world state.
- Order-of-operations puzzle core: at least one goal chain where the naive route dead-ends and deliberate backtracking is required (dead-ends are always recoverable, never save-scumming bait).
- Vague quest system: layered goal text with unknown-safe progress states derived only from recorded events.
- Clue journal: per-room pinned notes + quest-goal checkmarks, fully user-owned text.
- One-thumb exploration controls, large touch targets, pause-anywhere, session auto-save.
- Append-only run ledger; resume-after-quit; personal run record with unknown-safe derivation (never counted as zero).
- Versioned JSON backup with previewed restore; CSV journal/quest export.
- Accessibility: Dynamic Type on all journal/menu text, VoiceOver labels on controls, colorblind-safe state glyphs, haptics-optional.

## Explicit non-goals

- No procedural generation, no daily-challenge servers, no leaderboards.
- No accounts, cloud sync, analytics, ads, IAP, loot boxes, or energy timers. **Zero network — enforced by CI contract gate.**
- No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, or Unity; no other cross-platform/hybrid framework. Native Swift (SwiftUI + SpriteKit) only.
- No Android target and no native iPad support (iPhone-only; iPad requires explicit user opt-in).
- No franchise names, characters, or assets from HeroQuest, Gauntlet, or any other property — original IP only.
- No multiplayer, no AI-generated voice, no camera/microphone permissions.
- Not a game engine, level editor, or mod platform (a future seedable custom-room export is out of MVP scope).

## Privacy, permissions, and data storage

- 100% offline. The app uses no network and requests no permissions.
- Implemented run state and ledger records live in a local GRDB/SQLite store inside the app container. The implemented app has no export path; Files-app exports are planned.
- Planned exports are JSON/CSV with previewed restore.
- No identifiers, telemetry, or ad SDKs — CI enforces an empty network allowlist.

## iPhone Duo dual-screen design target

Today: standard iPhone app, iPad support disabled (`TARGETED_DEVICE_FAMILY = 1`, built `UIDeviceFamily == [1]`). The dungeon view and native exploration controls compose through `DelveWorkspaceLayout`; the clue/quest journal is planned in issue #5. When dual-screen SDK support matures, the migration path is to bind that seam to the second display — dungeon on the primary surface, persistent journal/quest control surface on the companion — with selection/scroll continuity across fold/unfold. No current code depends on unavailable fold APIs.

## Bundle ID & App Store Connect

- Bundle identifier: `com.infinityball.delve` (matches `PRODUCT_BUNDLE_IDENTIFIER`, App Store Connect registered: `CREATED com.infinityball.delve`).
- Planned release path (not implemented): TestFlight via GitHub Actions using the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only — values never logged), ported from the proven fleet template (rwrife/cook-console `release.yml`): `v*` tag or manual dispatch → macos-26 job → iOS 26+ SDK enforcement → signed IPA archive → TestFlight upload via the App Store Connect API → GitHub release.

## Current status and milestones

Implemented in the worktree: the deterministic DelveKit engine and validated 15-room wing one; ledger-derived quest APIs; SwiftUI entrance, new delve/resume, room movement, puzzle toggles, discoveries, automatic key pickup, pause, and retreat; a SpriteKit scene using clearly labeled original geometric placeholder art. Native controls have at least 56-point targets, Dynamic Type HUD text, VoiceOver labels, and text/glyph state indicators. `DelveWorkspaceLayout` composes the scene and controls without implementing the issue #5 journal.

DelveStore v2 adds content-pinned replay, atomic event/snapshot writes, an active-run pointer, and immutable terminal history. Every accepted action is saved before visible world state changes; backgrounding saves and pauses. Actual engine patrol contact records death atomically with movement and returns to the entrance, as does retreat. New starts preserve earlier runs and only replace the active pointer after a successful transaction. Legacy v1 fixture rows remain intact but are not offered as resumable runs because they lack canonical replay metadata.

Journal UI, run record UI, further wings, backup/export, cosmetic hero naming, epilogue, icon, release workflow, and dual-screen integration are planned. Linux package tests and local source gates can run here; native compilation, simulator journeys, VoiceOver behavior, and device accessibility still require the pinned macOS CI/device validation. No native result is claimed from this Linux worktree.

## Development / build quickstart

- Xcode 26.0.1 (17A400), iOS SDK 26.0, Swift 6 mode (see `toolchain.json`; enforced by native CI).
- App shell: SwiftUI; scenes: SpriteKit (from issue #4); pure game domain in `Packages/DelveKit` (Linux-testable), store in `Packages/DelveStore` (GRDB, needs libsqlite3 on Linux).
- Package tests on Linux/macOS: `swift test --package-path Packages/DelveKit && swift test --package-path Packages/DelveStore`.
- Gates: `bash scripts/check_zero_network.sh`, `scripts/check_native_only.sh`, `scripts/check_delvekit_purity.sh`; full simulator validation via `Scripts/ci.sh <sha>` (macOS only).
- Regenerate the store fixture: `python3 Packages/DelveStore/Tools/regenerate_v1_fixture.py` (byte-reproducible; commit the result only after intentional schema migrations).
- All gameplay content ships as data files (room graphs, puzzle tables) compiled into the app bundle — no downloads.
