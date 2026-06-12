import Foundation
import SwiftUI

@MainActor
class UsageViewModel: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authStatus: String = ""
    @AppStorage("pollIntervalRaw") var pollIntervalRaw: Int = PollInterval.fifteenMinutes.rawValue
    @AppStorage("savedApiKey") var savedApiKey: String = ""

    var pollInterval: PollInterval {
        get { PollInterval(rawValue: pollIntervalRaw) ?? .fifteenMinutes }
        set {
            pollIntervalRaw = newValue.rawValue
            restartTimer()
        }
    }

    private var timerTask: Task<Void, Never>?

    func startPolling() {
        fetchUsage()
        restartTimer()
    }

    func restartTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval.rawValue) * 1_000_000_000)
                guard !Task.isCancelled else { break }
                fetchUsage()
            }
        }
    }

    func fetchUsage() {
        guard !isLoading else { return }
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let auth = try CredentialManager.loadAuth(savedApiKey: savedApiKey.isEmpty ? nil : savedApiKey)
                switch auth {
                case .apiKey:
                    authStatus = "API Key"
                case .oauth:
                    authStatus = "OAuth"
                }
                let data = try await performAPICall(auth: auth)
                self.usageData = data
                self.errorMessage = nil
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func performAPICall(auth: AuthMethod) async throws -> UsageData {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        switch auth {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .oauth(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode >= 400 {
            let errorMsg = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])?["error"] as? [String: Any]
            let msg = errorMsg?["message"] as? String ?? "Unknown error"
            throw UsageError.apiError(http.statusCode, msg)
        }

        return parseHeaders(http)
    }

    private func parseHeaders(_ response: HTTPURLResponse) -> UsageData {
        let fiveHStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-unified-5h-utilization")
        let sevenDStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-unified-7d-utilization")
        let fiveHResetStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-unified-5h-reset")
        let sevenDResetStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-unified-7d-reset")

        let reqLimit = response.value(forHTTPHeaderField: "anthropic-ratelimit-requests-limit").flatMap(Int.init)
        let reqRemaining = response.value(forHTTPHeaderField: "anthropic-ratelimit-requests-remaining").flatMap(Int.init)
        let reqResetStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-requests-reset")
        let tokLimit = response.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-limit").flatMap(Int.init)
        let tokRemaining = response.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-remaining").flatMap(Int.init)
        let tokResetStr = response.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-reset")

        return UsageData(
            fiveHourUtilization: fiveHStr.flatMap(Double.init),
            sevenDayUtilization: sevenDStr.flatMap(Double.init),
            fiveHourReset: parseResetDate(fiveHResetStr),
            sevenDayReset: parseResetDate(sevenDResetStr),
            requestsLimit: reqLimit,
            requestsRemaining: reqRemaining,
            requestsReset: parseResetDate(reqResetStr),
            tokensLimit: tokLimit,
            tokensRemaining: tokRemaining,
            tokensReset: parseResetDate(tokResetStr),
            fetchedAt: Date()
        )
    }

    /// Parse reset date - handles both Unix timestamp (seconds) and ISO8601 formats
    private func parseResetDate(_ str: String?) -> Date? {
        guard let str = str else { return nil }

        // Try Unix timestamp first (e.g., "1772348400")
        if let ts = Double(str) {
            return Date(timeIntervalSince1970: ts)
        }

        // Try ISO8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: str) { return date }

        let isoBasic = ISO8601DateFormatter()
        return isoBasic.date(from: str)
    }
}
