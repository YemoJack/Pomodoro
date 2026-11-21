import Foundation

enum TimerDurationLimits {
    static let customFocusMinutes = 6 * 60
    static let oneOffFocusMinutes = 3 * 60
}

enum CompletionSoundMode: String, CaseIterable, Codable, Identifiable {
    case system
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "默认提示音"
        case .custom: "自定义音乐"
        }
    }
}

enum TimerSoundCue: String, CaseIterable, Identifiable {
    case focusCompleted
    case breakCompleted = "breakEndedFocusStarted"
    case planCompleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusCompleted: "专注结束"
        case .breakCompleted: "休息结束"
        case .planCompleted: "最后一轮专注结束"
        }
    }

    var explanation: String {
        switch self {
        case .focusCompleted:
            "普通专注阶段结束时播放。"
        case .breakCompleted:
            "每轮休息阶段结束时播放，与是否自动开始专注无关。"
        case .planCompleted:
            "完成计划中的最后一轮专注时播放。"
        }
    }

    var defaultSystemSoundName: String {
        switch self {
        case .focusCompleted: "Glass"
        case .breakCompleted: "Ping"
        case .planCompleted: "Hero"
        }
    }

}

struct TimerSoundConfiguration: Codable, Equatable {
    var mode: CompletionSoundMode
    var customSoundPath: String?
    var customSoundDisplayName: String? = nil

    var customSoundURL: URL? {
        guard let customSoundPath else { return nil }
        return URL(fileURLWithPath: customSoundPath)
    }

    static func defaultValue(for cue: TimerSoundCue) -> TimerSoundConfiguration {
        TimerSoundConfiguration(
            mode: .system,
            customSoundPath: nil,
            customSoundDisplayName: nil
        )
    }
}

struct TimerPreset: Codable, Equatable, Identifiable {
    static let defaultID = "builtin.pomodoro"

    let id: String
    var name: String
    var focusMinutes: Int
    var breakMinutes: Int
    var rounds: Int
    var autoStartBreaks: Bool
    var autoStartFocus: Bool

    var isDefault: Bool { id == Self.defaultID }

    var summary: String {
        "\(focusMinutes) / \(breakMinutes) 分钟 · \(rounds) 轮"
    }

    static let defaultPreset = TimerPreset(
        id: defaultID,
        name: "标准番茄",
        focusMinutes: 25,
        breakMinutes: 5,
        rounds: 4,
        autoStartBreaks: false,
        autoStartFocus: false
    )

    static let starterPresets = [
        TimerPreset(
            id: "starter.sprint",
            name: "短时冲刺",
            focusMinutes: 15,
            breakMinutes: 5,
            rounds: 4,
            autoStartBreaks: false,
            autoStartFocus: false
        ),
        TimerPreset(
            id: "starter.classroom",
            name: "上课模式",
            focusMinutes: 45,
            breakMinutes: 10,
            rounds: 4,
            autoStartBreaks: true,
            autoStartFocus: true
        ),
        TimerPreset(
            id: "starter.deep-focus",
            name: "深度专注",
            focusMinutes: 50,
            breakMinutes: 10,
            rounds: 3,
            autoStartBreaks: false,
            autoStartFocus: false
        )
    ]
}

enum TimerPhase: String, Codable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        isFocus ? "专注" : "休息"
    }

    var runningTitle: String {
        isFocus ? "专注中" : "休息中"
    }

    var symbol: String {
        switch self {
        case .focus: "timer"
        case .shortBreak, .longBreak: "cup.and.saucer.fill"
        }
    }

    var isFocus: Bool { self == .focus }
}

enum TimerStatus: String, Codable {
    case idle
    case running
    case paused
    case completed
}

enum FocusLimitMode: String, Codable, CaseIterable, Identifiable {
    case off, block, allow

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "关闭"
        case .block: "屏蔽名单内"
        case .allow: "仅允许名单内"
        }
    }
}

struct FocusLimitList: Codable, Equatable {
    var mode: FocusLimitMode = .block
    var blocked: [String] = []
    var allowed: [String] = []

    var entries: [String] {
        get { mode == .allow ? allowed : blocked }
        set {
            if mode == .allow { allowed = newValue } else { blocked = newValue }
        }
    }

    var isActive: Bool { mode != .off && !entries.isEmpty }

    func denies(_ target: String, includingSubdomains: Bool = false) -> Bool {
        guard isActive else { return false }
        let matches = entries.contains { entry in
            target == entry || (includingSubdomains && target.hasSuffix("." + entry))
        }
        return mode == .allow ? !matches : matches
    }
}

struct FocusLimitRules: Codable, Equatable {
    var apps = FocusLimitList()
    var websites = FocusLimitList()
}

struct FocusLimitRound: Codable, Equatable {
    let id: UUID
    let rules: FocusLimitRules
    var isGlobal: Bool? = nil
}

struct ActiveFocusLimitRound: Equatable {
    let round: FocusLimitRound
    let endsAt: Date
}

struct TimerSnapshot: Codable {
    let phase: TimerPhase
    let status: TimerStatus
    let remainingSeconds: TimeInterval
    let totalSeconds: TimeInterval
    let endDate: Date?
    let startedAt: Date?
    let completedRoundsInPlan: Int
    let pendingPhase: TimerPhase?
    let isOneOffFocus: Bool
    let preparedOneOffFocusMinutes: Int?
    let focusLimitRound: FocusLimitRound?

    private enum CodingKeys: String, CodingKey {
        case phase
        case status
        case remainingSeconds
        case totalSeconds
        case endDate
        case startedAt
        case completedRoundsInPlan = "completedFocusesInCycle"
        case pendingPhase
        case isOneOffFocus
        case preparedOneOffFocusMinutes
        case focusLimitRound
    }

    init(
        phase: TimerPhase,
        status: TimerStatus,
        remainingSeconds: TimeInterval,
        totalSeconds: TimeInterval,
        endDate: Date?,
        startedAt: Date?,
        completedRoundsInPlan: Int,
        pendingPhase: TimerPhase?,
        isOneOffFocus: Bool = false,
        preparedOneOffFocusMinutes: Int? = nil,
        focusLimitRound: FocusLimitRound? = nil
    ) {
        self.phase = phase
        self.status = status
        self.remainingSeconds = remainingSeconds
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        self.startedAt = startedAt
        self.completedRoundsInPlan = completedRoundsInPlan
        self.pendingPhase = pendingPhase
        self.isOneOffFocus = isOneOffFocus
        self.preparedOneOffFocusMinutes = preparedOneOffFocusMinutes
        self.focusLimitRound = focusLimitRound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(TimerPhase.self, forKey: .phase)
        status = try container.decode(TimerStatus.self, forKey: .status)
        remainingSeconds = try container.decode(TimeInterval.self, forKey: .remainingSeconds)
        totalSeconds = try container.decode(TimeInterval.self, forKey: .totalSeconds)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedRoundsInPlan = try container.decodeIfPresent(Int.self, forKey: .completedRoundsInPlan) ?? 0
        pendingPhase = try container.decodeIfPresent(TimerPhase.self, forKey: .pendingPhase)
        isOneOffFocus = try container.decodeIfPresent(Bool.self, forKey: .isOneOffFocus) ?? false
        preparedOneOffFocusMinutes = try container.decodeIfPresent(Int.self, forKey: .preparedOneOffFocusMinutes)
        focusLimitRound = try container.decodeIfPresent(FocusLimitRound.self, forKey: .focusLimitRound)
    }
}
