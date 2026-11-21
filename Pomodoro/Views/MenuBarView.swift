import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var timer: TimerStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var focusLimits: FocusLimitService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            HStack {
                Label(timer.statusTitle, systemImage: timer.phase.symbol)
                Spacer()
                Text(timer.formattedTime)
                    .monospacedDigit()
            }

            if timer.isActive || timer.status == .completed {
                Text(timer.cycleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if timer.isGlobalFocusLocked {
                Button("强行终止…") {
                    Task { await timer.authenticateAndEndGlobalFocus() }
                }
                .disabled(timer.isAuthenticatingGlobalFocus)
            } else if timer.status == .idle {
                Button("开始专注") {
                    startFocus()
                }
            } else if timer.status == .completed {
                Button(timer.primaryActionTitle) {
                    timer.startPendingPhase()
                }
                if !timer.isPlanCompleted {
                    Button("结束并重新开始") {
                        timer.restartPlan()
                    }
                }
            } else {
                Button(timer.status == .running ? "暂停" : "继续") {
                    timer.performPrimaryAction()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button(timer.phase.isFocus ? "跳过当前阶段" : "跳过休息") {
                    confirmSkip()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("结束计时") {
                    confirmEnd()
                }
            }

            Divider()

            Menu("专注限制") {
                Toggle("启用专注限制", isOn: $settings.focusLimitsEnabled)
                    .disabled(timer.isGlobalFocusLocked)
                if settings.focusLimitRules.websites.isActive {
                    Text(focusLimits.chromeStatus)
                }
            }

            Text("今日完成 \(sessions.todayFocusCount) 个番茄")
            Text("今日专注 \(Int(sessions.todayFocusSeconds / 60)) 分钟")

            Divider()

            Button("打开番茄专注") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o", modifiers: .command)

            SettingsLink {
                Text("设置…")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("退出番茄专注") {
                NSApplication.shared.terminate(nil)
            }
            .disabled(timer.isGlobalFocusLocked)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func startFocus() {
        if !settings.notificationExplanationSeen {
            let shouldAllow = ConfirmationService.confirm(
                title: "在阶段结束时提醒你",
                message: "允许通知后，即使主窗口已关闭，你也能及时知道专注或休息已经结束。",
                confirmTitle: "允许通知"
            )
            settings.notificationExplanationSeen = true
            if shouldAllow {
                Task { await notifications.requestAuthorization() }
            }
        } else if settings.notificationsEnabled {
            notifications.requestAuthorizationIfNeeded()
        }
        timer.start(phase: .focus)
    }

    private func confirmSkip() {
        let message = timer.phase.isFocus
            ? (timer.isFinalFocusRound ? "本轮不会被记录为完成番茄，计划将直接结束。" : "本轮不会被记录为完成番茄。")
            : "将直接进入下一轮专注。"
        if ConfirmationService.confirm(
            title: timer.phase.isFocus ? "跳过本轮专注？" : "跳过当前休息？",
            message: message,
            confirmTitle: timer.phase.isFocus ? (timer.isFinalFocusRound ? "跳过并结束" : "跳过并休息") : "开始专注"
        ) {
            timer.skipCurrentPhase()
        }
    }

    private func confirmEnd() {
        if ConfirmationService.confirm(
            title: "结束当前计时？",
            message: "当前进度不会被记录为完成番茄。",
            confirmTitle: "结束计时",
            isDestructive: true
        ) {
            timer.endCurrentCycle()
        }
    }
}
