import Foundation

struct FocusSession: Codable, Identifiable, Equatable {
    let id: UUID
    let phase: TimerPhase
    let startedAt: Date
    let endedAt: Date
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let completed: Bool

    init(
        id: UUID = UUID(),
        phase: TimerPhase,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        completed: Bool
    ) {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDuration = plannedDuration
        self.actualDuration = actualDuration
        self.completed = completed
    }
}
