import Configuration
import Foundation

struct ConfigManager {
    static let shared = ConfigManager()

    private let configFilePath: String

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.configFilePath = homeDir
            .appendingPathComponent(".config")
            .appendingPathComponent("tar_pit")
            .appendingPathComponent("config.yaml")
            .path
    }

    func resolveDBPath(cliArgument: String?) -> String? {
        // Priority order:
        // 1. CLI argument (if provided)
        // 2. Environment variable
        // 3. Config file
        // 4. nil (let caller handle the error)

        if let cliPath = cliArgument {
            return cliPath
        }

        // Use ConfigReader with providers
        // Priority is determined by order: first provider has highest priority
        var providers: [any ConfigProvider] = []

        // Add environment variables provider (highest priority after CLI)
        providers.append(EnvironmentVariablesProvider())

        // Add YAML file provider if file exists (lowest priority)
        if FileManager.default.fileExists(atPath: configFilePath) {
            do {
                let fileProvider = try FileProvider<YAMLSnapshot>(filePath: configFilePath)
                providers.append(fileProvider)
            } catch {
                // Silently ignore file reading errors
            }
        }

        let config = ConfigReader(providers: providers)

        // Try reading with environment variable key
        if let dbPath = config.string(forKey: "TAR_PIT_DB_PATH") {
            return dbPath
        }

        // Try reading with YAML config key
        if let dbPath = config.string(forKey: "db_path") {
            return dbPath
        }

        return nil
    }
}
