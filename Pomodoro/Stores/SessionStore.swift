import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    private let storageKey = "focusSessions.v1"
    private let defaults: UserDefaults

    @Published private(set) var sessions: [FocusSession] = []

    init(defaults: UserDefaults = .standard) {
        AppDataMigration.migrateStandardDefaultsIfNeeded(defaults)
        self.defaults = defaults
        load()
    }

    var todayCompletedFocusSessions: [FocusSession] {
        sessions.filter {
            $0.phase == .focus && $0.completed && Calendar.current.isDateInToday($0.endedAt)
        }
    }

    var todayFocusCount: Int { todayCompletedFocusSessions.count }

    var todayFocusSeconds: TimeInterval {
        todayCompletedFocusSessions.reduce(0) { $0 + $1.plannedDuration }
    }

    var completedFocusSessions: [FocusSession] {
        sessions.filter { $0.phase == .focus && $0.completed }
    }

    var totalFocusCount: Int { completedFocusSessions.count }

    var totalFocusSeconds: TimeInterval {
        completedFocusSessions.reduce(0) { $0 + $1.actualDuration }
    }

    var sessionsNewestFirst: [FocusSession] {
        sessions.sorted { $0.endedAt > $1.endedAt }
    }

    var recentSessions: [FocusSession] {
        Array(sessionsNewestFirst.prefix(5))
    }

    func add(_ session: FocusSession) {
        sessions.append(session)
        save()
    }

    func clear() {
        sessions.removeAll()
        save()
    }

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([FocusSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
