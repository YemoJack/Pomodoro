import AppKit
import AVFoundation
import Combine
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastDeliveryError: String?

    private let center = UNUserNotificationCenter.current()
    private var completionSound: NSSound?
    private var customSoundPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        center.delegate = self
        refreshAuthorizationStatus()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorizationStatus = granted ? .authorized : .denied
            lastDeliveryError = granted ? nil : "系统未允许通知，请在系统设置中开启。"
            return granted
        } catch {
            lastDeliveryError = "无法申请通知权限：\(error.localizedDescription)"
            refreshAuthorizationStatus()
            return false
        }
    }

    func requestAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        Task { await requestAuthorization() }
    }

    func playTimerSound(
        _ cue: TimerSoundCue,
        configuration: TimerSoundConfiguration
    ) {
        stopCompletionSound()

        if configuration.mode == .custom,
           let customSoundURL = configuration.customSoundURL,
           FileManager.default.fileExists(atPath: customSoundURL.path),
           let player = try? AVAudioPlayer(contentsOf: customSoundURL) {
            customSoundPlayer = player
            player.prepareToPlay()
            player.play()
            return
        }

        guard let sound = NSSound(named: NSSound.Name(cue.defaultSystemSoundName)) else {
            NSSound.beep()
            return
        }

        sound.loops = false
        completionSound = sound
        sound.play()
    }

    func stopCompletionSound() {
        completionSound?.stop()
        completionSound = nil
        customSoundPlayer?.stop()
        customSoundPlayer = nil
    }

    func sendPhaseCompleted(_ phase: TimerPhase, nextPhase: TimerPhase?) {
        let content = UNMutableNotificationContent()

        switch phase {
        case .focus:
            content.title = nextPhase == nil ? "计划完成" : "专注完成"
            content.body = nextPhase == nil
                ? "本次专注计划已经结束。"
                : "做得不错，休息几分钟吧。"
        case .shortBreak, .longBreak:
            content.title = "休息结束"
            content.body = "准备好后，开始下一轮专注。"
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        deliver(request, requestingAuthorizationIfNeeded: false)
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "番茄专注测试通知"
        content.body = "如果这里显示番茄图标，通知配置已经生效。"

        let request = UNNotificationRequest(
            identifier: "notification-test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        deliver(request, requestingAuthorizationIfNeeded: true)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func deliver(
        _ request: UNNotificationRequest,
        requestingAuthorizationIfNeeded: Bool
    ) {
        Task { [weak self] in
            guard let self else { return }

            let canDeliver = await ensureAuthorization(
                requestingIfNeeded: requestingAuthorizationIfNeeded
            )
            guard canDeliver else { return }

            do {
                try await center.add(request)
                lastDeliveryError = nil
            } catch {
                lastDeliveryError = "通知发送失败：\(error.localizedDescription)"
            }
        }
    }

    private func ensureAuthorization(requestingIfNeeded: Bool) async -> Bool {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined where requestingIfNeeded:
            return await requestAuthorization()
        case .notDetermined:
            lastDeliveryError = "尚未获得通知权限，请在设置中允许通知。"
            return false
        case .denied:
            lastDeliveryError = "系统通知已关闭，请在系统设置中允许番茄专注发送通知。"
            return false
        @unknown default:
            lastDeliveryError = "无法确定系统通知权限状态。"
            return false
        }
    }
}
