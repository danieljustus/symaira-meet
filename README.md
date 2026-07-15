# symaira-meet

[![CI](https://github.com/danieljustus/symaira-meet/actions/workflows/ci.yml/badge.svg)](https://github.com/danieljustus/symaira-meet/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/danieljustus/symaira-meet)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/danieljustus/symaira-meet)](https://github.com/danieljustus/symaira-meet/releases/latest)

`symmeet` is a local-first, standalone command-line tool for durable meeting
artifacts. It runs on macOS 15 or newer (Apple Silicon and Intel) and does not
require another Symaira binary, a cloud account, or telemetry.

> Status: the repository foundation is in place. Audio capture, decoding,
> transcription, model downloads, cloud providers, accounts, and a graphical
> application are deliberately not implemented yet.

## Install

Build from source requires Swift 6.0+ and macOS 15 or newer:

```bash
git clone https://github.com/danieljustus/symaira-meet.git
cd symaira-meet
swift build -c release
cp .build/release/symmeet /usr/local/bin/
```

## Build

```bash
swift build
swift test
make lint
.build/debug/symmeet --help
```

The binary is named `symmeet`. Every `--json` command writes exactly one
snake_case JSON document to stdout; diagnostics stay on stderr.

## CLI

```text
symmeet version [--json]
symmeet doctor [--json]
symmeet config path [--json]
symmeet meeting list [--json]
symmeet meeting show <meeting_id> [--json]
symmeet meeting trash <meeting_id> [--json]
symmeet meeting restore <meeting_id> [--json]
symmeet completion <bash|fish|zsh>
```

Exit codes: `0` success, `1` runtime failure, `2` invalid input or
configuration, `3` permission denied, and `4` unsupported operation. The
stable `version --json` handshake is:

```json
{"tool":"symmeet","version":"...","schema_version":1}
```

## Why symmeet

- Local-first: meeting content stays on the device by default.
- Standalone-first: artifacts are portable files, not records in a proprietary
  database.
- Contract-first: integrations use versioned, snake_case JSON at runtime.
- Privacy by design: future recording requires fresh, interactive authorization.

## License

Apache-2.0. See [LICENSE](LICENSE).
