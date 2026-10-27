# Delve release runbook

Do not claim a TestFlight result until an Actions run records a processed ASC
build ID. See [validation and exact local blocker output](issue-7-validation.md).

The release workflow is ported from rwrife/cook-console. It requires these four
repository secret names: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`.
The key must authorize automatic provisioning and uploading for the registered
`com.infinityball.delve` app. Do not log secret values or add signing material.

For a future authorized release:

1. Run both Swift packages, architecture gates, and pinned simulator CI. Review
   App Store copy and obtain compiled icon evidence from the native CI artifact.
2. Keep `VERSION` and the app's `MARKETING_VERSION` aligned. The current version
   is `0.1.0`. The workflow uses the Actions run number as the ASC build number.
3. Release only committed, reviewed code. A `v<version>` tag triggers the workflow;
   manual dispatch requires that tag already exists and points to the selected
   commit. This prevents a manual branch run from releasing unrelated code.
4. The runner must have exactly Xcode 26.0.1 / 17A400 and iPhoneOS SDK 26.0.
   Missing pins are blockers; never silently substitute a newer SDK.
5. The job archives with automatic ASC signing, validates the archived bundle
   and compiled icon, exports/uploads with xcodebuild, then polls ASC. It accepts
   VALID/COMPLETE and fails on INVALID/FAILED or timeout. The GitHub release is
   created only after processing succeeds. The job summary and status artifact
   record the build ID and terminal state. It does not submit an App Store review
   or configure beta tester groups.
6. Record the real run URL, ASC build ID and terminal state in the issue before
   declaring the TestFlight gate complete. If a step fails, preserve its exact
   output, omitting all credentials. A successful upload followed by another
   failure may require a fresh dispatch/build number; ASC will not reuse one.

Signing keys are written with mode 600 under runner temp and removed in an
`always()` step. GitHub's automatic secret masking supplements avoiding secret
output. Do not enable shell tracing around credentials or JWTs.
