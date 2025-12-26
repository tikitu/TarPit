# TarPit

A CLI tool for archiving a Mastodon RSS feed into a SQLite database.

## Build and Test

```bash
swift build              # Build the project
swift test               # Run all tests
swift test --filter TarPitTests.schemaCreation  # Run a single test
swiftlint lint           # Run linter (CI auto-fixes violations)
```

## Usage

```bash
swift run TarPit init <db-path>                    # Create database
swift run TarPit store <db-path> --url <rss-url>   # Fetch and store toots
swift run TarPit list <db-path> [--limit N]        # List stored toots
```

### Configuration

The database path can be specified in multiple ways, with the following priority order:

1. **Command-line argument** (highest priority): `swift run TarPit init /path/to/db.sqlite`
2. **Environment variable**: `export TAR_PIT_DB_PATH=/path/to/db.sqlite`
3. **Configuration file** (lowest priority): `~/.config/tar_pit/config.yaml`

Example configuration file (`~/.config/tar_pit/config.yaml`):

```yaml
db_path: /path/to/your/database.sqlite
```

If the database path is not specified through any of these methods, the command will fail with an error message.

## Architecture

Single-package CLI using swift-argument-parser.

- **Script** - Main command with subcommands: `init`, `store`, `print`, `list`
- **Schema** - SQLite table definitions (toots, categories, toots-categories join, trace)
- **RSSSource** - Shared argument group for `--url` or `--file` RSS input

## Technology Choices

- **Swift 6.0** with strict concurrency
- **Swift Testing** framework (not XCTest)
- **Snapshot testing** for output verification (`Tests/TarPitTests/__Snapshots__/`)

## CI Environment

GitHub Actions runs tests on Linux (Ubuntu), which may behave differently from local macOS builds. The SwiftLint workflow auto-fixes and commits violations.

To reproduce the CI environment exactly:

```bash
# Clean build directory first (macOS artifacts have different permissions)
rm -rf .build

# Build on Linux
docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 swift build

# Test on Linux
docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 swift test
```

## Swift 6 Considerations

- Use `SQLite.Expression<T>` (fully qualified) to avoid collision with `FoundationEssentials.Expression` on Linux
- Use `static public let configuration` (not `var`) for `ParsableCommand` concurrency safety
