import ArgumentParser
import Foundation
import FeedKit
import SQLite

@main
struct Script: ParsableCommand {
    static public var configuration = CommandConfiguration(
        abstract: "Fetch and store a Mastodon RSS feed",
        version: "0.0.1",
        subcommands: [Init.self, Fetch.self])

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

    struct Fetch: ParsableCommand {
        static public var configuration = CommandConfiguration()

        @Argument(
            transform: {
                guard let url = URL(string: $0) else {
                    throw ValidationError("could not parse URL from \($0)")
                }
                return url
            })
        var url: URL

        func run() throws {
            let parser = FeedParser(URL: url)
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
        let date = Expression<Date>("timestamp")
        let lastBuildDate = Expression<Date?>("lastBuildDate")
        let description = Expression<String>("description")

        func createTable() -> String {
            table.create(ifNotExists: true) { t in
                t.column(date)
                t.column(lastBuildDate)
                t.column(description)
            }
        }
    }
}
