# Delve — PLAN

## Scope

A single-player, offline, fixed-dungeon puzzle-crawler game for iPhone (native Swift). One handcrafted dungeon with deterministic room state, a vague layered quest whose progress is derived only from an append-only event ledger, order-of-operations puzzles requiring deliberate backtracking, and a user-owned clue journal. iPhone Duo dual-screen is a documented design target behind a single layout seam; no fold-SDK dependency. Zero network.

Out of scope: procedural generation, accounts/cloud, IAP/ads, multiplayer, Android, native iPad support, franchise IP, level editor.

## Architecture

```
DelveApp (SwiftUI shell: menus, quest journal, notes, settings)
  └─ DelveScenes (SpriteKit: dungeon room view, movement, actors, effects)
       └─ DelveKit (pure Swift 6 package — no UIKit):
            RoomGraph        fixed room/door topology, wing definitions
            WorldState       flags, keys, puzzle-element state (value semantics)
            RuleEngine       switch→effect, lock→key, patrol-step transitions;
                             deterministic step(world, inputs) -> world'
            QuestEngine      layered goal definitions; unknown-safe progress
                             (unknown | in_progress | achieved) derived ONLY
                             from the event ledger
            RunLedger        append-only events (visit, action, discovery,
                             death, retreat) -> resume + run record
            BackupCodec      versioned JSON archive/restore with preview diff
            CSVExporter      journal + quest progress
       └─ DelveStore (GRDB package): schema migrations, fixture DB,
                        repositories, ledger persistence
       └─ DelveWorkspaceLayout: single layout seam composing dungeon view +
                        journal surface; today a sheet/panel on one screen,
                        future dual-screen migration target
```

Content is data-driven: room graphs and puzzle tables are versioned data files compiled into the bundle; the engine validates every room graph at launch (connectivity, solvability assertions) so content bugs fail fast in tests, not in players' hands.

## Technology choices

| Choice | Rationale |
|---|---|
| SwiftUI + SpriteKit | Apple-first-party only; SpriteKit is the right 2D/2.5D scene engine for room-crawl gameplay; SwiftUI for journal/menus. Prohibited: Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity. |
| Pure-Swift `DelveKit` | Determinism and unknown-safe derivation must be unit-testable on Linux CI without Xcode. |
| GRDB/SQLite | Proven fleet store with versioned migrations + committed fixture DB pattern. |
| Append-only ledger | Resume, run record, and quest progress all recompute from events; no mutable truth to corrupt. |
| Zero network | Privacy posture + CI-enforced empty network allowlist; also the differentiator vs chart-topper crawler bloat. |
| Xcode 26.0.1 (17A400) / iOS SDK 26.0 / Swift 6 | Fleet toolchain pin in `toolchain.json`, asserted by CI. |

## Milestones (dependency order)

1. **M1 — Skeleton + CI** (issue #1): Xcode project, DelveKit/DelveStore packages, pinned macos-26 CI (exact Xcode/SDK assert), iPhone-only gates (`TARGETED_DEVICE_FAMILY = 1`, built `UIDeviceFamily == [1]`), zero-network gate, Linux DelveKit test lane.
2. **M2 — DelveKit core** (issue #2): `WorldState`, `RuleEngine` deterministic step, `RunLedger`, property-style determinism tests (same seed of inputs → identical state), unknown-safe helpers.
3. **M3 — Dungeon content + quest engine** (issue #3): first vertical slice — one wing (~15 rooms) with a complete order-of-operations chain, vague quest layer, graph validator (solvability + no-softlock assertions as tests).
4. **M4 — Exploration UI + clue journal** (issues #4, #5): SpriteKit room view + one-thumb controls; SwiftUI journal (per-room pinned notes, quest-goal checkmarks), run record screen, Dynamic Type/VoiceOver pass.
5. **M5 — Full dungeon + workspace seam** (issue #6): all 3 wings; `DelveWorkspaceLayout` seam + documented iPhone Duo dual-screen migration contract (issue #6 explicitly documents the future API path without depending on it).
6. **M6 — Backup/export** (issue #7): versioned JSON archive, previewed restore, CSV export, Files-app integration.
7. **M7 — Packaging/TestFlight** (issue #8): App Store copy review, generated `AppStore/icon.png` wired into the asset catalog, `.github/workflows/release.yml` ported from the rwrife/cook-console template (`v*` tag / dispatch → macos-26 → iOS 26+ enforcement → signed IPA → TestFlight via ASC API using ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_P8/ASC_TEAM_ID → GitHub release).

## Testing strategy

- **DelveKit (Linux + macOS CI):** determinism (identical replay → identical state), rule-table unit tests, quest unknown-safe derivation, graph validator on every wing, ledger append/resume round-trip, backup codec version matrix + restore preview, CSV golden files.
- **DelveStore (Linux with libsqlite3 + macOS CI):** migrations on committed fixture DB, repository CRUD, ledger persistence.
- **App/UI (macos-26 CI):** build asserts (bundle id, device family [1], SDK), XCUITest journeys (start → move room → note → journal → quit → resume).
- **Zero-network gate:** source+resource grep against empty allowlist.
- Never claim device/TestFlight results without real artifacts.

## Packaging / distribution

Bundle identifier: `com.infinityball.delve` in `PRODUCT_BUNDLE_IDENTIFIER`, Info.plist, and all signing/provisioning configuration — the registered `com.infinityball.` prefix is mandatory and never substituted. TestFlight-first via the fleet release Action; App Store submission only after gameplay-vertical polish. Listing copy lives in `AppStore/description.txt` and must be re-reviewed against implemented features before release. Icon is generated artwork at `AppStore/icon.png` (hermes-image-gen, fleet brief) wired into the Xcode app-icon asset catalog. Single original-IP product, no IAP → simple paid or free tier decided at release time (default: free, no IAP).

## Risks

| Risk | Mitigation |
|---|---|
| Content authoring is the real cost (rooms, puzzles) | Data-driven room graphs + validator tests; ship one wing per milestone. |
| "Vague quest" reads as unfair | Dead-ends always recoverable; journal lets players own their theories; playtest gate on milestone M3 before building wings 2–3. |
| Scope creep toward RPG systems | Non-goals list is the contract; anything not in MVP needs an explicit scope PR. |
| SpriteKit learning curve for executor | Keep scenes thin; all logic in DelveKit where Linux tests catch errors early. |
| Dual-screen SDK never matures | Game is fully valuable single-screen; the seam costs nothing. |

## Explicit non-goals

Same as README: no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, or Unity; no Android; no native iPad support (disabled by default); no procedural generation, accounts, cloud, ads, IAP, or network; no franchise IP.
