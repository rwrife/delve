# Delve workspace migration contract

Today `DelveWorkspaceLayout` (in `App/BootstrapHomeView.swift`) composes three view builders: dungeon, native exploration controls, and journal. Only binding shipped: one iPhone screen, with journal presented as a full-screen cover above the room view. All state belongs to `ExplorationModel` and `DelveStore`, not to a screen or scene.

When a supported dual-screen SDK exists, keep this seam and change its arrangement only. Show dungeon/controls on primary surface and journal on companion surface. Never create a second run, engine, or persistent journal instance. Selection (room ID, quest goal ID, selected note) and journal scroll position must survive fold/unfold and window-size changes. Persist only user-owned notes/marks; presentation selection and scroll offsets remain scene state. Dismissing/reopening the journal must not reset run, ledger, or notes. The same run and pinned `RuleTables` drive both surfaces.

No current code depends on unavailable fold SDK APIs. Do not add compile-time imports, model types, or entitlements from speculative fold SDKs. iPhone-only remains binding (`TARGETED_DEVICE_FAMILY = 1`, built `UIDeviceFamily == [1]`); native iPad support and Android are out of scope absent explicit opt-in. Test migration later with real SDK and device evidence, including selection/scroll continuity across fold transitions.
