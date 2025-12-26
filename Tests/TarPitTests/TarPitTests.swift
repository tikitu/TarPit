import Testing
import Foundation
import SQLite
@testable import TarPit

@Suite
final class TarPitTests {
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

    @Test func schemaCreation() throws {
        let db = try Connection(dbPath)
        let schema = Schema()

        try schema.create(db: db)

        // Verify tables exist by querying them
        _ = try db.prepare(schema.toots.table)
        _ = try db.prepare(schema.categories.table)
        _ = try db.prepare(schema.tootsCategories.table)
        _ = try db.prepare(schema.trace.table)
    }

    @Test func insertAndRetrieveToots() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        // Insert test data
        let testDate1 = Date(timeIntervalSince1970: 1000000000)
        let testDate2 = Date(timeIntervalSince1970: 2000000000)
        let testDate3 = Date(timeIntervalSince1970: 3000000000)

        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "guid1",
            schema.toots.link <- "http://example.com/1",
            schema.toots.pubDate <- testDate1,
            schema.toots.description <- "<p>First toot</p>"
        ))

        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "guid2",
            schema.toots.link <- "http://example.com/2",
            schema.toots.pubDate <- testDate2,
            schema.toots.description <- "<p>Second toot</p>"
        ))

        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "guid3",
            schema.toots.link <- "http://example.com/3",
            schema.toots.pubDate <- testDate3,
            schema.toots.description <- "<p>Third toot with a very long description that should be truncated when displayed</p>"
        ))

        // Query toots ordered by date descending
        let query = schema.toots.table.order(schema.toots.pubDate.desc)
        let rows = Array(try db.prepare(query))

        #expect(rows.count == 3)
        #expect(try rows[0].get(schema.toots.guid) == "guid3")
        #expect(try rows[1].get(schema.toots.guid) == "guid2")
        #expect(try rows[2].get(schema.toots.guid) == "guid1")
    }

    @Test func queryWithLimit() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        // Insert test data
        for i in 1...10 {
            let testDate = Date(timeIntervalSince1970: TimeInterval(i * 1000000))
            try db.run(schema.toots.table.insert(
                schema.toots.guid <- "guid\(i)",
                schema.toots.link <- "http://example.com/\(i)",
                schema.toots.pubDate <- testDate,
                schema.toots.description <- "<p>Toot \(i)</p>"
            ))
        }

        // Query with limit
        let query = schema.toots.table.order(schema.toots.pubDate.desc).limit(5)
        let rows = Array(try db.prepare(query))

        #expect(rows.count == 5)
        // Should get the 5 most recent (guid10, guid9, guid8, guid7, guid6)
        #expect(try rows[0].get(schema.toots.guid) == "guid10")
        #expect(try rows[4].get(schema.toots.guid) == "guid6")
    }

    @Test func duplicateGuidPrevention() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        let testDate = Date()

        // Insert first toot
        try db.run(schema.toots.table.insert(
            schema.toots.guid <- "duplicate-guid",
            schema.toots.link <- "http://example.com/1",
            schema.toots.pubDate <- testDate,
            schema.toots.description <- "<p>First</p>"
        ))

        // Try to insert duplicate - should fail
        #expect(throws: Error.self) {
            try db.run(schema.toots.table.insert(
                or: .abort,
                schema.toots.guid <- "duplicate-guid",
                schema.toots.link <- "http://example.com/2",
                schema.toots.pubDate <- testDate,
                schema.toots.description <- "<p>Second</p>"
            ))
        }
    }

    @Test func htmlStripping() throws {
        let list = Script.List()

        #expect(list.stripHTML("<p>Hello world</p>") == "Hello world")
        #expect(list.stripHTML("<p>Hello&nbsp;world</p>") == "Hello world")
        #expect(list.stripHTML("<p>Hello &amp; goodbye</p>") == "Hello & goodbye")
        #expect(list.stripHTML("<p>Test &lt;tag&gt;</p>") == "Test <tag>")
        #expect(list.stripHTML("<p>&quot;quoted&quot;</p>") == "\"quoted\"")
        #expect(list.stripHTML("<p>&#39;apostrophe&#39;</p>") == "'apostrophe'")
        #expect(list.stripHTML("<p><strong>Bold</strong> text</p>") == "Bold text")
    }

    @Test func truncation() throws {
        let list = Script.List()

        let short = "Short text"
        #expect(list.truncate(short, maxLength: 100) == "Short text")

        let long = String(repeating: "a", count: 150)
        let truncated = list.truncate(long, maxLength: 100)
        #expect(truncated.count == 100)
        #expect(truncated.hasSuffix("..."))
        #expect(truncated == String(repeating: "a", count: 97) + "...")
    }
}
