import Combine
import Foundation
import Security

@MainActor
final class TimerStore: ObservableObject {
    static let shared = TimerStore(
        settings: .shared,
        sessions: .shared,
        notifications: .shared
    )

    private let snapshotKey = "timerSnapshot.v1"
    private let settings: SettingsStore
    private let sessions: SessionStore
    private let notifications: NotificationService?
    private let defaults: UserDefaults
    private var ticker: AnyCancellable?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var startedAt: Date?
    private var endDate: Date?
    private var pendingPhase: TimerPhase?
    private var isMenuTracking = false
    private var focusLimitRound: FocusLimitRound?

    @Published private(set) var phase: TimerPhase = .focus
    @Published private(set) var status: TimerStatus = .idle
    @Published private(set) var remainingSeconds: TimeInterval = 25 * 60
    @Published private(set) var totalSeconds: TimeInterval = 25 * 60
    @Published private(set) var completedRoundsInPlan = 0
    @Published private(set) var isOneOffFocus = false
    @Published private(set) var preparedOneOffFocusMinutes: Int?
    @Published private(set) var focusCompletionEventID = 0
    @Published private(set) var activeFocusLimitRound: ActiveFocusLimitRound?
    @Published private(set) var isAuthenticatingGlobalFocus = false
    @Published private(set) var globalFocusAuthenticationFailed = false

    var isGlobalFocusLocked: Bool {
        guard status == .running, phase.isFocus, let endDate, endDate > Date() else { return false }
        return focusLimitRound?.isGlobal == true
    }

    init(
        settings: SettingsStore,
        sessions: SessionStore,
        notifications: NotificationService? = nil,
        defaults: UserDefaults = .standard
    ) {
        AppDataMigration.migrateStandardDefaultsIfNeeded(defaults)
        self.settings = settings
        self.sessions = sessions
        self.notifications = notifications
        self.defaults = defaults

        restore()
        observeSettings()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.tick(at: now)
            }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(1 - remainingSeconds / totalSeconds, 0), 1)
    }

    var formattedTime: String {
        let seconds = max(Int(ceil(remainingSeconds)), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var isActive: Bool { status == .running || status == .paused }
    var isPlanCompleted: Bool { status == .completed && pendingPhase == nil }
    var canPrepareOneOffFocus: Bool { status == .idle || isPlanCompleted }
    var isFinalFocusRound: Bool {
        phase.isFocus && (isOneOffFocus || completedRoundsInPlan + 1 >= settings.totalRounds)
    }

    var primaryActionTitle: String {
        switch status {
        case .idle:
            if preparedOneOffFocusMinutes != nil { return "开始单次专注" }
            return phase.isFocus ? "开始专注" : "开始休息"
        case .running:
            return phase.isFocus ? "暂停" : "暂停休息"
        case .paused:
            return phase.isFocus ? "继续专注" : "继续休息"
        case .completed:
            if preparedOneOffFocusMinutes != nil { return "开始单次专注" }
            guard let pendingPhase else { return "重新开始" }
            return pendingPhase.isFocus ? "开始专注" : "开始休息"
        }
    }

    var statusTitle: String {
        if isOneOffFocus && status == .completed {
            return "单次专注完成"
        }
        switch status {
        case .idle:
            return "准备专注"
        case .running:
            return phase.runningTitle
        case .paused:
            return "已暂停"
        case .completed:
            return pendingPhase == nil ? "计划完成" : "已完成"
        }
    }

    var cycleDescription: String {
        if isOneOffFocus {
            return status == .completed ? "单次专注已结束" : "单次专注"
        }
        if status == .completed {
            if pendingPhase == .focus {
                let next = min(completedRoundsInPlan + 1, settings.totalRounds)
                return "准备第 \(next) / \(settings.totalRounds) 轮"
            }
            if pendingPhase != nil {
                return "第 \(completedRoundsInPlan) / \(settings.totalRounds) 轮已结束"
            }
            return "已完成 \(completedRoundsInPlan) / \(settings.totalRounds) 轮"
        }

        if phase.isFocus {
            let current = min(completedRoundsInPlan + 1, settings.totalRounds)
            return "第 \(current) / \(settings.totalRounds) 轮"
        }
        return "第 \(completedRoundsInPlan) / \(settings.totalRounds) 轮休息"
    }

    func performPrimaryAction() {
        switch status {
        case .idle:
            start(phase: .focus)
        case .running:
            pause()
        case .paused:
            resume()
        case .completed:
            startPendingPhase()
        }
    }

    func start(phase newPhase: TimerPhase) {
        guard !isGlobalFocusLocked else { return }
        focusLimitRound = newPhase.isFocus
            ? FocusLimitRound(
                id: UUID(), rules: settings.focusLimitRules,
                isGlobal: settings.focusLimitsEnabled && settings.globalFocusLimitEnabled
            ) : nil
        globalFocusAuthenticationFailed = false
        phase = newPhase
        status = .running
        if newPhase.isFocus, let preparedOneOffFocusMinutes {
            isOneOffFocus = true
            totalSeconds = TimeInterval(preparedOneOffFocusMinutes * 60)
            self.preparedOneOffFocusMinutes = nil
            completedRoundsInPlan = 0
        } else {
            isOneOffFocus = false
            totalSeconds = settings.duration(for: newPhase)
        }
        remainingSeconds = totalSeconds
        startedAt = Date()
        endDate = Date().addingTimeInterval(totalSeconds)
        pendingPhase = nil
        persist()
    }

    func prepareOneOffFocus(minutes: Int) {
        guard canPrepareOneOffFocus else { return }
        preparedOneOffFocusMinutes = min(max(minutes, 1), TimerDurationLimits.oneOffFocusMinutes)
        persist()
    }

    func pause() {
        guard status == .running, !isGlobalFocusLocked else { return }
        updateRemaining(at: Date())
        endDate = nil
        status = .paused
        persist()
    }

    func resume() {
        guard status == .paused else { return }
        endDate = Date().addingTimeInterval(remainingSeconds)
        status = .running
        persist()
    }

    func skipCurrentPhase() {
        guard isActive, !isGlobalFocusLocked else { return }
        let now = Date()

        if phase.isFocus {
            finishFocusRound(completed: false, endedAt: now, forceStartBreak: true)
        } else {
            recordCurrentPhase(completed: false, endedAt: now)
            start(phase: .focus)
        }
    }

    func endCurrentCycle() {
        guard !isGlobalFocusLocked else { return }
        endCycle()
    }

    func authenticateAndEndGlobalFocus() async {
        guard isGlobalFocusLocked, !isAuthenticatingGlobalFocus, let roundID = focusLimitRound?.id else { return }
        globalFocusAuthenticationFailed = false
        isAuthenticatingGlobalFocus = true
        defer { isAuthenticatingGlobalFocus = false }

        let result = await Task.detached { Self.authorizeEndingGlobalFocus() }.value
        guard isGlobalFocusLocked, focusLimitRound?.id == roundID else { return }
        if result == errAuthorizationSuccess {
            updateRemaining(at: Date())
            endCycle()
        } else if result != errAuthorizationCanceled {
            globalFocusAuthenticationFailed = true
        }
    }

    private nonisolated static func authorizeEndingGlobalFocus() -> OSStatus {
        var reference: AuthorizationRef?
        let created = AuthorizationCreate(nil, nil, [], &reference)
        guard created == errAuthorizationSuccess, let reference else { return created }
        defer { AuthorizationFree(reference, [.destroyRights]) }

        return "com.ruidouwang.Pomodoro.end-global-focus".withCString { name in
            if AuthorizationRightGet(name, nil) != errAuthorizationSuccess {
                let rule: [String: Any] = [
                    "class": "user",
                    "session-owner": true,
                    "authenticate-user": true,
                    "shared": false,
                    "timeout": 0
                ]
                let status = AuthorizationRightSet(
                    reference, name, rule as CFDictionary,
                    "请输入 Mac 登录密码以终止本次全局专注。" as CFString, nil, nil
                )
                guard status == errAuthorizationSuccess else { return status }
            }
            var right = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &right) { item in
                var rights = AuthorizationRights(count: 1, items: item)
                return AuthorizationCopyRights(reference, &rights, nil, [.interactionAllowed, .extendRights], nil)
            }
        }
    }

    private func endCycle() {
        guard status != .idle else { return }
        if isActive {
            recordCurrentPhase(completed: false, endedAt: Date())
        }
        completedRoundsInPlan = 0
        resetToIdle()
    }

    func restartPlan() {
        guard !isGlobalFocusLocked else { return }
        if isActive {
            recordCurrentPhase(completed: false, endedAt: Date())
        }
        completedRoundsInPlan = 0
        start(phase: .focus)
    }

    func startPendingPhase() {
        guard !isGlobalFocusLocked else { return }
        if let pendingPhase {
            start(phase: pendingPhase)
        } else {
            completedRoundsInPlan = 0
            start(phase: .focus)
        }
    }

    func setMenuTracking(_ isTracking: Bool) {
        guard isMenuTracking != isTracking else { return }
        isMenuTracking = isTracking

        if !isTracking {
            tick(at: Date())
        }
    }

    private func tick(at date: Date) {
        guard status == .running else { return }
        guard let endDate else { return }

        let updatedRemaining = max(endDate.timeIntervalSince(date), 0)
        if updatedRemaining <= 0 {
            remainingSeconds = 0
            completeCurrentPhase(at: date)
        } else if !isMenuTracking {
            remainingSeconds = updatedRemaining
        }
    }

    private func updateRemaining(at date: Date) {
        guard let endDate else { return }
        remainingSeconds = max(endDate.timeIntervalSince(date), 0)
    }

    private func completeCurrentPhase(at date: Date) {
        guard status == .running else { return }

        remainingSeconds = 0
        if phase.isFocus {
            finishFocusRound(completed: true, endedAt: date, forceStartBreak: false)
        } else {
            let completedPhase = phase
            recordCurrentPhase(completed: true, endedAt: date)
            let nextPhase = TimerPhase.focus
            notify(
                completedPhase: completedPhase,
                nextPhase: nextPhase,
                soundCue: .breakCompleted
            )

            if settings.autoStartFocus {
                start(phase: nextPhase)
            } else {
                status = .completed
                pendingPhase = nextPhase
                startedAt = nil
                endDate = nil
                persist()
            }
        }
    }

    private func finishFocusRound(completed: Bool, endedAt: Date, forceStartBreak: Bool) {
        recordCurrentPhase(completed: completed, endedAt: endedAt)
        if completed {
            focusCompletionEventID += 1
        }

        if isOneOffFocus {
            if completed {
                notify(
                    completedPhase: .focus,
                    nextPhase: nil,
                    soundCue: .planCompleted
                )
            }
            status = .completed
            pendingPhase = nil
            startedAt = nil
            endDate = nil
            persist()
            return
        }

        completedRoundsInPlan += 1

        let finishedPlan = completedRoundsInPlan >= settings.totalRounds
        if finishedPlan {
            if completed {
                notify(
                    completedPhase: .focus,
                    nextPhase: nil,
                    soundCue: .planCompleted
                )
            }
            completedRoundsInPlan = settings.totalRounds
            status = .completed
            pendingPhase = nil
            startedAt = nil
            endDate = nil
            persist()
            return
        }

        let nextPhase = TimerPhase.shortBreak
        if completed {
            notify(
                completedPhase: .focus,
                nextPhase: nextPhase,
                soundCue: .focusCompleted
            )
        }

        if forceStartBreak || settings.autoStartBreaks {
            start(phase: nextPhase)
        } else {
            status = .completed
            pendingPhase = nextPhase
            startedAt = nil
            endDate = nil
            persist()
        }
    }

    private func notify(
        completedPhase: TimerPhase,
        nextPhase: TimerPhase?,
        soundCue: TimerSoundCue?
    ) {
        if settings.soundEnabled, let soundCue {
            notifications?.playTimerSound(
                soundCue,
                configuration: settings.soundConfiguration(for: soundCue)
            )
        }

        guard settings.notificationsEnabled else { return }
        notifications?.sendPhaseCompleted(
            completedPhase,
            nextPhase: nextPhase
        )
    }

    private func recordCurrentPhase(completed: Bool, endedAt: Date) {
        guard let startedAt else { return }
        let actualDuration = completed
            ? totalSeconds
            : max(totalSeconds - remainingSeconds, 0)
        sessions.add(FocusSession(
            phase: phase,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedDuration: totalSeconds,
            actualDuration: actualDuration,
            completed: completed
        ))
    }

    private func resetToIdle() {
        phase = .focus
        status = .idle
        totalSeconds = settings.duration(for: .focus)
        remainingSeconds = totalSeconds
        startedAt = nil
        endDate = nil
        pendingPhase = nil
        isOneOffFocus = false
        preparedOneOffFocusMinutes = nil
        focusLimitRound = nil
        persist()
    }

    private func observeSettings() {
        settings.$focusMinutes
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.status == .idle else { return }
                self.totalSeconds = self.settings.duration(for: .focus)
                self.remainingSeconds = self.totalSeconds
                self.persist()
            }
            .store(in: &settingsCancellables)
    }

    private func restore() {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(TimerSnapshot.self, from: data)
        else {
            totalSeconds = settings.duration(for: .focus)
            remainingSeconds = totalSeconds
            return
        }

        phase = snapshot.phase == .longBreak ? .shortBreak : snapshot.phase
        status = snapshot.status
        totalSeconds = snapshot.totalSeconds
        remainingSeconds = snapshot.remainingSeconds
        endDate = snapshot.endDate
        startedAt = snapshot.startedAt
        completedRoundsInPlan = snapshot.completedRoundsInPlan
        pendingPhase = snapshot.pendingPhase == .longBreak ? .shortBreak : snapshot.pendingPhase
        isOneOffFocus = snapshot.isOneOffFocus
        focusLimitRound = snapshot.focusLimitRound
        preparedOneOffFocusMinutes = snapshot.preparedOneOffFocusMinutes.map {
            min(max($0, 1), TimerDurationLimits.oneOffFocusMinutes)
        }

        if status == .running, let endDate {
            remainingSeconds = max(endDate.timeIntervalSinceNow, 0)
            if remainingSeconds <= 0 {
                completeCurrentPhase(at: Date())
            }
        }
        publishFocusLimitRound()
    }

    private func persist() {
        let snapshot = TimerSnapshot(
            phase: phase,
            status: status,
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            endDate: endDate,
            startedAt: startedAt,
            completedRoundsInPlan: completedRoundsInPlan,
            pendingPhase: pendingPhase,
            isOneOffFocus: isOneOffFocus,
            preparedOneOffFocusMinutes: preparedOneOffFocusMinutes,
            focusLimitRound: focusLimitRound
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        publishFocusLimitRound()
    }

    private func publishFocusLimitRound() {
        let next: ActiveFocusLimitRound?
        if phase.isFocus, status == .running, let focusLimitRound, let endDate, endDate > Date() {
            next = ActiveFocusLimitRound(round: focusLimitRound, endsAt: endDate)
        } else {
            next = nil
        }
        if next != activeFocusLimitRound { activeFocusLimitRound = next }
    }
}
