import XCTest
import Foundation
import SQLite
@testable import TarPit

final class TarPitTests: XCTestCase {
    var tempDir: URL!
    var dbPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("test.sqlite3").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSchemaCreation() throws {
        let db = try Connection(dbPath)
        let schema = Schema()

        XCTAssertNoThrow(try schema.create(db: db))

        // Verify tables exist by querying them
        XCTAssertNoThrow(try db.prepare(schema.toots.table))
        XCTAssertNoThrow(try db.prepare(schema.categories.table))
        XCTAssertNoThrow(try db.prepare(schema.tootsCategories.table))
        XCTAssertNoThrow(try db.prepare(schema.trace.table))
    }

    func testInsertAndRetrieveToots() throws {
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

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(try rows[0].get(schema.toots.guid), "guid3")
        XCTAssertEqual(try rows[1].get(schema.toots.guid), "guid2")
        XCTAssertEqual(try rows[2].get(schema.toots.guid), "guid1")
    }

    func testQueryWithLimit() throws {
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

        XCTAssertEqual(rows.count, 5)
        // Should get the 5 most recent (guid10, guid9, guid8, guid7, guid6)
        XCTAssertEqual(try rows[0].get(schema.toots.guid), "guid10")
        XCTAssertEqual(try rows[4].get(schema.toots.guid), "guid6")
    }

    func testDuplicateGuidPrevention() throws {
        let db = try Connection(dbPath)
        let schema = Schema()
        try schema.create(db: db)

        let testDate = Date()

        // Insert first toot
        XCTAssertNoThrow(try db.run(schema.toots.table.insert(
            schema.toots.guid <- "duplicate-guid",
            schema.toots.link <- "http://example.com/1",
            schema.toots.pubDate <- testDate,
            schema.toots.description <- "<p>First</p>"
        )))

        // Try to insert duplicate - should fail
        XCTAssertThrowsError(try db.run(schema.toots.table.insert(
            or: .abort,
            schema.toots.guid <- "duplicate-guid",
            schema.toots.link <- "http://example.com/2",
            schema.toots.pubDate <- testDate,
            schema.toots.description <- "<p>Second</p>"
        )))
    }

    func testHTMLStripping() throws {
        let list = Script.List()

        XCTAssertEqual(list.stripHTML("<p>Hello world</p>"), "Hello world")
        XCTAssertEqual(list.stripHTML("<p>Hello&nbsp;world</p>"), "Hello world")
        XCTAssertEqual(list.stripHTML("<p>Hello &amp; goodbye</p>"), "Hello & goodbye")
        XCTAssertEqual(list.stripHTML("<p>Test &lt;tag&gt;</p>"), "Test <tag>")
        XCTAssertEqual(list.stripHTML("<p>&quot;quoted&quot;</p>"), "\"quoted\"")
        XCTAssertEqual(list.stripHTML("<p>&#39;apostrophe&#39;</p>"), "'apostrophe'")
        XCTAssertEqual(list.stripHTML("<p><strong>Bold</strong> text</p>"), "Bold text")
    }

    func testTruncation() throws {
        let list = Script.List()

        let short = "Short text"
        XCTAssertEqual(list.truncate(short, maxLength: 100), "Short text")

        let long = String(repeating: "a", count: 150)
        let truncated = list.truncate(long, maxLength: 100)
        XCTAssertEqual(truncated.count, 100)
        XCTAssertTrue(truncated.hasSuffix("..."))
        XCTAssertEqual(truncated, String(repeating: "a", count: 97) + "...")
    }
}
