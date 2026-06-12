import SwiftUI
import Combine
import AppKit

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate (NSStatusBar based)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var viewModel: UsageViewModel!
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    private static let iconPointSize: CGFloat = 15
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: AppDelegate.iconPointSize, weight: .regular)

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching")
        viewModel = UsageViewModel()

        // Fixed length so the bar always reserves space — variable length can collapse to 0
        statusItem = NSStatusBar.system.statusItem(withLength: 60)
        statusItem.autosaveName = "ClaudeUsageStatusItem"
        statusItem.isVisible = true
        statusItem.behavior = []

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imageScaling = .scaleProportionallyDown
            applyImage(to: button, symbol: "bolt.fill", tint: nil)
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(
                string: " --",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            debugLog("button configured, image=\(button.image != nil ? "set" : "nil") frame=\(button.frame)")
        } else {
            debugLog("ERROR: statusItem.button is nil")
        }

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(viewModel: viewModel)
        )

        // Observe published values; these emit AFTER the property has been set
        viewModel.$usageData
            .combineLatest(viewModel.$isLoading, viewModel.$errorMessage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data, loading, error in
                self?.updateStatusIcon(data: data, isLoading: loading, errorMessage: error)
            }
            .store(in: &cancellables)

        viewModel.startPolling()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Icon update

    private func updateStatusIcon(data: UsageData?, isLoading: Bool, errorMessage: String?) {
        guard let button = statusItem?.button else { return }

        if let data {
            if data.hasUnifiedLimits {
                let remaining = 100 - data.fiveHourPercent
                render(button: button, symbol: batterySymbol(remaining: remaining),
                       title: "\(remaining)%", color: colorForRemaining(remaining))
            } else if data.hasStandardLimits {
                let remaining = 100 - data.requestsUsedPercent
                render(button: button, symbol: batterySymbol(remaining: remaining),
                       title: "\(remaining)%", color: colorForRemaining(remaining))
            } else {
                render(button: button, symbol: "questionmark.circle", title: nil, color: nil)
            }
        } else if isLoading {
            render(button: button, symbol: "arrow.triangle.2.circlepath", title: nil, color: nil)
        } else if errorMessage != nil {
            render(button: button, symbol: "exclamationmark.triangle.fill", title: nil, color: .systemOrange)
        } else {
            render(button: button, symbol: "key.fill", title: nil, color: nil)
        }
    }

    private func colorForRemaining(_ remaining: Int) -> NSColor {
        switch remaining {
        case 51...:    return .systemGreen
        case 21...50:  return .systemYellow
        default:       return .systemRed
        }
    }

    private func render(button: NSStatusBarButton, symbol: String, title: String?, color: NSColor?) {
        applyImage(to: button, symbol: symbol, tint: color)

        let titleText = (title?.isEmpty == false) ? " \(title!)" : ""
        button.imagePosition = .imageLeft
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.attributedTitle = NSAttributedString(
            string: titleText,
            attributes: [
                .font: titleFont,
                .foregroundColor: color ?? NSColor.labelColor
            ]
        )

        // 폭을 콘텐츠에 맞춰 동적 산정. 고정 60px는 배터리 아이콘 + 4글자 "100%"를
        // 다 못 담아 숫자가 잘림(100%만 안 보이던 원인). 60px를 최소로 보장.
        let imageWidth = button.image?.size.width ?? 0
        let titleWidth = titleText.isEmpty
            ? 0
            : (titleText as NSString).size(withAttributes: [.font: titleFont]).width
        statusItem.length = max(60, ceil(imageWidth + titleWidth + 16))

        button.needsDisplay = true
        statusItem.isVisible = true
        debugLog("render symbol=\(symbol) title=\(title ?? "-") color=\(color?.description ?? "default") frame=\(button.frame)")
    }

    private func applyImage(to button: NSStatusBarButton, symbol: String, tint: NSColor?) {
        button.contentTintColor = nil

        guard let raw = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude Usage") else {
            debugLog("ERROR applyImage: symbol \(symbol) not found")
            button.image = nil
            return
        }

        if let tint {
            // Apple-recommended: paletteColors configuration → colored SF Symbol
            let config = Self.symbolConfig.applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
            let colored = raw.withSymbolConfiguration(config) ?? raw
            colored.isTemplate = false
            button.image = colored
            debugLog("applyImage palette tint=\(tint), size=\(colored.size)")
        } else {
            let plain = raw.withSymbolConfiguration(Self.symbolConfig) ?? raw
            plain.isTemplate = true
            button.image = plain
        }
    }

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/claudeusage.log")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func batterySymbol(remaining: Int) -> String {
        switch remaining {
        case 76...:   return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 1...25:  return "battery.25"
        default:      return "battery.0"
        }
    }
}
