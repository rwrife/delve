# Issue #4 worktree validation

Implemented exploration of bundled wing one through existing DelveKit APIs, with native SwiftUI controls and SpriteKit original geometric placeholder scenes. `DelveWorkspaceLayout` is the single composition seam; no journal UI is implemented. Durable actions publish their candidate world only after transaction success. Background saves pause after successful persistence. New-start failures retain the active run; contact death and retreat clear only the active pointer and preserve immutable historical data.

Store v2 leaves the committed v1 fixture and its historical rows unchanged. Legacy rows without canonical ledger metadata are not offered for resume. New ledgers are content-pinned, replayed in insertion order, and strictly decoded; snapshots are a cache. There is no fabricated death command in the app: movement into actual engine patrol contact automatically records the engine-accepted death within the same transaction.

## Commands and results (Linux, 2026-10-06)

Run from `/home/rwrife/repos/delve-issue-4`:

```bash
docker run --rm -v "$PWD:/src:ro" swift:6.2-noble bash -lc 'export HOME=/tmp/delve-home; mkdir -p "$HOME"; apt-get update -qq && apt-get install -y -qq libsqlite3-dev >/dev/null && swift test --package-path /src/Packages/DelveKit --scratch-path /tmp/delve-kit && swift test --package-path /src/Packages/DelveStore --scratch-path /tmp/delve-store' > /tmp/delve-packages-test.log 2>&1
```

DelveKit: 40 tests passed. The initial added store death-route test failed because the selected room visit was safe at that patrol step; the route was corrected to reach genuine contact. No engine rule was changed.

Final store validation, including an added death-insertion rollback check:

```bash
docker run --name delve-issue4-validation -v "$PWD:/src:ro" swift:6.2-noble bash -lc 'export HOME=/tmp/delve-home; mkdir -p "$HOME"; apt-get update -qq && apt-get install -y -qq libsqlite3-dev >/dev/null && swift test --package-path /src/Packages/DelveStore --scratch-path /tmp/delve-store' > /tmp/delve-store-final.log 2>&1
docker start -a delve-issue4-validation > /tmp/delve-store-final.log 2>&1
```

Final result: 12 tests passed. Coverage includes persistent reopen/replay, ignoring stale snapshots, invalid/unknown events, content mismatch, rejected/stale commands, ledger/snapshot rollback, failed new start, save failure, immutable terminal history, and atomic movement/death rollback.

```bash
bash scripts/check_zero_network.sh
bash scripts/check_native_only.sh
bash scripts/check_delvekit_purity.sh
python3 -m unittest discover -s Scripts/tests -v
bash -n Scripts/ci.sh scripts/*.sh
git diff --check
docker run --rm -v "$PWD:/src:ro" swift:6.2-noble bash -lc 'swiftc -frontend -parse /src/App/DelveApp.swift /src/App/BootstrapHomeView.swift && swiftc -frontend -parse /src/UITests/DelveLaunchTests.swift'
```

All passed; Python: 21 tests. App/UI sources passed syntax parsing only. The source mount was read-only, all Swift scratch products and dependency checkouts stayed under container `/tmp`, and HOME was set only inside containers.

## Native verification outstanding

Xcode and Apple SDKs are unavailable on this Linux host. Native compilation and all XCUITest execution are CI-only and **unverified** here. Pinned `Scripts/ci.sh` on the macos-26 lane builds the target, executes UI tests, and verifies the built bundle identifier and iPhone-only device family. The updated journeys cover movement, puzzle/discovery interaction, pause, background auto-save, quit/relaunch resume, retreat, key pickup/locked movement, hit target sizes, and real patrol-contact death. VoiceOver and large Dynamic Type device behavior still need native validation. No TestFlight or release artifact is claimed.

No commits, pushes, PR creation, GitHub writes, icon assets, release workflow, or issue #5 journal changes were made.

## Changed files

- `App/BootstrapHomeView.swift`: model, entrance, workspace seam, scene, HUD and controls.
- `App/DelveApp.swift`: exploration app entry point with recoverable initialization in the model.
- `Packages/DelveStore/Sources/DelveStore/DelveStore.swift`: v2 migration and history guards.
- `Packages/DelveStore/Sources/DelveStore/RunRepository.swift`: persistent run APIs and atomic replay-backed transactions.
- `Packages/DelveStore/Tests/DelveStoreTests/DelveStoreTests.swift`: v2 migration assertions.
- `Packages/DelveStore/Tests/DelveStoreTests/RunRepositoryTests.swift`: replay, transaction and terminal tests.
- `UITests/DelveLaunchTests.swift`: exploration journeys and quit/relaunch resume.
- `Scripts/ci.sh`: native lane also runs purity/native-only gates.
- `.github/workflows/ci.yml`: updated purity-gate description.
- `scripts/check_delvekit_purity.sh`: additionally rejects SwiftUI/AppKit imports.
- `README.md` and `AppStore/description.txt`: distinguish implemented and planned features.
- `docs/issue-4-validation.md`: exact command/result and changed-file report.

The Xcode project already includes both app files and the existing UI-test file, and links both local packages. No project wiring change was necessary. All six explicit device-family configurations remain `TARGETED_DEVICE_FAMILY = 1`; the app bundle remains `com.infinityball.delve`; `network_allowlist` remains `[]`.
