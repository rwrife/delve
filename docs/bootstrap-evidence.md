# Bootstrap evidence (issue #1)

Milestone M1 landed the buildable skeleton and both CI lanes. This page keeps
the evidence tiers strictly separate: what was executed on the Linux executor
host, versus what only the pinned native lanes can prove.

## Executed on the Linux host (real tool output, 2026-10-02)

Executed in `gamecrate-swift-sqlite:latest` (Swift 6.2.4,
aarch64-unknown-linux-gnu, libsqlite3 present) — the same engine class as the
CI Linux job (`swift:6.2-noble` + libsqlite3-dev):

```
swift test --package-path Packages/DelveKit
  → Test run with 4 tests in 2 suites passed
swift test --package-path Packages/DelveStore
  → Test run with 6 tests in 0 suites passed   (includes the committed
     v1 fixture read-back through DelveStore + DelveKit WorldState decode)
```

Executed directly on the host:

- `python3 -m unittest discover -s Scripts/tests` → 21 tests, OK
  (pin selection, simulator selection retry/flush, bounded boot retry,
  real-subprocess timeout behavior)
- `bash scripts/check_zero_network.sh` → PASS (empty allowlist; also asserts
  `toolchain.json network_allowlist == []`)
- `bash scripts/check_native_only.sh` → PASS (no Flutter/RN/Expo/KMP/MAUI/Unity)
- `bash scripts/check_delvekit_purity.sh` → PASS (no UIKit/SpriteKit/GRDB imports)
- `bash -n Scripts/ci.sh`; `ci.yml` YAML parse; `toolchain.json` JSON parse → OK
- `grep TARGETED_DEVICE_FAMILY` inventory: 6 occurrences, all exactly `= 1`,
  zero `1,2` / `2` (project + app + UI-test configurations)
- Fixture regeneration determinism: `regenerate_v1_fixture.py` run twice →
  byte-identical `v1.sqlite` (`cmp` clean; sha256 0159b05247241c23…)
- `swiftc -parse` on `App/*.swift` and `UITests/DelveLaunchTests.swift`:
  syntax only — **not** a build (Apple SDK types are absent on Linux)

## Pending — only the CI lanes can produce this evidence

- Linux CI job (swift:6.2-noble + libsqlite3-dev) — expected to mirror the
  host runs above exactly.
- macos-26 pinned lane (Scripts/ci.sh): exact Xcode 26.0.1 / 17A400 /
  iPhoneOS SDK 26.0 measurement (missing pin = acceptance blocker),
  exact-runtime install + deterministic iPhone creation, bounded simulator
  boot, Debug simulator build, launch XCUITest (`bootstrap.home`),
  post-build `plutil` assertions on the built app:
  `UIDeviceFamily == [1]` and `CFBundleIdentifier == com.infinityball.delve`.

No Xcode build, simulator boot, UI test, signing, or TestFlight result is
claimed from this host — none is possible here. See the PR's CI run for the
native evidence once green.
