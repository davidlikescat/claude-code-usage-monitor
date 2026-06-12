import Foundation

// MARK: - Credential File Structure

struct ClaudeCredentials: Codable {
    let claudeAiOauth: OAuthToken

    struct OAuthToken: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Int64 // milliseconds since epoch
    }
}

// MARK: - Auth Method

enum AuthMethod {
    case apiKey(String)
    case oauth(String)
}

// MARK: - Usage Data

struct UsageData {
    // Unified limits (OAuth/subscription users)
    var fiveHourUtilization: Double?  // 0.0 to 1.0
    var sevenDayUtilization: Double?  // 0.0 to 1.0
    var fiveHourReset: Date?
    var sevenDayReset: Date?

    // Standard limits (API key users)
    var requestsLimit: Int?
    var requestsRemaining: Int?
    var requestsReset: Date?
    var tokensLimit: Int?
    var tokensRemaining: Int?
    var tokensReset: Date?

    let fetchedAt: Date

    var fiveHourPercent: Int { Int((fiveHourUtilization ?? 0) * 100) }
    var sevenDayPercent: Int { Int((sevenDayUtilization ?? 0) * 100) }

    var hasUnifiedLimits: Bool { fiveHourUtilization != nil }
    var hasStandardLimits: Bool { requestsLimit != nil }

    var requestsUsedPercent: Int {
        guard let limit = requestsLimit, let remaining = requestsRemaining, limit > 0 else { return 0 }
        return Int(Double(limit - remaining) / Double(limit) * 100)
    }

    var tokensUsedPercent: Int {
        guard let limit = tokensLimit, let remaining = tokensRemaining, limit > 0 else { return 0 }
        return Int(Double(limit - remaining) / Double(limit) * 100)
    }
}

// MARK: - Poll Interval

enum PollInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .oneHour: return "1 hour"
        }
    }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case noAuthConfigured
    case credentialsParseError
    case tokenExpired
    case networkError(Error)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAuthConfigured:
            return "No API key or credentials configured."
        case .credentialsParseError:
            return "Could not parse credentials file."
        case .tokenExpired:
            return "Token expired. Re-authenticate in Claude Code."
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        }
    }
}
