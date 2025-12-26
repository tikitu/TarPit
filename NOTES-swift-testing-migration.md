# Swift Testing Migration Notes

This document summarizes the changes made to migrate from XCTest to Swift Testing, and the issues encountered along the way.

## Summary of Changes

### 1. Convert Tests from XCTest to Swift Testing

**Files changed:** `Tests/TarPitTests/TarPitTests.swift`, `Tests/TarPitTests/ListOutputTests.swift`

- Changed `import XCTest` to `import Testing`
- Added `@Suite` attribute to test classes
- Converted `setUp()` to throwing `init()` - this eliminates the need for `try!` (which was causing SwiftLint violations)
- Converted `tearDown()` to `deinit`
- Added `@Test` attribute to all test methods and removed "test" prefix from method names
- Replaced `XCTAssert*` with `#expect` macros
- Replaced `XCTAssertThrowsError` with `#expect(throws:)`
- Replaced `XCTAssertNoThrow` by just calling the throwing code directly (test will fail if it throws)

### 2. Update Package.swift for Swift 6.0

- Changed `swift-tools-version` from `5.7` to `6.0` (required for Swift Testing)
- Added `resources: [.copy("__Snapshots__")]` to test target (fixes warning about unhandled snapshot files)

### 3. Update GitHub Actions Workflow

**File:** `.github/workflows/test.yml`

- Changed Swift version from `5.10` to `6.0`

### 4. Update Dependencies

- `swift-argument-parser`: `1.2.0` → `1.5.0` (for Swift 6 Sendable conformance)
- `SQLite.swift`: `0.14.1` → `0.15.0` (for Swift 6 compatibility)

### 5. Swift 6 Concurrency Fixes

**File:** `Sources/TarPit/TarPit.swift`

- Changed `static public var configuration` to `static public let configuration` for all `ParsableCommand` structs (Swift 6 requires this for concurrency safety)

### 6. Fix SQLite.Expression Type Collision (Linux-specific)

**Root cause:** On Linux with Swift 6.0, `SQLite.Expression` collides with `FoundationEssentials.Expression` (the new Predicate expression type from iOS 17/macOS 14). This caused the compiler to incorrectly require a `value:` label when creating column expressions.

**Solution:**
- Added a helper function to create column expressions explicitly:
  ```swift
  func col<T>(_ name: String) -> SQLite.Expression<T> {
      SQLite.Expression<T>(literal: "\"\(name)\"")
  }
  ```
- Fully qualified all `Expression` type annotations as `SQLite.Expression`

### 7. Snapshot File Renaming

When test method names changed (removed "test" prefix), snapshot files needed to be renamed to match:
- `testListOutputFormatting.1.txt` → `listOutputFormatting.1.txt`
- `testListOutputWithLimit.1.txt` → `listOutputWithLimit.1.txt`
- `testListOutputEmptyDatabase.1.txt` → `listOutputEmptyDatabase.1.txt`

---

## Red Herrings

### 1. `@preconcurrency import ArgumentParser`

**What we tried:** Adding `@preconcurrency` to the ArgumentParser import to suppress Swift 6 concurrency warnings.

**Why it wasn't the solution:** The actual fix was to update swift-argument-parser to version 1.5.0+, which has proper Sendable conformance. The `@preconcurrency` workaround was unnecessary with the updated dependency.

### 2. `swiftLanguageModes: [.v5]` in Package.swift

**What we tried:** Setting Swift 5 language mode while using Swift 6.0 tools, hoping to avoid the breaking changes.

**Why it wasn't the solution:** The Expression type collision is a cross-module issue that occurs regardless of language mode. The real fix was to fully qualify the type as `SQLite.Expression`.

### 3. Adding `init(column:)` extension to Expression

**What we tried:** Adding an extension initializer `init(column name: String)` to Expression.

**Why it wasn't the solution:** The Swift 6.0 compiler on Linux still preferred the existing `init(value:)` initializer over our extension initializer. A free function (`col()`) worked better because it doesn't compete with the type's own initializers.

### 4. Using `init(value:)` with the column name string

**What we tried:** Changing `Expression<Int64>("id")` to `Expression<Int64>(value: "id")`.

**Why it wasn't the solution:** The `init(value:)` initializer expects an actual value of the underlying type (e.g., `Int64`), not a column name string. The column name initializer is `init(_ identifier: String)` or `init(literal:)`.

---

## Testing Locally with Docker

To reproduce the Linux environment locally:

```bash
# Clean build directory first (macOS build artifacts have different permissions)
rm -rf .build

# Run build
docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 swift build

# Run tests
docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 swift test
```

**Note:** Snapshot tests may fail on Linux due to timezone differences in date formatting. This is a pre-existing issue unrelated to the Swift 6.0 migration.
