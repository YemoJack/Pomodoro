import Combine
import Foundation

enum AppDataMigration {
    static let legacyBundleIdentifier = "com.local.Pomodoro"
    static let currentBundleIdentifier = "com.ruidouwang.Pomodoro"
    static let migrationKey = "appDataMigration.com.local.Pomodoro.v1"

    static func migrateStandardDefaultsIfNeeded(_ defaults: UserDefaults) {
        guard defaults === UserDefaults.standard else { return }
        migrateIfNeeded(defaults: defaults)
    }

    static func migrateIfNeeded(
        defaults: UserDefaults,
        legacyDomainName: String = legacyBundleIdentifier,
        markerKey: String = migrationKey
    ) {
        guard !defaults.bool(forKey: markerKey) else { return }

        if let legacyDomain = defaults.persistentDomain(forName: legacyDomainName) {
            for (key, value) in legacyDomain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: markerKey)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let focusMinutes = "settings.focusMinutes"
        static let breakMinutes = "settings.breakMinutes"
        static let totalRounds = "settings.totalRounds"
        static let legacyShortBreakMinutes = "settings.shortBreakMinutes"
        static let legacyLongBreakInterval = "settings.longBreakInterval"
        static let autoStartBreaks = "settings.autoStartBreaks"
        static let autoStartFocus = "settings.autoStartFocus"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let soundEnabled = "settings.soundEnabled"
        static let notificationExplanationSeen = "settings.notificationExplanationSeen"
        static let fullScreenCompletionEnabled = "settings.fullScreenCompletionEnabled"
        static let fullScreenCompletionOpacity = "settings.fullScreenCompletionOpacity"
        static let fullScreenCompletionDuration = "settings.fullScreenCompletionDuration"
        static let timerPresets = "settings.timerPresets.v1"
        static let selectedPresetID = "settings.selectedTimerPresetID"
        static let focusLimitsEnabled = "settings.focusLimitsEnabled"
        static let globalFocusLimitEnabled = "settings.globalFocusLimitEnabled"
        static let focusLimitRules = "settings.focusLimitRules.v1"
        static let completionSoundMode = "settings.completionSoundMode"
        static let customSoundPath = "settings.customSoundPath"
        static let soundConfigurations = "settings.soundConfigurations.v1"
    }

    private let defaults: UserDefaults
    private var isApplyingPreset = false

    @Published var focusLimitsEnabled: Bool {
        didSet { defaults.set(focusLimitsEnabled, forKey: Key.focusLimitsEnabled) }
    }
    @Published var globalFocusLimitEnabled: Bool {
        didSet { defaults.set(globalFocusLimitEnabled, forKey: Key.globalFocusLimitEnabled) }
    }
    @Published var focusLimitRules: FocusLimitRules {
        didSet {
            if let data = try? JSONEncoder().encode(focusLimitRules) {
                defaults.set(data, forKey: Key.focusLimitRules)
            }
        }
    }

    @Published var focusMinutes: Int { didSet { saveSetting(focusMinutes, key: Key.focusMinutes) } }
    @Published var breakMinutes: Int { didSet { saveSetting(breakMinutes, key: Key.breakMinutes) } }
    @Published var totalRounds: Int { didSet { saveSetting(totalRounds, key: Key.totalRounds) } }
    @Published var autoStartBreaks: Bool { didSet { saveSetting(autoStartBreaks, key: Key.autoStartBreaks) } }
    @Published var autoStartFocus: Bool { didSet { saveSetting(autoStartFocus, key: Key.autoStartFocus) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    @Published var notificationExplanationSeen: Bool { didSet { defaults.set(notificationExplanationSeen, forKey: Key.notificationExplanationSeen) } }
    @Published var fullScreenCompletionEnabled: Bool { didSet { defaults.set(fullScreenCompletionEnabled, forKey: Key.fullScreenCompletionEnabled) } }
    @Published var fullScreenCompletionOpacity: Double { didSet { defaults.set(fullScreenCompletionOpacity, forKey: Key.fullScreenCompletionOpacity) } }
    @Published var fullScreenCompletionDuration: Int { didSet { defaults.set(fullScreenCompletionDuration, forKey: Key.fullScreenCompletionDuration) } }
    @Published private(set) var soundConfigurations: [String: TimerSoundConfiguration]
    @Published private(set) var presets: [TimerPreset]
    @Published private(set) var selectedPresetID: String?

    init(defaults: UserDefaults = .standard) {
        AppDataMigration.migrateStandardDefaultsIfNeeded(defaults)
        self.defaults = defaults
        focusLimitsEnabled = defaults.bool(forKey: Key.focusLimitsEnabled)
        globalFocusLimitEnabled = defaults.bool(forKey: Key.globalFocusLimitEnabled)
        focusLimitRules = defaults.data(forKey: Key.focusLimitRules)
            .flatMap { try? JSONDecoder().decode(FocusLimitRules.self, from: $0) } ?? FocusLimitRules()
        let legacyBreakMinutes = defaults.object(forKey: Key.legacyShortBreakMinutes) as? Int ?? 5
        let legacyRounds = defaults.object(forKey: Key.legacyLongBreakInterval) as? Int ?? 4
        let legacySoundMode = defaults.string(forKey: Key.completionSoundMode)
            .flatMap(CompletionSoundMode.init(rawValue:))
        let legacySoundPath = defaults.string(forKey: Key.customSoundPath)
        defaults.register(defaults: [
            Key.focusMinutes: 25,
            Key.breakMinutes: legacyBreakMinutes,
            Key.totalRounds: legacyRounds,
            Key.autoStartBreaks: false,
            Key.autoStartFocus: false,
            Key.notificationsEnabled: true,
            Key.soundEnabled: true,
            Key.notificationExplanationSeen: false,
            Key.fullScreenCompletionEnabled: true,
            Key.fullScreenCompletionOpacity: 0.7,
            Key.fullScreenCompletionDuration: 4,
            Key.completionSoundMode: CompletionSoundMode.system.rawValue
        ])

        focusMinutes = min(max(defaults.integer(forKey: Key.focusMinutes), 1), TimerDurationLimits.customFocusMinutes)
        breakMinutes = min(max(defaults.integer(forKey: Key.breakMinutes), 1), 60)
        totalRounds = min(max(defaults.integer(forKey: Key.totalRounds), 1), 12)
        autoStartBreaks = defaults.bool(forKey: Key.autoStartBreaks)
        autoStartFocus = defaults.bool(forKey: Key.autoStartFocus)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        notificationExplanationSeen = defaults.bool(forKey: Key.notificationExplanationSeen)
        fullScreenCompletionEnabled = defaults.bool(forKey: Key.fullScreenCompletionEnabled)
        fullScreenCompletionOpacity = min(max(defaults.double(forKey: Key.fullScreenCompletionOpacity), 0.2), 1)
        fullScreenCompletionDuration = min(max(defaults.integer(forKey: Key.fullScreenCompletionDuration), 1), 15)

        if let data = defaults.data(forKey: Key.soundConfigurations),
           let decoded = try? JSONDecoder().decode([String: TimerSoundConfiguration].self, from: data) {
            soundConfigurations = Self.normalizedSoundConfigurations(decoded)
        } else if legacySoundMode != nil || legacySoundPath != nil {
            let legacyConfiguration = TimerSoundConfiguration(
                mode: legacySoundMode ?? .system,
                customSoundPath: legacySoundPath,
                customSoundDisplayName: legacySoundPath.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                }
            )
            soundConfigurations = Dictionary(
                uniqueKeysWithValues: TimerSoundCue.allCases.map { ($0.rawValue, legacyConfiguration) }
            )
        } else {
            soundConfigurations = Dictionary(
                uniqueKeysWithValues: TimerSoundCue.allCases.map {
                    ($0.rawValue, TimerSoundConfiguration.defaultValue(for: $0))
                }
            )
        }

        if let data = defaults.data(forKey: Key.timerPresets),
           let decoded = try? JSONDecoder().decode([TimerPreset].self, from: data) {
            presets = Self.normalizedPresets(decoded)
        } else {
            presets = [TimerPreset.defaultPreset] + TimerPreset.starterPresets
        }

        let storedPresetID = defaults.string(forKey: Key.selectedPresetID)
        if presets.contains(where: { $0.id == storedPresetID }) {
            selectedPresetID = storedPresetID
        } else {
            selectedPresetID = presets.first(where: {
                $0.focusMinutes == focusMinutes
                    && $0.breakMinutes == breakMinutes
                    && $0.rounds == totalRounds
                    && $0.autoStartBreaks == autoStartBreaks
                    && $0.autoStartFocus == autoStartFocus
            })?.id
        }

        savePresets()
        saveSelectedPresetID()
        saveSoundConfigurations()
    }

    func duration(for phase: TimerPhase) -> TimeInterval {
        let minutes = switch phase {
        case .focus: focusMinutes
        case .shortBreak, .longBreak: breakMinutes
        }
        return TimeInterval(minutes * 60)
    }

    var activePreset: TimerPreset? {
        guard let selectedPresetID else { return nil }
        return presets.first { $0.id == selectedPresetID }
    }

    func apply(_ preset: TimerPreset) {
        guard presets.contains(where: { $0.id == preset.id }) else { return }
        isApplyingPreset = true
        focusMinutes = preset.focusMinutes
        breakMinutes = preset.breakMinutes
        totalRounds = preset.rounds
        autoStartBreaks = preset.autoStartBreaks
        autoStartFocus = preset.autoStartFocus
        isApplyingPreset = false
        selectedPresetID = preset.id
        saveSelectedPresetID()
    }

    func selectPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        apply(preset)
    }

    func selectCustom() {
        selectedPresetID = nil
        saveSelectedPresetID()
    }

    @discardableResult
    func createPreset(
        name: String,
        focusMinutes: Int,
        breakMinutes: Int,
        rounds: Int,
        autoStartBreaks: Bool,
        autoStartFocus: Bool
    ) -> TimerPreset {
        let preset = TimerPreset(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            focusMinutes: min(max(focusMinutes, 1), TimerDurationLimits.customFocusMinutes),
            breakMinutes: min(max(breakMinutes, 1), 60),
            rounds: min(max(rounds, 1), 12),
            autoStartBreaks: autoStartBreaks,
            autoStartFocus: autoStartFocus
        )
        presets.append(preset)
        savePresets()
        apply(preset)
        return preset
    }

    func updatePreset(_ preset: TimerPreset) {
        guard !preset.isDefault,
              let index = presets.firstIndex(where: { $0.id == preset.id })
        else { return }

        var updated = preset
        updated.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.focusMinutes = min(max(preset.focusMinutes, 1), TimerDurationLimits.customFocusMinutes)
        updated.breakMinutes = min(max(preset.breakMinutes, 1), 60)
        updated.rounds = min(max(preset.rounds, 1), 12)
        presets[index] = updated
        savePresets()

        if selectedPresetID == updated.id {
            apply(updated)
        }
    }

    func deletePreset(id: String) {
        guard id != TimerPreset.defaultID else { return }
        presets.removeAll { $0.id == id }
        savePresets()
        if selectedPresetID == id {
            selectCustom()
        }
    }

    func soundConfiguration(for cue: TimerSoundCue) -> TimerSoundConfiguration {
        soundConfigurations[cue.rawValue] ?? .defaultValue(for: cue)
    }

    func customSoundFileName(for cue: TimerSoundCue) -> String? {
        let configuration = soundConfiguration(for: cue)
        return configuration.customSoundDisplayName
            ?? configuration.customSoundURL?.lastPathComponent
    }

    func updateSoundConfiguration(
        _ configuration: TimerSoundConfiguration,
        for cue: TimerSoundCue
    ) {
        var configurations = soundConfigurations
        configurations[cue.rawValue] = configuration
        soundConfigurations = configurations
        saveSoundConfigurations()
    }

    func setCustomSoundFile(_ url: URL, for cue: TimerSoundCue) throws {
        let importedURL = try importCustomSoundFile(url, for: cue)
        var configuration = soundConfiguration(for: cue)
        let previousURL = configuration.customSoundURL
        configuration.customSoundPath = importedURL.path
        configuration.customSoundDisplayName = url.lastPathComponent
        configuration.mode = .custom
        updateSoundConfiguration(configuration, for: cue)
        removeManagedCustomSoundFile(previousURL, excluding: importedURL)
    }

    func clearCustomSoundFile(for cue: TimerSoundCue) {
        var configuration = soundConfiguration(for: cue)
        let previousURL = configuration.customSoundURL
        configuration.customSoundPath = nil
        configuration.customSoundDisplayName = nil
        configuration.mode = .system
        updateSoundConfiguration(configuration, for: cue)
        removeManagedCustomSoundFile(previousURL)
    }

    private func importCustomSoundFile(_ sourceURL: URL, for cue: TimerSoundCue) throws -> URL {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directory = try customSoundsDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension
        var fileName = "\(cue.rawValue)-\(UUID().uuidString)"
        if !fileExtension.isEmpty {
            fileName += ".\(fileExtension)"
        }
        let destinationURL = directory.appendingPathComponent(fileName, isDirectory: false)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw CustomSoundImportError.copyFailed(error)
        }
    }

    private func customSoundsDirectory() throws -> URL {
        do {
            return try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("com.local.Pomodoro", isDirectory: true)
            .appendingPathComponent("CustomSounds", isDirectory: true)
        } catch {
            throw CustomSoundImportError.storageUnavailable(error)
        }
    }

    private func removeManagedCustomSoundFile(_ url: URL?, excluding retainedURL: URL? = nil) {
        guard let url,
              url.standardizedFileURL != retainedURL?.standardizedFileURL,
              let directory = try? customSoundsDirectory(),
              url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
        else { return }

        try? FileManager.default.removeItem(at: url)
    }

    private func saveSetting<T>(_ value: T, key: String) {
        defaults.set(value, forKey: key)
        guard !isApplyingPreset else { return }
        selectCustom()
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Key.timerPresets)
    }

    private func saveSelectedPresetID() {
        if let selectedPresetID {
            defaults.set(selectedPresetID, forKey: Key.selectedPresetID)
        } else {
            defaults.removeObject(forKey: Key.selectedPresetID)
        }
    }

    private func saveSoundConfigurations() {
        guard let data = try? JSONEncoder().encode(soundConfigurations) else { return }
        defaults.set(data, forKey: Key.soundConfigurations)
    }

    private static func normalizedPresets(_ presets: [TimerPreset]) -> [TimerPreset] {
        var result = presets.filter { !$0.isDefault }
        result.insert(.defaultPreset, at: 0)
        return result
    }

    private static func normalizedSoundConfigurations(
        _ configurations: [String: TimerSoundConfiguration]
    ) -> [String: TimerSoundConfiguration] {
        Dictionary(uniqueKeysWithValues: TimerSoundCue.allCases.map { cue in
            (cue.rawValue, configurations[cue.rawValue] ?? .defaultValue(for: cue))
        })
    }
}

enum CustomSoundImportError: LocalizedError {
    case storageUnavailable(Error)
    case copyFailed(Error)

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "无法打开 App 的声音存储目录。"
        case .copyFailed:
            "无法复制该音乐文件，请确认文件仍然存在并允许访问。"
        }
    }
}
