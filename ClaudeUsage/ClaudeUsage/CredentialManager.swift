import Foundation
import Security

struct CredentialManager {
    /// Cached auth to avoid repeated Keychain password prompts
    private static var cachedAuth: AuthMethod?
    private static var cacheExpiry: Date?

    static func clearCache() {
        cachedAuth = nil
        cacheExpiry = nil
    }

    /// Try to find auth: OAuth first (free subscription), then API key as fallback
    static func loadAuth(savedApiKey: String?) throws -> AuthMethod {
        // Return cached auth if still valid (cache for 30 minutes)
        if let cached = cachedAuth, let expiry = cacheExpiry, expiry > Date() {
            return cached
        }

        // 1. macOS Keychain OAuth (via security CLI - no password prompt)
        if let token = loadFromKeychain() {
            let auth = AuthMethod.oauth(token)
            cache(auth)
            return auth
        }

        // 2. ~/.claude/.credentials.json
        if let token = try? loadFromCredentialsFile() {
            let auth = AuthMethod.oauth(token)
            cache(auth)
            return auth
        }

        // 3. User-saved API key in app settings
        if let key = savedApiKey, !key.isEmpty {
            let auth = AuthMethod.apiKey(key)
            cache(auth)
            return auth
        }

        // 4. Read API key from user's shell profile (last - may have no credits)
        if let key = readApiKeyFromShellEnv(), !key.isEmpty {
            let auth = AuthMethod.apiKey(key)
            cache(auth)
            return auth
        }

        throw UsageError.noAuthConfigured
    }

    private static func cache(_ auth: AuthMethod) {
        cachedAuth = auth
        cacheExpiry = Date().addingTimeInterval(1800) // 30 min
    }

    // MARK: - Keychain (via security CLI to avoid password prompts)

    private static func loadFromKeychain() -> String? {
        // Multiple keychain items can share the "Claude Code-credentials"
        // service name (e.g. MCP OAuth tokens stored by Claude Code).
        // The Claude Code subscription token is stored under the macOS
        // account name, so query that explicitly first; a bare lookup
        // returns an arbitrary duplicate (often the MCP item, which has
        // no `claudeAiOauth` key and fails to decode).
        if let token = keychainToken(account: NSUserName()) { return token }
        // Fallback for older Claude Code versions that stored no account.
        return keychainToken(account: nil)
    }

    private static func keychainToken(account: String?) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        var args = ["find-generic-password", "-s", "Claude Code-credentials"]
        if let account = account, !account.isEmpty {
            args += ["-a", account]
        }
        args.append("-w")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let jsonData = raw.data(using: .utf8) else {
            return nil
        }

        guard let json = try? JSONDecoder().decode(ClaudeCredentials.self, from: jsonData) else {
            return nil
        }

        let expiresAt = Date(timeIntervalSince1970: Double(json.claudeAiOauth.expiresAt) / 1000.0)
        guard expiresAt > Date() else {
            return nil
        }

        return json.claudeAiOauth.accessToken
    }

    /// Trigger Claude Code browser login
    static func triggerBrowserLogin() {
        guard let claudePath = findClaude() else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = ["auth", "login"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    /// Find claude CLI in common paths
    private static func findClaude() -> String? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/local/claude"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback: use `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Credentials File

    private static func loadFromCredentialsFile() throws -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json").path

        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.noAuthConfigured
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let credentials = try JSONDecoder().decode(ClaudeCredentials.self, from: data)

        let expiresAt = Date(timeIntervalSince1970: Double(credentials.claudeAiOauth.expiresAt) / 1000.0)
        guard expiresAt > Date() else {
            throw UsageError.tokenExpired
        }

        return credentials.claudeAiOauth.accessToken
    }

    // MARK: - Shell Environment

    private static func readApiKeyFromShellEnv() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profileFiles = [
            "\(home)/.zshrc",
            "\(home)/.zprofile",
            "\(home)/.bash_profile",
            "\(home)/.bashrc",
            "\(home)/.profile"
        ]

        for file in profileFiles {
            if let key = extractApiKey(from: file) {
                return key
            }
        }
        return nil
    }

    private static func extractApiKey(from filePath: String) -> String? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            if trimmed.contains("ANTHROPIC_API_KEY") {
                if let eqIndex = trimmed.firstIndex(of: "=") {
                    var value = String(trimmed[trimmed.index(after: eqIndex)...])
                    value = value.trimmingCharacters(in: .whitespaces)
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if value.hasPrefix("sk-") {
                        return value
                    }
                }
            }
        }
        return nil
    }
}
