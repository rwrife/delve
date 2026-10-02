/// DelveKit — pure-domain core for Delve.
///
/// M1 ships the skeleton contract: a value-semantics `WorldState` and a
/// deterministic `RuleEngine.step` stub that later milestones extend.
/// M2 replaces the stub with the full rule tables (switch→effect, lock→key,
/// patrol-step transitions) and the append-only `RunLedger`; M3 adds the
/// fixed room graph, the vague `QuestEngine`, and the graph validator.
///
/// This package must never import UIKit, SpriteKit, GRDB, or networking —
/// CI gates (`scripts/check_delvekit_purity.sh`, `scripts/check_zero_network.sh`)
/// keep it Linux-testable and offline by construction.
public enum DelveKit {
    /// Namespace marker for the domain layer.
    public static let domain = "DelveKit"

    /// Current build/CI milestone marker consumed by the app's home screen.
    public static let milestone = "M1-skeleton"
}
