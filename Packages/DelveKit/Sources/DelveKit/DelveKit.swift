/// DelveKit — pure-domain core for Delve.
///
/// M2 ships the deterministic simulation core: value-semantics `WorldState`,
/// table-driven `RuleEngine.step` (switch→effect, lock→key, patrol-step
/// transitions), append-only `RunLedger` with exact `resume`, and the
/// canonical `WorldCodec`/`EventCodec` byte-stable encodings. M3 adds the
/// external room-graph files, the graph validator, and the vague
/// `QuestEngine`.
///
/// This package must never import UIKit, SpriteKit, GRDB, or networking —
/// CI gates (`scripts/check_delvekit_purity.sh`, `scripts/check_zero_network.sh`)
/// keep it Linux-testable and offline by construction.
public enum DelveKit {
    /// Namespace marker for the domain layer.
    public static let domain = "DelveKit"

    /// Current build/CI milestone marker consumed by the app's home screen.
    public static let milestone = "M2-engine"
}
