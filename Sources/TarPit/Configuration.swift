import Foundation

struct ConfigManager {
    static let shared = ConfigManager()

    private let configFilePath: String
    private let environmentPrefix = "TAR_PIT_"

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

        // Check environment variable
        if let envPath = ProcessInfo.processInfo.environment["TAR_PIT_DB_PATH"] {
            return envPath
        }

        // Check config file
        if FileManager.default.fileExists(atPath: configFilePath) {
            do {
                let yamlData = try String(contentsOfFile: configFilePath, encoding: .utf8)
                // Simple YAML parsing for "db_path: value" format
                let lines = yamlData.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("db_path:") {
                        let value = trimmed
                            .replacingOccurrences(of: "db_path:", with: "")
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty && !value.hasPrefix("#") {
                            return value
                        }
                    }
                }
            } catch {
                // Silently ignore file read errors and continue
            }
        }

        return nil
    }
}
