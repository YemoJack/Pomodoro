import AppKit
import Combine
import CoreFoundation
import SwiftUI

@MainActor
final class FocusLimitService: ObservableObject {
    static let shared = FocusLimitService()

    private enum Target: Equatable {
        case app(String)
        case website(String)
    }

    private struct TemporaryAccess {
        let target: Target
        let endsAt: Date
    }

    private var round: ActiveFocusLimitRound?
    private var temporaryAccess: TemporaryAccess?
    private var expiry: Task<Void, Never>?
    private var promptDismissal: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var prompt: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var chromePermissionByClient: [UUID: (ready: Bool, seen: Date)] = [:]
    private var chromeListener: CFMessagePort?
    private weak var timer: TimerStore?
    private var globalPanels: [NSPanel] = []
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    @Published private(set) var chromeStatus = "Chrome 未连接"

    static func isExemptApp(_ id: String) -> Bool {
        id == Bundle.main.bundleIdentifier || [AppDataMigration.currentBundleIdentifier, "com.apple.finder",
         "com.apple.systempreferences", "com.apple.dock"].contains(id)
    }

    func start(timer: TimerStore, settings: SettingsStore) {
        self.timer = timer
        checkForeground()
        timer.$activeFocusLimitRound.combineLatest(settings.$focusRestrictionMode)
            .sink { [weak self] round, mode in
                self?.apply(mode == .appsAndWebsites || round?.round.isGlobal == true ? round : nil)
            }
            .store(in: &subscriptions)

        timer.$isAuthenticatingGlobalFocus
            .sink { [weak self] authenticating in
                self?.globalPanels.forEach { $0.level = authenticating ? .normal : Self.globalPanelLevel }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.timer?.isGlobalFocusLocked == true else { return }
                self.showGlobalPanels()
            }
            .store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkForeground() }
            .store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.expireAccessIfNeeded()
                self?.checkForeground()
            }
            .store(in: &subscriptions)

        chromeListener = ChromeNativeMessaging.listen()
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in self?.updateChromeStatus(at: now) }
            .store(in: &subscriptions)
    }

    func stop() {
        subscriptions.removeAll()
        apply(nil)
        if let chromeListener { CFMessagePortInvalidate(chromeListener) }
        chromeListener = nil
    }

    func handleChrome(_ request: ChromeNativeMessaging.Request) -> ChromeNativeMessaging.Reply {
        chromePermissionByClient[request.client] = (request.ready, Date())
        updateChromeStatus(at: Date())
        let active = round.flatMap {
            $0.endsAt > Date() && $0.round.isGlobal != true && $0.round.rules.websites.isActive ? $0 : nil
        }
        if let host = request.host, request.ready, let active, request.roundID == active.round.id,
           Self.normalizedHost(host) == host, active.round.rules.websites.denies(host, includingSubdomains: true) {
            grant(.website(host), until: active.endsAt)
            checkForeground()
        }

        guard request.ready, let active else { return ChromeNativeMessaging.Reply() }
        let exception: ChromeNativeMessaging.WebException?
        if let temporaryAccess, case let .website(host) = temporaryAccess.target,
           temporaryAccess.endsAt > Date() {
            exception = .init(host: host, endsAt: temporaryAccess.endsAt)
        } else {
            exception = nil
        }
        let list = active.round.rules.websites
        return ChromeNativeMessaging.Reply(state: .init(
            roundID: active.round.id, endsAt: active.endsAt, mode: list.mode,
            domains: list.entries, exception: exception
        ))
    }

    static func domain(from input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: value.contains("://") ? value : "https://" + value)
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host(percentEncoded: false) else { return nil }
        return normalizedHost(host)
    }

    private static func normalizedHost(_ target: String) -> String? {
        let stripped = target.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let host = URL(string: "http://" + stripped)?.host,
              !host.isEmpty, host.count <= 253 else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") { return host }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return nil }
        return host
    }

    private func apply(_ next: ActiveFocusLimitRound?) {
        guard round != next else { return }
        round = next
        clearAccess()
        dismissPrompt()
        if next?.round.isGlobal == true {
            if previousPresentationOptions == nil {
                previousPresentationOptions = NSApp.presentationOptions
                NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
            }
            showGlobalPanels()
        } else {
            dismissGlobalPanels()
        }
        checkForeground()
    }

    private func isRestricted(_ app: NSRunningApplication) -> Bool {
        guard let round, round.endsAt > Date(), app.activationPolicy == .regular,
              let id = app.bundleIdentifier, !Self.isExemptApp(id) else { return false }
        if let temporaryAccess, temporaryAccess.endsAt > Date(), temporaryAccess.target == .app(id) {
            return false
        }
        return round.round.rules.apps.denies(id)
    }

    private func checkForeground() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if round?.round.isGlobal == true {
            guard let timer, timer.isGlobalFocusLocked,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy == .regular else { return }
            if timer.isAuthenticatingGlobalFocus,
               app.bundleURL?.path.hasPrefix("/System/Library/") == true,
               app.bundleIdentifier == "com.apple.SecurityAgent" {
                return
            }
            _ = app.hide()
            guard !timer.isAuthenticatingGlobalFocus else { return }
            NSApp.activate(ignoringOtherApps: true)
            (globalPanels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? globalPanels.first)?.makeKeyAndOrderFront(nil)
            return
        }
        guard isRestricted(app), let id = app.bundleIdentifier, let round else {
            if app.activationPolicy == .regular,
               let id = app.bundleIdentifier,
               (Self.isExemptApp(id) || round?.round.rules.apps.denies(id) != true),
               !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApp = app
            }
            return
        }

        _ = app.hide()
        if let previousApp, !previousApp.isTerminated, previousApp != app, !isRestricted(previousApp) {
            _ = previousApp.activate(options: [])
        }
        showPrompt(for: app, id: id, roundID: round.round.id)
    }

    private func grant(_ target: Target, until endDate: Date) {
        let endsAt = min(Date().addingTimeInterval(120), endDate)
        temporaryAccess = TemporaryAccess(target: target, endsAt: endsAt)
        expiry?.cancel()
        expiry = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            } catch { return }
            self?.expireAccessIfNeeded()
            self?.checkForeground()
        }
    }

    private func expireAccessIfNeeded() {
        if let temporaryAccess, temporaryAccess.endsAt <= Date() { clearAccess() }
    }

    private func clearAccess() {
        expiry?.cancel()
        expiry = nil
        temporaryAccess = nil
    }

    private func updateChromeStatus(at date: Date) {
        chromePermissionByClient = chromePermissionByClient.filter { date.timeIntervalSince($0.value.seen) < 3 }
        let next = chromePermissionByClient.values.contains { $0.ready } ? "Chrome 已连接"
            : chromePermissionByClient.isEmpty ? "Chrome 未连接" : "Chrome 需要网站权限"
        if chromeStatus != next { chromeStatus = next }
    }

    private func showPrompt(for app: NSRunningApplication, id: String, roundID: UUID) {
        dismissPrompt()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 106),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 14) {
            Label("\(app.localizedName ?? id) 在专注中受限", systemImage: "shield")
                .font(.headline)
                .lineLimit(1)
            HStack {
                Button("关闭") { self.dismissPrompt() }
                Spacer()
                Button("临时放行 2 分钟") { [weak self] in
                    guard let self, let round = self.round, round.round.id == roundID,
                          self.isRestricted(app) else { return }
                    self.grant(.app(id), until: round.endsAt)
                    self.dismissPrompt()
                    _ = app.unhide()
                    _ = app.activate(options: [])
                }
            }
        }.padding(16))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 24))
        }
        prompt = panel
        panel.orderFrontRegardless()
        promptDismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.dismissPrompt()
        }
    }

    private func dismissPrompt() {
        promptDismissal?.cancel()
        promptDismissal = nil
        prompt?.orderOut(nil)
        prompt = nil
    }

    private static let globalPanelLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    private func showGlobalPanels() {
        guard let timer else { return }
        let oldPanels = globalPanels
        globalPanels = NSScreen.screens.map { screen in
            let panel = GlobalFocusPanel(contentRect: screen.frame, styleMask: [.borderless],
                                         backing: .buffered, defer: false, screen: screen)
            panel.setFrame(screen.frame, display: false)
            panel.level = timer.isAuthenticatingGlobalFocus ? .normal : Self.globalPanelLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovable = false
            panel.contentView = NSHostingView(rootView: GlobalFocusView(timer: timer))
            panel.orderFrontRegardless()
            return panel
        }
        oldPanels.forEach { $0.orderOut(nil) }
        guard !timer.isAuthenticatingGlobalFocus else { return }
        NSApp.activate(ignoringOtherApps: true)
        (globalPanels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? globalPanels.first)?.makeKeyAndOrderFront(nil)
    }

    private func dismissGlobalPanels() {
        globalPanels.forEach { $0.orderOut(nil) }
        globalPanels.removeAll()
        if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }
    }
}

private final class GlobalFocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct GlobalFocusView: View {
    @ObservedObject var timer: TimerStore

    var body: some View {
        VStack(spacing: 20) {
            Label("全局专注", systemImage: "lock.fill")
                .font(.title2.weight(.semibold))
            ProgressRingView(progress: timer.progress, color: .accentColor, isPaused: false)
                .overlay {
                    Text(timer.formattedTime)
                        .font(.system(size: 58, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            GlobalFocusExitButton(timer: timer)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct GlobalFocusExitButton: View {
    @ObservedObject var timer: TimerStore

    var body: some View {
        VStack(spacing: 8) {
            Button(timer.isAuthenticatingGlobalFocus ? "等待系统验证…" : "强行终止", role: .destructive) {
                Task { await timer.authenticateAndEndGlobalFocus() }
            }
            .buttonStyle(InteractiveButtonStyle(kind: .destructive))
            .disabled(timer.isAuthenticatingGlobalFocus)
            if timer.globalFocusAuthenticationFailed {
                Text("验证未通过，本轮专注继续。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
