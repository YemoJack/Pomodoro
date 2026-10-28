import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var sessions: SessionStore

    let onStartFocus: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("今天")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 12) {
                    statCard(value: "\(sessions.todayFocusCount)", label: "完成番茄", symbol: "checkmark.circle.fill")
                    statCard(value: focusTimeText, label: "专注时间", symbol: "clock.fill")
                }

                Text("最近记录")
                    .font(.headline)

                if sessions.recentSessions.isEmpty {
                    ContentUnavailableView {
                        Label("今天还没有记录", systemImage: "timer")
                    } description: {
                        Text("开始第一轮专注，让复习进入状态。")
                    } actions: {
                        Button("开始专注", action: onStartFocus)
                            .buttonStyle(InteractiveButtonStyle(kind: .prominent))
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(sessions.recentSessions) { session in
                            sessionRow(session)
                            if session.id != sessions.recentSessions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
    }

    private var focusTimeText: String {
        let minutes = Int(sessions.todayFocusSeconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)时\(minutes % 60)分"
        }
        return "\(minutes)分钟"
    }

    private func statCard(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sessionRow(_ session: FocusSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.completed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(session.completed ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.phase.isFocus ? (session.completed ? "专注完成" : "专注未完成") : "休息完成")
                Text(session.endedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(session.plannedDuration / 60)) 分钟")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}
