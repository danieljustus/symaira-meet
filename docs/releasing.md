# Releasing

## Prerequisites

- macOS 15+ with Xcode or Command Line Tools
- Git with push access to the repository
- A clean working tree on the `main` branch

## Release process

1. Ensure all issues assigned to the milestone are closed or moved.
2. Run the full test suite: `make clean build test lint`
3. Create and push a version tag:
   ```bash
   git tag v0.4.0-beta.1
   git push origin v0.4.0-beta.1
   ```
4. The `release.yml` workflow builds, packages, and creates a GitHub prerelease.
5. Verify the release on GitHub: https://github.com/danieljustus/symaira-meet/releases
6. Smoke-test the published assets on a clean machine:
   ```bash
   scripts/release-smoke.sh dist/
   ```

## Version format

Follows Semantic Versioning: `v<major>.<minor>.<patch>[-<prerelease>]`

The CLI embeds the version via `SYMMEET_VERSION` environment variable.
The `version --json` handshake is the source of truth for consumers:

```json
{"tool":"symmeet","version":"0.4.0-beta.1","schema_version":1}
```

## Required assets

| Asset | Description |
|-------|-------------|
| `symmeet_vVERSION_darwin_arm64.tar.gz` | CLI binary archive |
| `SymMeetAgent_vVERSION.dmg` | Signed/notarized agent app |
| `checksums.txt` | SHA-256 checksums for all assets |

## Signing and notarization

The agent app must be signed with a Developer ID certificate and
notarized via Apple's notary service. The CLI binary uses hardened
runtime but does not require notarization.

Release secrets:
- `APPLE_CERTIFICATE_BASE64`: Base64-encoded .p12 certificate
- `APPLE_CERTIFICATE_PASSWORD`: Certificate password
- `APPLE_ID`: Apple ID for notarization
- `APPLE_TEAM_ID`: Developer team ID
- `APPLE_APP_PASSWORD`: App-specific password for notarization

These are referenced only through GitHub Actions secrets and are never
printed in logs.

## Rollback

If a release has a critical issue:
1. Mark the release as a pre-release on GitHub.
2. Remove the tag: `git push --delete origin vVERSION`
3. Fix the issue and re-release.
