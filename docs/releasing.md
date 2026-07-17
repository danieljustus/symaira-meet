# Releasing

## Prerequisites

- **CLI-only builds**: macOS 15+ with Swift (CLT sufficient)
- **Tests and coverage**: full Xcode required (XCTest is not part of the
  Command Line Tools). CI is the canonical test gate and publishes
  `coverage.lcov` as the `coverage-report` workflow artifact on every run —
  see [Coverage](#coverage)
- **Agent app builds** (CI or local): full Xcode 15+ required (`xcodegen` installed via Homebrew)
- Git with push access to the repository
- A clean working tree on the `main` branch

### Required tools

| Tool | Required for | Notes |
|------|-------------|-------|
| `swift` | CLI build | CLT is sufficient |
| `xcodegen` | Agent build | `brew install xcodegen`; invoked automatically by `package-agent.sh` |
| `xcodebuild` | Agent archive | Full Xcode (not CLT); CI uses default Xcode |
| `hdiutil` | DMG creation | Included with macOS |
| `codesign` | Signing | Only in signed builds |
| `jq` / `python3` | SBOM + smoke | For JSON validation |

## Local dry-run (unsigned)

Produces both artifacts without signing or notarization. Requires full Xcode
for the agent app.

```bash
scripts/build-release.sh --dry-run v0.4.0-beta.1
scripts/release-smoke.sh dist/ v0.4.0-beta.1
(cd dist && shasum -a 256 -c checksums.txt)
```

This creates:

| Artifact | Description |
|----------|-------------|
| `dist/symmeet_v0.4.0-beta.1_darwin_arm64.tar.gz` | CLI binary + LICENSE |
| `dist/SymMeetAgent_v0.4.0-beta.1.dmg` | Unsigned agent app |
| `dist/sbom.spdx.json` | SPDX 2.3 SBOM |
| `dist/symmeet_v0.4.0-beta.1_notices.tar.gz` | Third-party notices |
| `dist/checksums.txt` | SHA-256 checksums for all binary assets |

### Version embedding

The build script writes `Sources/symmeet/Output/EmbeddedRelease.swift` with
the release version, builds the CLI, then **restores the committed nil
default** via a trap. After a dry-run, `git status` should show only
intended changes — `EmbeddedRelease.swift` reverts to `nil`.

The CLI test harness (`SYMMEET_VERSION=0.1.0-test`) continues to work
because `EmbeddedRelease.version` is `nil` in the committed source.

## Signed local build

Set the following environment variables before running without `--dry-run`:

```bash
export APPLE_SIGNING_IDENTITY="Developer ID Application: ..."
export APPLE_CERTIFICATE_BASE64=...   # base64-encoded .p12
export APPLE_CERTIFICATE_PASSWORD=...
export APPLE_ID=...
export APPLE_TEAM_ID=...
export APPLE_APP_PASSWORD=...         # app-specific password
```

```bash
scripts/build-release.sh v0.4.0-beta.1
scripts/release-smoke.sh dist/ v0.4.0-beta.1
```

The signed build additionally runs:

```bash
codesign --verify --deep --strict dist/SymMeetAgent.app
spctl --assess --type execute --verbose dist/SymMeetAgent.app
xcrun stapler validate dist/SymMeetAgent.app
```

## Coverage

CI is the canonical test and coverage gate. Every CI run executes
`swift test --enable-code-coverage` on macos-15 (via `make coverage`) and
uploads `coverage.lcov` as the `coverage-report` workflow artifact (GitHub
Actions → CI → run → Artifacts, retained for 30 days). The prerelease gate
uses this artifact to verify coverage, so no full Xcode install is needed on
the coordinator machine.

Local coverage requires full Xcode (XCTest is not part of the Command Line
Tools; `make test`/`make coverage` fail fast with a clear error on CLT-only
machines):

```bash
make coverage   # runs tests with coverage and writes coverage.lcov
```

## CI tag flow

1. Ensure all issues assigned to the milestone are closed or moved.
2. Run the full test suite: `make clean build test lint`
3. Create and push a version tag:
   ```bash
   git tag v0.4.0-beta.1
   git push origin v0.4.0-beta.1
   ```
4. The `release.yml` workflow:
   - Imports the `.p12` certificate into an ephemeral keychain
   - Runs `scripts/build-release.sh` (signed path)
   - Verifies code signing, notarization, and checksums
   - Creates build provenance attestations
   - Creates a GitHub prerelease with all assets
5. Verify the release on GitHub: https://github.com/danieljustus/symaira-meet/releases
6. Smoke-test the published assets on a clean machine:
   ```bash
   scripts/release-smoke.sh dist/
   ```

## Release assets

| Asset | Description |
|-------|-------------|
| `symmeet_vVERSION_darwin_arm64.tar.gz` | CLI binary + LICENSE |
| `SymMeetAgent_vVERSION.dmg` | Signed/notarized agent app |
| `checksums.txt` | SHA-256 checksums for all binary assets |
| `sbom.spdx.json` | SPDX 2.3 SBOM (deterministic; timestamp pinned to the tag commit) |
| `symmeet_vVERSION_notices.tar.gz` | Third-party licenses + notices |

## Version format

Follows Semantic Versioning: `v<major>.<minor>.<patch>[-<prerelease>]`

The CLI embeds the version at compile time. The `version --json` handshake
is the source of truth for consumers:

```json
{"tool":"symmeet","version":"0.4.0-beta.1","schema_version":1}
```

## Signing and notarization

The agent app must be signed with a Developer ID certificate and
notarized via Apple's notary service. The CLI binary uses hardened
runtime but does not require notarization.

Release secrets (referenced only through GitHub Actions secrets):

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded .p12 certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Certificate password |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_TEAM_ID` | Developer team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

These are never printed in logs. The signing workflow uses `set +x` around
all signing and notarization commands.

## Bundle identifier

The agent app uses the stable bundle identifier `dev.symaira.symmeet.agent`.
This ensures TCC (Transparency, Consent, and Control) permissions persist
across app upgrades — users are not re-prompted for microphone or screen
recording permissions after updating.

## Homebrew

Homebrew tap updates are handled in the
[danieljustus/tap](https://github.com/danieljustus/tap) repository and are
out of scope for this release pipeline.

## Rollback

If a release has a critical issue:
1. Mark the release as a pre-release on GitHub.
2. Remove the tag: `git push --delete origin vVERSION`
3. Fix the issue and re-release.
