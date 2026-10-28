import XCTest

@MainActor
final class SessionStoreTests: XCTestCase {
    func testMigratesLegacyDefaultsOnlyOnce() {
        let targetSuiteName = "AppDataMigrationTests.Target.\(UUID().uuidString)"
        let legacySuiteName = "AppDataMigrationTests.Legacy.\(UUID().uuidString)"
        let markerKey = "migration.complete"
        let defaults = UserDefaults(suiteName: targetSuiteName)!

        defaults.removePersistentDomain(forName: targetSuiteName)
        defaults.setPersistentDomain(
            [
                "settings.focusMinutes": 42,
                "focusSessions.v1": Data([1, 2, 3])
            ],
            forName: legacySuiteName
        )
        defer {
            defaults.removePersistentDomain(forName: targetSuiteName)
            defaults.removePersistentDomain(forName: legacySuiteName)
        }

        AppDataMigration.migrateIfNeeded(
            defaults: defaults,
            legacyDomainName: legacySuiteName,
            markerKey: markerKey
        )

        XCTAssertEqual(defaults.integer(forKey: "settings.focusMinutes"), 42)
        XCTAssertEqual(defaults.data(forKey: "focusSessions.v1"), Data([1, 2, 3]))
        XCTAssertTrue(defaults.bool(forKey: markerKey))

        defaults.set(25, forKey: "settings.focusMinutes")
        defaults.setPersistentDomain(
            ["settings.focusMinutes": 60],
            forName: legacySuiteName
        )

        AppDataMigration.migrateIfNeeded(
            defaults: defaults,
            legacyDomainName: legacySuiteName,
            markerKey: markerKey
        )

        XCTAssertEqual(defaults.integer(forKey: "settings.focusMinutes"), 25)
    }

    func testTodayStatisticsOnlyIncludeCompletedFocusSessions() {
        let defaults = UserDefaults(suiteName: "SessionStoreTests.\(UUID().uuidString)")!
        let store = SessionStore(defaults: defaults)
        let now = Date()

        store.add(FocusSession(
            phase: .focus,
            startedAt: now.addingTimeInterval(-1500),
            endedAt: now,
            plannedDuration: 1500,
            actualDuration: 1500,
            completed: true
        ))
        store.add(FocusSession(
            phase: .focus,
            startedAt: now.addingTimeInterval(-300),
            endedAt: now,
            plannedDuration: 1500,
            actualDuration: 300,
            completed: false
        ))
        store.add(FocusSession(
            phase: .shortBreak,
            startedAt: now.addingTimeInterval(-300),
            endedAt: now,
            plannedDuration: 300,
            actualDuration: 300,
            completed: true
        ))

        XCTAssertEqual(store.todayFocusCount, 1)
        XCTAssertEqual(store.todayFocusSeconds, 1500)
        XCTAssertEqual(store.totalFocusCount, 1)
        XCTAssertEqual(store.totalFocusSeconds, 1500)
        XCTAssertEqual(store.sessionsNewestFirst.count, 3)
    }
}
