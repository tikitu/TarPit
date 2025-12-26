import Testing
import Foundation
import SQLite
import SnapshotTesting
@testable import TarPit

@Suite
final class ListOutputTests {
    let tempDir: URL
    let dbPath: String

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("test.sqlite3").path
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func listOutputFormatting() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        // Insert test data with fixed dates for consistent snapshots
        let testDate1 = Date(timeIntervalSince1970: 1000000000) // 2001-09-09 01:46:40 UTC
        let testDate2 = Date(timeIntervalSince1970: 1500000000) // 2017-07-14 02:40:00 UTC
        let testDate3 = Date(timeIntervalSince1970: 1700000000) // 2023-11-14 22:13:20 UTC

        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "guid1",
            schema.toots.link <- "http://example.com/1",
            schema.toots.pubDate <- testDate1,
            schema.toots.description <- "<p>First toot with <strong>HTML</strong> tags</p>"
        ))

        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "guid2",
            schema.toots.link <- "http://example.com/2",
            schema.toots.pubDate <- testDate2,
            schema.toots.description <- "<p>Second toot with &amp; entities &lt;test&gt;</p>"
        ))

        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "guid3",
            schema.toots.link <- "http://example.com/3",
            schema.toots.pubDate <- testDate3,
            schema.toots.description <- "<p>A very long third toot that should be truncated because it exceeds the maximum character limit we have set for display purposes in our command-line application interface</p>"
        ))

        let list = Script.List()
        let output = try list.formatOutput(dbPath: dbPath, limit: nil, timeZone: TimeZone(identifier: "UTC")!)

        assertSnapshot(of: output, as: .lines)
    }

    @Test func listOutputWithLimit() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        // Insert 5 toots
        for i in 1...5 {
            let testDate = Date(timeIntervalSince1970: TimeInterval(1000000000 + (i * 100000000)))
            try db.run(schema.toots.table.insert(
                schema.toots.guid <- "guid\(i)",
                schema.toots.link <- "http://example.com/\(i)",
                schema.toots.pubDate <- testDate,
                schema.toots.description <- "<p>Toot number \(i)</p>"
            ))
        }

        let list = Script.List()
        let output = try list.formatOutput(dbPath: dbPath, limit: 2, timeZone: TimeZone(identifier: "UTC")!)

        assertSnapshot(of: output, as: .lines)
    }

    @Test func listOutputEmptyDatabase() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        let list = Script.List()
        let output = try list.formatOutput(dbPath: dbPath, limit: nil, timeZone: TimeZone(identifier: "UTC")!)

        assertSnapshot(of: output, as: .lines)
    }
}
