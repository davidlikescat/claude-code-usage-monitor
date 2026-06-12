import SwiftUI
import ServiceManagement

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var apiKeyInput = ""
    @State private var showApiKeyField = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Claude Code Usage")
                    .font(.headline)
                Spacer()
                if !viewModel.authStatus.isEmpty {
                    Text(viewModel.authStatus)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Content
            if let data = viewModel.usageData {
                usageContentView(data)
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if viewModel.isLoading {
                ProgressView("Loading...")
                    .padding(32)
            } else {
                setupView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 320)
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContentView(_ data: UsageData) -> some View {
        VStack(spacing: 14) {
            if data.hasUnifiedLimits {
                UsageBar(
                    title: "5-Hour Session",
                    utilization: data.fiveHourUtilization ?? 0,
                    resetDate: data.fiveHourReset
                )
                UsageBar(
                    title: "7-Day Weekly",
                    utilization: data.sevenDayUtilization ?? 0,
                    resetDate: data.sevenDayReset
                )
            }

            if data.hasStandardLimits {
                StandardLimitBar(
                    title: "Requests",
                    used: (data.requestsLimit ?? 0) - (data.requestsRemaining ?? 0),
                    limit: data.requestsLimit ?? 0,
                    resetDate: data.requestsReset
                )
                StandardLimitBar(
                    title: "Tokens",
                    used: (data.tokensLimit ?? 0) - (data.tokensRemaining ?? 0),
                    limit: data.tokensLimit ?? 0,
                    resetDate: data.tokensReset
                )
            }

            if !data.hasUnifiedLimits && !data.hasStandardLimits {
                Text("No rate limit data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Setup View (no auth configured)

    private var setupView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundStyle(.blue)
            Text("Sign in to Claude")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Opens browser for Anthropic OAuth login")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                loginAndRefresh()
            } label: {
                Label("Login with Browser", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Divider().padding(.vertical, 4)

            Text("Or enter API key manually")
                .font(.caption2)
                .foregroundStyle(.secondary)

            apiKeyInputField

            Button {
                saveApiKey()
            } label: {
                Label("Connect", systemImage: "checkmark.circle")
            }
            .controlSize(.small)
            .disabled(apiKeyInput.isEmpty)
        }
        .padding(24)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if showApiKeyField {
                apiKeyInputField
                HStack(spacing: 8) {
                    Button {
                        saveApiKey()
                    } label: {
                        Label("Save Key", systemImage: "checkmark.circle")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.isEmpty)

                    Button("Cancel") {
                        showApiKeyField = false
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        loginAndRefresh()
                    } label: {
                        Label("Login", systemImage: "safari")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)

                    Button("Retry") {
                        viewModel.fetchUsage()
                    }
                    .controlSize(.small)

                    Button {
                        showApiKeyField = true
                    } label: {
                        Label("API Key", systemImage: "key")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(24)
    }

    // MARK: - API Key Input

    private var apiKeyInputField: some View {
        SecureField("sk-ant-...", text: $apiKeyInput)
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: 260)
    }

    private func loginAndRefresh() {
        CredentialManager.clearCache()
        CredentialManager.triggerBrowserLogin()
        // Auto-refresh after 10 seconds to pick up new auth
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            CredentialManager.clearCache()
            viewModel.fetchUsage()
        }
    }

    private func saveApiKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        viewModel.savedApiKey = key
        apiKeyInput = ""
        showApiKeyField = false
        viewModel.fetchUsage()
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 10) {
            if let data = viewModel.usageData {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Updated \(data.fetchedAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack {
                Text("Poll interval:")
                    .font(.caption)
                Picker("", selection: Binding(
                    get: { viewModel.pollInterval },
                    set: { viewModel.pollInterval = $0 }
                )) {
                    ForEach(PollInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                Spacer()
            }

            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: launchAtLogin) { newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                Spacer()
            }

            HStack {
                Button {
                    viewModel.fetchUsage()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(viewModel.isLoading)

                if !viewModel.savedApiKey.isEmpty {
                    Button {
                        viewModel.savedApiKey = ""
                        viewModel.usageData = nil
                        viewModel.errorMessage = nil
                    } label: {
                        Label("Clear Key", systemImage: "key.slash")
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }

            Divider().padding(.top, 8)

            HStack {
                Text("v1.0 by davidlikescat")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Link("Contact", destination: URL(string: "mailto:davidlikescat@icloud.com")!)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Usage Bar (Unified 5h/7d)

struct UsageBar: View {
    let title: String
    let utilization: Double
    let resetDate: Date?

    private var percentage: Int { Int(utilization * 100) }

    private var barColor: Color {
        switch utilization {
        case ..<0.50: return .green
        case 0.50..<0.80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(barColor)
            }

            ProgressView(value: utilization)
                .tint(barColor)

            if let reset = resetDate {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text("Resets in \(formatCountdown(reset))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Standard Limit Bar (API key)

struct StandardLimitBar: View {
    let title: String
    let used: Int
    let limit: Int
    let resetDate: Date?

    private var utilization: Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit)
    }

    private var barColor: Color {
        switch utilization {
        case ..<0.50: return .green
        case 0.50..<0.80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(used)/\(formatNumber(limit))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(barColor)
            }

            ProgressView(value: utilization)
                .tint(barColor)

            if let reset = resetDate {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text("Resets in \(formatCountdown(reset))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Helpers

func formatCountdown(_ target: Date) -> String {
    let interval = target.timeIntervalSinceNow
    guard interval > 0 else { return "now" }

    let total = Int(interval)
    let days = total / 86400
    let hours = (total % 86400) / 3600
    let minutes = (total % 3600) / 60

    if days > 0 {
        return "\(days)d \(hours)h"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}

func formatNumber(_ n: Int) -> String {
    if n >= 1_000_000 {
        return "\(n / 1_000_000)M"
    } else if n >= 1_000 {
        return "\(n / 1_000)K"
    }
    return "\(n)"
}
