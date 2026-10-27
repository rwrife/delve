# Issue 7 implementation and validation

Work is confined to the isolated `delve-issue7` worktree. Native CI and
TestFlight evidence must be recorded from actual runs; local Linux checks do not
prove signing, simulator behavior, or upload.

## Data contract

`DelveKit.BackupCodec` exports JSON v2. It contains all recorded run ledgers
(including terminal and superseded runs), the active run identity, per-run room
notes and player quest marks, and settings. Snapshots and engine progress are
recomputed from ledgers, never trusted from an imported file. Database row IDs,
internal timestamps, and the constant hero label are not portable save facts.
Archive v1 has the same runs/active identity but no settings; importing it adds
current default settings. Versions outside 1–2 fail closed. The test matrix covers
content v1, v2, and v3, preserving each ledger's exact version and fingerprint.
Current app runs use bundled content v2/v3. Old unpinned database rows cannot be
safely replayed: export/restore refuses those stores instead of omitting history.

Import is limited to 32 MiB and validates IDs, sequences, canonical events,
content fingerprints, legal replay, notes, marks, and active-run identity before
showing the diff. Preview shows added/removed/changed/unchanged run identities,
event/note/mark totals, active slot changes, and settings changes. Confirmation
is required by both the UI and store API. The store compares the current data
with the preview baseline inside the same GRDB write transaction as replacement.
A stale preview requires another review. Only the known history guards are
removed during replacement; their SQL is reinstated inside the transaction.
SQLite rolls back data and guard DDL together if anything fails. Other triggers
remain in force. Direct ledger/history mutation remains prohibited afterward.

Entrance and exploration toolbars expose **Your data**. Prepare JSON or CSV,
then use ShareLink or the Files exporter. CSV uses RFC 4180 quoting and CRLF,
preserves Unicode/multiline notes, neutralizes formula prefixes, and keeps player
marks separate from engine-derived quest progress. Content v1 had no quest text,
so it emits notes without invented quest rows. The persisted setting controls
confirmation before superseding an active run; it defaults to enabled. Restore
confirmation is always mandatory. All application data operations are local.

## Icon

The supplied genuine generated image was copied unchanged from
`/home/rwrife/media/delve/images/20261025T152414Z_openai_63ebb1.png` to
`AppStore/icon.png` and `App/Assets.xcassets/AppIcon.appiconset/icon.png`.
Pillow inspection: **1024 × 1024, RGB, no alpha channel**. Visual inspection:
edge-to-edge illustration, square edges, no text, border, or baked corner mask.
All three SHA-256 values are:

```
5e2977abdca0f038e4627a51918183b1b1173d26bbff956c1bf57b1a7806215e
```

The original remains unchanged. The catalog is in the app Resources build phase;
both app configurations select `AppIcon`. Native CI and release now invoke
`Scripts/verify_app.py` on the built app to require bundle identity,
`UIDeviceFamily == [1]`, primary `AppIcon` metadata, and nonempty `Assets.car`.
**Actual actool compilation evidence is pending macOS; no local asset build is claimed.**

## Release pipeline

`.github/workflows/release.yml` is ported from the requested cook-console file;
`Tools/asc_jwt.rb` is copied from its dependency-free signing helper. It retains
macos-26, tag/manual triggers, four ASC secrets, private mode-600 key installation,
automatic signing and App Store Connect upload through xcodebuild, refreshed JWT
polling, terminal processing gate, cleanup, and GitHub release creation. Delve
adds exact Xcode 26.0.1 / 17A400 / SDK 26.0 selection, native/offline gates, signed
Release configuration, and built iPhone/bundle/icon validation. `VERSION` is
0.1.0; the release tag must match it and point at the checked-out commit. Manual
runs require that existing tag too. No project regeneration is needed.

The poll uses curl `--globoff` for ASC bracket filters, filters by build number,
parses TSV using a literal tab separator, and fails immediately on FAILED/INVALID.
Success writes ASC build ID/state to the Actions summary and artifact before
creating a GitHub release. A fresh dispatch gets a fresh build number; rerunning
a previously uploaded run cannot reuse its number. The template's optional beta
group mutation is omitted; processed build registration gates the release.
Secret values are never printed. GitHub API inspection confirmed these names:
ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID. Values were not accessed.

## Local verification and acceptance limits

Docker image `delve-swift-noble:latest` supplies Swift 6.2.4 and SQLite headers.
Full results: **50 DelveKit tests (46 Swift Testing + 4 XCTest), 22 DelveStore tests (16 Swift Testing + 6 XCTest), and 22 Python helper tests pass**. Logs are in ignored `build/`. The OpenStep Xcode project also opens successfully with the Ruby xcodeproj parser; the new Swift source and asset catalog resolve in their intended build phases.
The new tests cover migration/version/content combinations, invalid archives,
illegal/corrupt events, Unicode/CSV quoting and formula handling, explicit
confirmation, stale journal/settings/ledger previews, mixed-version terminal
history, successful replacement, reopen persistence, empty replacement, unpinned
legacy rejection, and injected mid-restore rollback with guards preserved.
Architecture gates and release actionlint pass. The Ruby helper passes `ruby -c`
in Docker. App Swift sources pass syntax parsing in Docker; this does not
substitute for SwiftUI type checking against an iOS SDK.

The exact local toolchain probe fails on Linux because Xcode is macOS-only:

```
$ python3 Scripts/select_xcode.py --toolchain toolchain.json
No installed Xcode matches ('26.0.1', '17A400', '26.0'); observed: none
(exit 1)
$ xcodebuild -version
/bin/bash: line 1: xcodebuild: command not found
(exit 127)
```

The corresponding release step is **Select exact pinned Xcode and SDK**. This is
local environment output, not a fabricated Actions failure. Signed archive, real catalog
compilation, iPhone simulator/UI verification, TestFlight upload, ASC terminal
build ID, and GitHub release require GitHub Actions runner execution on macos-26.
An unverified milestone cannot close issue #7 without real execution evidence.
