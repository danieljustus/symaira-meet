# symaira-meet

`symmeet` is a local-first, standalone command-line tool for durable meeting
artifacts. It runs on macOS 15 or newer (Apple Silicon and Intel) and does not
require another Symaira binary, a cloud account, or telemetry.

> Status: the repository foundation is in place. Audio capture, decoding,
> transcription, model downloads, cloud providers, accounts, and a graphical
> application are deliberately not implemented yet.

## Build

```bash
swift build
swift test
make lint
.build/debug/symmeet --help
```

The binary is named `symmeet`. The initial command tree provides `--help` and a
placeholder `version` command; stable machine-readable commands are documented
as they become available.

## Design principles

- Local-first: meeting content stays on the device by default.
- Standalone-first: artifacts are portable files, not records in a proprietary
  database.
- Contract-first: integrations use versioned, snake_case JSON at runtime.
- Privacy by design: future recording requires fresh, interactive authorization.

## License

Apache-2.0. See [LICENSE](LICENSE).
