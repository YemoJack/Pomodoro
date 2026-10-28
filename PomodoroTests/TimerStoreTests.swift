import XCTest

@MainActor
final class TimerStoreTests: XCTestCase {
    func testStartPauseAndResume() {
        let context = makeContext()
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.start(phase: .focus)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.phase, .focus)

        timer.pause()
        XCTAssertEqual(timer.status, .paused)

        timer.resume()
        XCTAssertEqual(timer.status, .running)
    }

    func testPreparedOneOffFocusUsesTemporaryDurationWithoutChangingSettings() {
        let context = makeContext()
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.prepareOneOffFocus(minutes: 37)
        timer.performPrimaryAction()

        XCTAssertEqual(timer.status, .running)
        XCTAssertTrue(timer.isOneOffFocus)
        XCTAssertNil(timer.preparedOneOffFocusMinutes)
        XCTAssertEqual(timer.totalSeconds, 37 * 60)
        XCTAssertEqual(context.settings.focusMinutes, 25)
        XCTAssertEqual(timer.cycleDescription, "单次专注")
    }

    func testCustomAndOneOffFocusDurationsUseSeparateUpperBounds() {
        let context = makeContext()
        context.settings.focusMinutes = TimerDurationLimits.customFocusMinutes + 30

        let restored = SettingsStore(defaults: context.defaults)
        XCTAssertEqual(restored.focusMinutes, TimerDurationLimits.customFocusMinutes)

        let timer = TimerStore(
            settings: restored,
            sessions: context.sessions,
            defaults: UserDefaults(suiteName: "OneOffLimitTests.\(UUID().uuidString)")!
        )
        timer.prepareOneOffFocus(minutes: TimerDurationLimits.oneOffFocusMinutes + 30)

        XCTAssertEqual(timer.preparedOneOffFocusMinutes, TimerDurationLimits.oneOffFocusMinutes)
    }

    func testCompletedOneOffFocusDoesNotStartBreakAndNextStartUsesPlan() throws {
        let context = makeContext()
        context.settings.autoStartBreaks = true
        let snapshot = TimerSnapshot(
            phase: .focus,
            status: .running,
            remainingSeconds: 0,
            totalSeconds: 60,
            endDate: Date().addingTimeInterval(-1),
            startedAt: Date().addingTimeInterval(-61),
            completedRoundsInPlan: 0,
            pendingPhase: nil,
            isOneOffFocus: true
        )
        context.defaults.set(try JSONEncoder().encode(snapshot), forKey: "timerSnapshot.v1")

        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertTrue(timer.isOneOffFocus)
        XCTAssertEqual(timer.cycleDescription, "单次专注已结束")
        XCTAssertEqual(context.sessions.todayFocusCount, 1)

        timer.performPrimaryAction()

        XCTAssertEqual(timer.status, .running)
        XCTAssertFalse(timer.isOneOffFocus)
        XCTAssertEqual(timer.totalSeconds, 25 * 60)
        XCTAssertEqual(timer.cycleDescription, "第 1 / 4 轮")
    }

    func testEndingFocusDoesNotCountAsCompleted() {
        let context = makeContext()
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.start(phase: .focus)
        timer.endCurrentCycle()

        XCTAssertEqual(timer.status, .idle)
        XCTAssertEqual(context.sessions.todayFocusCount, 0)
        XCTAssertEqual(context.sessions.sessions.count, 1)
        XCTAssertFalse(context.sessions.sessions[0].completed)
    }

    func testSkippingBreakStartsFocus() {
        let context = makeContext()
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.start(phase: .shortBreak)
        timer.skipCurrentPhase()

        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.completedRoundsInPlan, 0)
    }

    func testSkippingFocusAdvancesRoundAndStartsBreak() {
        let context = makeContext()
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.start(phase: .focus)
        timer.skipCurrentPhase()

        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
        XCTAssertEqual(timer.cycleDescription, "第 1 / 4 轮休息")
        XCTAssertEqual(context.sessions.todayFocusCount, 0)
        XCTAssertFalse(context.sessions.sessions[0].completed)

        timer.skipCurrentPhase()
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
        XCTAssertEqual(timer.cycleDescription, "第 2 / 4 轮")
    }

    func testSkippingLastFocusFinishesPlanWithoutBreak() {
        let context = makeContext()
        context.settings.totalRounds = 1
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.start(phase: .focus)
        timer.skipCurrentPhase()

        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.primaryActionTitle, "重新开始")
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
        XCTAssertEqual(context.sessions.todayFocusCount, 0)
    }

    func testCompletedFocusWaitsForBreakBeforeFinalRound() throws {
        let context = makeContext()
        context.settings.totalRounds = 2
        try storeExpiredFocusSnapshot(defaults: context.defaults)

        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.primaryActionTitle, "开始休息")
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
        XCTAssertEqual(context.sessions.todayFocusCount, 1)
        XCTAssertEqual(timer.focusCompletionEventID, 1)
    }

    func testSkippedFocusDoesNotEmitCompletionPresentationEvent() {
        let context = makeContext()
        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        timer.start(phase: .focus)
        timer.skipCurrentPhase()

        XCTAssertEqual(timer.focusCompletionEventID, 0)
    }

    func testCompletedFinalFocusFinishesPlanWithoutBreak() throws {
        let context = makeContext()
        context.settings.totalRounds = 1
        try storeExpiredFocusSnapshot(defaults: context.defaults)

        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.primaryActionTitle, "重新开始")
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
        XCTAssertEqual(context.sessions.todayFocusCount, 1)
    }

    func testRestartPlanFromCompletedTransitionStartsFirstFocusRound() throws {
        let context = makeContext()
        context.settings.totalRounds = 2
        try storeExpiredFocusSnapshot(defaults: context.defaults)

        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.completedRoundsInPlan, 1)

        timer.restartPlan()

        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.completedRoundsInPlan, 0)
        XCTAssertEqual(timer.cycleDescription, "第 1 / 2 轮")
    }

    func testSettingsExposeFocusBreakAndRoundValues() {
        let context = makeContext()
        XCTAssertEqual(context.settings.focusMinutes, 25)
        XCTAssertEqual(context.settings.breakMinutes, 5)
        XCTAssertEqual(context.settings.totalRounds, 4)

        context.settings.focusMinutes = 40
        context.settings.breakMinutes = 10
        context.settings.totalRounds = 6

        let restored = SettingsStore(defaults: context.defaults)
        XCTAssertEqual(restored.focusMinutes, 40)
        XCTAssertEqual(restored.breakMinutes, 10)
        XCTAssertEqual(restored.totalRounds, 6)
    }

    func testFullScreenCompletionSettingsPersist() {
        let context = makeContext()
        XCTAssertTrue(context.settings.fullScreenCompletionEnabled)
        XCTAssertEqual(context.settings.fullScreenCompletionOpacity, 0.7)
        XCTAssertEqual(context.settings.fullScreenCompletionDuration, 4)

        context.settings.fullScreenCompletionEnabled = false
        context.settings.fullScreenCompletionOpacity = 0.45
        context.settings.fullScreenCompletionDuration = 8

        let restored = SettingsStore(defaults: context.defaults)
        XCTAssertFalse(restored.fullScreenCompletionEnabled)
        XCTAssertEqual(restored.fullScreenCompletionOpacity, 0.45)
        XCTAssertEqual(restored.fullScreenCompletionDuration, 8)
    }

    func testCustomSoundSettingsPersist() throws {
        let context = makeContext()
        let soundURL = try makeTemporarySoundFile(named: "class-bell.mp3")
        defer { try? FileManager.default.removeItem(at: soundURL.deletingLastPathComponent()) }
        let cue = TimerSoundCue.breakCompleted

        try context.settings.setCustomSoundFile(soundURL, for: cue)

        let restored = SettingsStore(defaults: context.defaults)
        let restoredConfiguration = restored.soundConfiguration(for: cue)
        XCTAssertEqual(restoredConfiguration.mode, .custom)
        XCTAssertNotEqual(restoredConfiguration.customSoundURL, soundURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredConfiguration.customSoundURL!.path))
        XCTAssertEqual(restored.customSoundFileName(for: cue), "class-bell.mp3")

        let importedURL = restoredConfiguration.customSoundURL!
        restored.clearCustomSoundFile(for: cue)
        XCTAssertEqual(restored.soundConfiguration(for: cue).mode, .system)
        XCTAssertNil(restored.soundConfiguration(for: cue).customSoundURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testSoundCueConfigurationsRemainIndependent() throws {
        let context = makeContext()
        let focusURL = try makeTemporarySoundFile(named: "focus.wav")
        let planURL = try makeTemporarySoundFile(named: "plan.mp3")
        defer {
            try? FileManager.default.removeItem(at: focusURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: planURL.deletingLastPathComponent())
        }

        try context.settings.setCustomSoundFile(focusURL, for: .focusCompleted)
        try context.settings.setCustomSoundFile(planURL, for: .planCompleted)

        let restored = SettingsStore(defaults: context.defaults)
        XCTAssertEqual(restored.customSoundFileName(for: .focusCompleted), "focus.wav")
        XCTAssertEqual(restored.soundConfiguration(for: .breakCompleted).mode, .system)
        XCTAssertEqual(restored.customSoundFileName(for: .planCompleted), "plan.mp3")

        restored.clearCustomSoundFile(for: .focusCompleted)
        restored.clearCustomSoundFile(for: .planCompleted)
    }

    func testApplyingPresetUpdatesAndPersistsTimingValues() {
        let context = makeContext()
        let classroom = context.settings.presets.first { $0.id == "starter.classroom" }!

        context.settings.apply(classroom)

        XCTAssertEqual(context.settings.activePreset?.id, classroom.id)
        XCTAssertEqual(context.settings.focusMinutes, 45)
        XCTAssertEqual(context.settings.breakMinutes, 10)
        XCTAssertEqual(context.settings.totalRounds, 4)
        XCTAssertTrue(context.settings.autoStartBreaks)
        XCTAssertTrue(context.settings.autoStartFocus)

        let restored = SettingsStore(defaults: context.defaults)
        XCTAssertEqual(restored.activePreset?.id, classroom.id)
    }

    func testSelectingCustomKeepsCurrentValuesAndClearsPresetSelection() {
        let context = makeContext()
        let classroom = context.settings.presets.first { $0.id == "starter.classroom" }!
        context.settings.apply(classroom)

        context.settings.selectCustom()

        XCTAssertNil(context.settings.activePreset)
        XCTAssertEqual(context.settings.focusMinutes, 45)
        XCTAssertEqual(context.settings.breakMinutes, 10)
        XCTAssertEqual(context.settings.totalRounds, 4)
    }

    func testCustomPresetCanBeCreatedUpdatedDeletedAndRestored() {
        let context = makeContext()
        let created = context.settings.createPreset(
            name: "  我的课程  ",
            focusMinutes: 40,
            breakMinutes: 8,
            rounds: 5,
            autoStartBreaks: true,
            autoStartFocus: false
        )

        XCTAssertEqual(created.name, "我的课程")
        XCTAssertEqual(context.settings.activePreset?.id, created.id)

        var updated = created
        updated.name = "晚间课程"
        updated.focusMinutes = 35
        updated.autoStartFocus = true
        context.settings.updatePreset(updated)

        XCTAssertEqual(context.settings.activePreset?.name, "晚间课程")
        XCTAssertEqual(context.settings.focusMinutes, 35)
        XCTAssertTrue(context.settings.autoStartFocus)

        let restored = SettingsStore(defaults: context.defaults)
        XCTAssertEqual(restored.activePreset?.name, "晚间课程")

        restored.deletePreset(id: created.id)
        XCTAssertNil(restored.activePreset)
        XCTAssertFalse(restored.presets.contains { $0.id == created.id })
    }

    func testDefaultPresetCannotBeUpdatedOrDeleted() {
        let context = makeContext()
        var changedDefault = TimerPreset.defaultPreset
        changedDefault.name = "已修改"
        changedDefault.focusMinutes = 99

        context.settings.updatePreset(changedDefault)
        context.settings.deletePreset(id: TimerPreset.defaultID)

        let defaultPreset = context.settings.presets.first { $0.id == TimerPreset.defaultID }
        XCTAssertEqual(defaultPreset, .defaultPreset)
    }

    func testCompletedFocusAutomaticallyStartsBreakWhenEnabled() throws {
        let context = makeContext()
        context.settings.totalRounds = 2
        context.settings.autoStartBreaks = true
        try storeExpiredFocusSnapshot(defaults: context.defaults)

        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
    }

    func testCompletedBreakAutomaticallyStartsFocusWhenEnabled() throws {
        let context = makeContext()
        context.settings.totalRounds = 2
        context.settings.autoStartFocus = true
        try storeExpiredBreakSnapshot(defaults: context.defaults)

        let timer = TimerStore(
            settings: context.settings,
            sessions: context.sessions,
            defaults: context.defaults
        )

        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.completedRoundsInPlan, 1)
    }

    private func storeExpiredFocusSnapshot(defaults: UserDefaults) throws {
        let snapshot = TimerSnapshot(
            phase: .focus,
            status: .running,
            remainingSeconds: 0,
            totalSeconds: 60,
            endDate: Date().addingTimeInterval(-1),
            startedAt: Date().addingTimeInterval(-61),
            completedRoundsInPlan: 0,
            pendingPhase: nil
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "timerSnapshot.v1")
    }

    private func storeExpiredBreakSnapshot(defaults: UserDefaults) throws {
        let snapshot = TimerSnapshot(
            phase: .shortBreak,
            status: .running,
            remainingSeconds: 0,
            totalSeconds: 60,
            endDate: Date().addingTimeInterval(-1),
            startedAt: Date().addingTimeInterval(-61),
            completedRoundsInPlan: 1,
            pendingPhase: nil
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "timerSnapshot.v1")
    }

    private func makeContext() -> (
        defaults: UserDefaults,
        settings: SettingsStore,
        sessions: SessionStore
    ) {
        let defaults = UserDefaults(suiteName: "TimerStoreTests.\(UUID().uuidString)")!
        return (
            defaults,
            SettingsStore(defaults: defaults),
            SessionStore(defaults: defaults)
        )
    }

    private func makeTemporarySoundFile(named fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PomodoroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try Data([0x00, 0x01, 0x02]).write(to: fileURL)
        return fileURL
    }
}
