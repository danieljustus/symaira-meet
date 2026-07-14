# Agent Instructions — symaira-meet

`symmeet` is a local-first, standalone meeting-artifact tool for macOS 15 and
newer. It stores portable files that users can keep without any Symaira service.

## Build and verification

```bash
swift build
swift test
make lint
.build/debug/symmeet --help
```

## Module boundaries

```text
symmeet executable -> SymMeetMCP -> SymMeetCore
SymMeetAgent -> SymMeetCore
SymDesk -> symmeet runtime JSON contracts
```

- `SymMeetCore` owns contracts, privacy enforcement, artifact storage, and
  processing-independent business logic.
- `SymMeetMCP` is a narrow stdio protocol adapter. It must not import capture
  frameworks and must not write anything except protocol frames to stdout.
- `symmeet` owns human and machine-readable CLI output.

No sibling Symaira repository may be imported. Integrations communicate only
through versioned runtime JSON contracts.

## Privacy and output rules

- Processing is local by default; do not add telemetry, cloud uploads, or
  account requirements.
- A recording start must require a fresh interactive authorization record.
- Never log transcript text, participant names, calendar data, provider keys,
  or absolute user paths.
- JSON output is a single snake_case document on stdout. Progress, warnings,
  and diagnostics go to stderr.

Run the listed verification commands before committing changes.
