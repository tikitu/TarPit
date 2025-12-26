import Configuration
import Foundation

struct TarPitConfig: Codable {
    var dbPath: String?

    enum CodingKeys: String, CodingKey {
        case dbPath = "db_path"
    }
}

struct ConfigManager {
    static let shared = ConfigManager()

    private let configFilePath: String
    private let environmentPrefix = "TAR_PIT"

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.configFilePath = homeDir
            .appendingPathComponent(".config")
            .appendingPathComponent("tar_pit")
            .appendingPathComponent("config.yaml")
            .path
    }

    func loadConfiguration() -> TarPitConfig {
        var configuration = ConfigurationBuilder()

        // Add YAML file source if it exists
        if FileManager.default.fileExists(atPath: configFilePath) {
            configuration.addYAMLFile(atPath: configFilePath, required: false)
        }

        // Add environment variables with prefix
        configuration.addEnvironmentVariables(prefix: environmentPrefix)

        do {
            let config = try configuration.build().get(TarPitConfig.self)
            return config
        } catch {
            // Return empty config if loading fails
            return TarPitConfig()
        }
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

        let config = loadConfiguration()
        return config.dbPath
    }
}
