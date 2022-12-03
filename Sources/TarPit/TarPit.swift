import ArgumentParser
import Foundation
import FeedKit
import SQLite

@main
struct Script: ParsableCommand {
    static public var configuration = CommandConfiguration(
        abstract: "Fetch and store a Mastodon RSS feed",
        version: "0.0.1",
        subcommands: [Init.self, Print.self, Store.self])

    struct Init: ParsableCommand {
        static public var configuration = CommandConfiguration(
            commandName: "init",
            abstract: "create the sqlite database & table structure"
        )

        @Argument()
        var file: String

        func run() throws {
            let db = try Connection(file)
            try Schema().create(db: db)
        }
    }

    struct RSSSource: ParsableArguments {
        @Option(
            transform: {
                guard !$0.isEmpty else { return nil }
                guard let url = URL(string: $0) else {
                    throw ValidationError("could not parse URL from \($0)")
                }
                return url
            })
        var url: URL?
        @Option()
        var file: String?

        func validate() throws {
            if url == nil && file == nil {
                throw ValidationError("you must specify either --url or --file")
            }
            if url != nil && file != nil {
                throw ValidationError("you cannot specify both --url and --file")
            }
        }

        func parser() throws -> FeedParser {
            if let url { return FeedParser(URL: url) }
            if let file {
                let data = try Data(String(contentsOfFile: file).utf8)
                return FeedParser(data: data)
            }
            fatalError("should not happen, validation ensure not both nil")
        }
    }

    struct Store: ParsableCommand {
        static public var configuration = CommandConfiguration()

        @Argument()
        var db: String

        @OptionGroup
        var rss: RSSSource

        func run() throws {
            let parser = try rss.parser()
            let db = try Connection(self.db)

            parseItemsAndUpdateDB(parser: parser, db: db)
        }
    }

    struct Print: ParsableCommand {
        static public var configuration = CommandConfiguration()

        @OptionGroup
        var rss: RSSSource

        func run() throws {
            let parser = try rss.parser()
            let feed = parser.parse()
            switch feed {
            case .failure(let error):
                throw error
            case .success(.rss(let feed)):
                feed.items?.forEach { item in
                    item.guid.map { print($0) }
                    item.pubDate.map { print($0) }
                    item.description.map { print($0) }
                    item.categories.map { print($0.map { $0.value }) }
                }
            default:
                throw ValidationError("not a Mastodon RSS feed?")
            }
        }
    }
}

func parseItemsAndUpdateDB(parser: FeedParser, db: Connection) {
    let schema = Schema()
    let timestamp = Date()
    var description = ""
    var lastBuildDate: Date?
    do {
        switch parser.parse() {
        case .failure(let error):
            throw error
        case .success(.rss(let feed)):
            lastBuildDate = feed.lastBuildDate
            var parsed = 0
            var incomplete = 0
            var skipped = 0
            var inserted = 0
            for item in feed.items ?? [] {
                guard let guid = item.guid?.value,
                      let link = item.link,
                      let pubDate = item.pubDate,
                      let description = item.description
                else {
                    incomplete += 1
                    continue
                }
                parsed += 1
                do {
                    let tootID = try db.run(
                        schema.toots.table.insert(
                            or: .abort,
                            schema.toots.guid <- guid,
                            schema.toots.link <- link,
                            schema.toots.pubDate <- pubDate,
                            schema.toots.description <- description
                        )
                    )
                    inserted += 1
                    for category in (item.categories ?? []).compactMap({ $0.value }) {
                        let categoryID: Int64
                        if let row = try? db.pluck(
                            schema.categories.table
                                .select(schema.categories.id)
                                .filter(schema.categories.value == category)) {
                            categoryID = try row.get(schema.categories.id)
                        } else {
                            categoryID = try db.run(
                                schema.categories.table.insert(
                                    or: .ignore,
                                    schema.categories.value <- category
                                )
                            )
                        }
                        try db.run(
                            schema.tootsCategories.table.insert(
                                schema.tootsCategories.toot <- tootID,
                                schema.tootsCategories.category <- categoryID
                            )
                        )
                    }
                } catch let Result.error(_, code, _) where code == SQLITE_CONSTRAINT {
                    skipped += 1 // we *assume* this was a uniqueness constraint
                    continue
                }
            }
            description = "success: incomplete \(incomplete) parsed \(parsed) skipped \(skipped) inserted \(inserted)"
        default:
            throw ValidationError("not a Mastodon RSS feed?")
        }
    } catch {
        description = "failed with error \(error)"
    }

    do {
        try db.run(
            schema.trace.table.insert(
                schema.trace.timestamp <- timestamp,
                schema.trace.lastBuildDate <- lastBuildDate,
                schema.trace.description <- description
            )
        )
        print(description)
    } catch {
        print("failed to update trace with \(error)")
    }
}

struct Schema {
    let toots = Toots()
    let categories = Categories()
    let tootsCategories = TootsCategories()
    let trace = Trace()

    func create(db: Connection) throws {
        print("creating table `toots`")
        try db.run(toots.createTable())

        print("creating table `categories`")
        try db.run(categories.createTable())

        print("creating join table `toots-categories`")
        try db.run(tootsCategories.createTable(toots: toots, categories: categories))

        print("creating table `trace`")
        try db.run(trace.createTable())

        print("done")
    }

    struct Toots {
        let table = Table("toots")

        let id = Expression<Int64>("id")
        let guid = Expression<String>("guid")
        let link = Expression<String>("link")
        let pubDate = Expression<Date>("pubDate")
        let description = Expression<String>("description")

        func createTable() -> String {
            table.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(guid, unique: true)
                t.column(link)
                t.column(pubDate)
                t.column(description)
            }
        }
    }

    struct Categories {
        let table = Table("categories")
        let id = Expression<Int64>("id")
        let value = Expression<String>("value")

        func createTable() -> String {
            table.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(value, unique: true)
            }
        }
    }

    struct TootsCategories {
        let table = Table("toots-categories")
        let toot = Expression<Int64>("toot")
        let category = Expression<Int64>("category")

        func createTable(toots: Toots, categories: Categories) -> String {
            table.create(ifNotExists: true) { t in
                t.column(toot)
                t.column(category)
                t.foreignKey(toot, references: toots.table, toots.id, delete: .cascade)
                t.foreignKey(category, references: categories.table, categories.id, delete: .cascade)
            }
        }
    }

    struct Trace {
        let table = Table("trace")
        let timestamp = Expression<Date>("timestamp")
        let lastBuildDate = Expression<Date?>("lastBuildDate")
        let description = Expression<String>("description")

        func createTable() -> String {
            table.create(ifNotExists: true) { t in
                t.column(timestamp)
                t.column(lastBuildDate)
                t.column(description)
            }
        }
    }
}

let SQLITE_CONSTRAINT = 19
