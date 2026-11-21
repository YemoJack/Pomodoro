import SwiftUI

struct TimerView: View {
    @EnvironmentObject private var timer: TimerStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var notifications: NotificationService

    @State private var showsNotificationPrimer = false
    @State private var adjustedOneOffMinutes: Int?
    @State private var lastRotationAngle: Double?
    @State private var rotationMinutes = 0.0
    @State private var isPressingRing = false
    @State private var longPressProgress = 0.0
    @State private var longPressFeedbackCancelled = false

    private let longPressDuration = 0.45

    private var phaseColor: Color {
        timer.phase.isFocus ? .accentColor : .green
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Label(timer.statusTitle, systemImage: timer.status == .completed ? "checkmark.circle.fill" : timer.phase.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(timer.status == .completed ? .green : .primary)

                ZStack {
                    ProgressRingView(
                        progress: displayedRingProgress,
                        color: phaseColor,
                        isPaused: timer.status == .paused
                    )
                    .overlay {
                        if isPressingRing || adjustedOneOffMinutes != nil {
                            Circle()
                                .trim(from: 0, to: longPressProgress)
                                .stroke(
                                    Color.accentColor,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .padding(-8)
                                .shadow(
                                    color: Color.accentColor.opacity(adjustedOneOffMinutes == nil ? 0.35 : 0.7),
                                    radius: adjustedOneOffMinutes == nil ? 4 : 8
                                )
                                .transition(.opacity)
                        }
                    }

                    VStack(spacing: 8) {
                        Text(displayedTime)
                            .font(.system(size: 58, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        if isPressingRing && adjustedOneOffMinutes == nil {
                            Text("继续按住…")
                                .foregroundStyle(.secondary)
                        } else if adjustedOneOffMinutes != nil {
                            Text("旋转调整 · 松开保存")
                                .foregroundStyle(.secondary)
                        } else if timer.preparedOneOffFocusMinutes != nil {
                            Text("下一次仅进行这一轮专注")
                                .foregroundStyle(.secondary)
                        } else if timer.status == .completed {
                            Text(completionMessage)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(timer.cycleDescription)
                                .foregroundStyle(.secondary)
                        }

                        if timer.canPrepareOneOffFocus {
                            Text("长按圆环并旋转，可调整单次专注时长")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .scaleEffect(adjustedOneOffMinutes != nil ? 1.02 : (isPressingRing ? 0.985 : 1))
                .animation(.easeOut(duration: 0.12), value: isPressingRing)
                .animation(.spring(response: 0.24, dampingFraction: 0.58), value: adjustedOneOffMinutes != nil)
                .contentShape(Circle())
                .gesture(
                    oneOffDurationGesture,
                    including: timer.canPrepareOneOffFocus ? .all : .none
                )
                .simultaneousGesture(
                    longPressFeedbackGesture,
                    including: timer.canPrepareOneOffFocus ? .all : .none
                )
                .help("长按并沿圆环旋转，设置下一次单次专注时长")
                .padding(.vertical, 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("剩余\(timer.phase.title)时间，\(accessibleTime)")

                if timer.isGlobalFocusLocked {
                    GlobalFocusExitButton(timer: timer)
                } else {
                    Button(action: primaryAction) {
                        Label(timer.primaryActionTitle, systemImage: primarySymbol)
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .prominent))
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                }

                HStack(spacing: 24) {
                    if timer.isActive && !timer.isGlobalFocusLocked {
                        Button(timer.phase.isFocus ? "跳过阶段" : "跳过休息") {
                            confirmSkip()
                        }
                        .buttonStyle(InteractiveButtonStyle(kind: .quiet))

                        Button(timer.phase.isFocus ? "结束计时" : "结束循环") {
                            confirmEnd()
                        }
                        .buttonStyle(InteractiveButtonStyle(kind: .destructive))
                    } else if timer.status == .completed && !timer.isPlanCompleted {
                        Button("结束并重新开始") {
                            timer.restartPlan()
                        }
                        .buttonStyle(InteractiveButtonStyle(kind: .quiet))
                    }
                }
                .frame(height: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 20) {
                Toggle(settings.globalFocusLimitEnabled ? "全局限制" : "专注限制",
                       isOn: $settings.focusLimitsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(timer.isGlobalFocusLocked)
                    .help(settings.globalFocusLimitEnabled ? "全局限制从下一轮专注开始" : "启用或关闭专注限制")
                Spacer(minLength: 0)
                summaryItem(value: "\(sessions.todayFocusCount)", label: "完成番茄")
                summaryItem(value: formattedTodayMinutes, label: "专注时间")
            }
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showsNotificationPrimer) {
            NotificationPrimerView {
                settings.notificationExplanationSeen = true
                showsNotificationPrimer = false
                timer.performPrimaryAction()
                Task { await notifications.requestAuthorization() }
            } onSkip: {
                settings.notificationExplanationSeen = true
                showsNotificationPrimer = false
                timer.performPrimaryAction()
            }
        }
    }

    private var completionMessage: String {
        if timer.isOneOffFocus {
            return "本次单次专注已结束"
        }
        if timer.isPlanCompleted {
            return "本次专注计划已结束"
        }
        return timer.phase.isFocus ? "完成一个番茄" : "休息完成"
    }

    private var primarySymbol: String {
        timer.status == .running ? "pause.fill" : "play.fill"
    }

    private var formattedTodayMinutes: String {
        "\(Int(sessions.todayFocusSeconds / 60)) 分钟"
    }

    private var accessibleTime: String {
        if let minutes = displayedOneOffMinutes {
            return "\(minutes) 分 0 秒"
        }
        let seconds = max(Int(ceil(timer.remainingSeconds)), 0)
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }

    private var displayedOneOffMinutes: Int? {
        (adjustedOneOffMinutes ?? timer.preparedOneOffFocusMinutes).map {
            min(max($0, 1), TimerDurationLimits.oneOffFocusMinutes)
        }
    }

    private var displayedTime: String {
        guard let minutes = displayedOneOffMinutes else { return timer.formattedTime }
        return String(format: "%02d:00", minutes)
    }

    private var displayedRingProgress: Double {
        if let minutes = displayedOneOffMinutes {
            return Double(minutes) / Double(TimerDurationLimits.oneOffFocusMinutes)
        }
        return timer.status == .idle ? 0 : timer.progress
    }

    private var oneOffDurationGesture: some Gesture {
        LongPressGesture(minimumDuration: longPressDuration, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard timer.canPrepareOneOffFocus else { return }
                guard case .second(true, let dragValue) = value, let dragValue else { return }

                let angle = rotationAngle(at: dragValue.location)
                if adjustedOneOffMinutes == nil {
                    let initialMinutes = min(
                        timer.preparedOneOffFocusMinutes ?? settings.focusMinutes,
                        TimerDurationLimits.oneOffFocusMinutes
                    )
                    adjustedOneOffMinutes = initialMinutes
                    rotationMinutes = Double(initialMinutes)
                    lastRotationAngle = angle
                    return
                }

                guard let lastRotationAngle else { return }
                var delta = angle - lastRotationAngle
                if delta > 180 {
                    delta -= 360
                } else if delta < -180 {
                    delta += 360
                }

                rotationMinutes = min(
                    max(rotationMinutes + delta / 6, 1),
                    Double(TimerDurationLimits.oneOffFocusMinutes)
                )
                adjustedOneOffMinutes = Int(rotationMinutes.rounded())
                self.lastRotationAngle = angle
            }
            .onEnded { _ in
                if let adjustedOneOffMinutes {
                    timer.prepareOneOffFocus(minutes: adjustedOneOffMinutes)
                }
                adjustedOneOffMinutes = nil
                lastRotationAngle = nil
                resetLongPressFeedback()
            }
    }

    private var longPressFeedbackGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard timer.canPrepareOneOffFocus else { return }

                let distance = hypot(value.translation.width, value.translation.height)
                if distance > 12, adjustedOneOffMinutes == nil {
                    longPressFeedbackCancelled = true
                    resetLongPressFeedback()
                    return
                }

                guard !longPressFeedbackCancelled, !isPressingRing else { return }
                isPressingRing = true
                longPressProgress = 0
                withAnimation(.linear(duration: longPressDuration)) {
                    longPressProgress = 1
                }
            }
            .onEnded { _ in
                longPressFeedbackCancelled = false
                resetLongPressFeedback()
            }
    }

    private func resetLongPressFeedback() {
        isPressingRing = false
        longPressProgress = 0
    }

    private func rotationAngle(at location: CGPoint) -> Double {
        let center = CGPoint(x: 110, y: 110)
        return atan2(location.y - center.y, location.x - center.x) * 180 / .pi
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 100)
    }

    private func primaryAction() {
        if timer.status == .idle && !settings.notificationExplanationSeen {
            showsNotificationPrimer = true
        } else {
            if timer.status == .idle && settings.notificationsEnabled {
                notifications.requestAuthorizationIfNeeded()
            }
            timer.performPrimaryAction()
        }
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

private struct NotificationPrimerView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            Text("在阶段结束时提醒你")
                .font(.title3.weight(.semibold))

            Text("允许通知后，即使主窗口已关闭，你也能及时知道专注或休息已经结束。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            HStack {
                Button("暂不允许", action: onSkip)
                    .buttonStyle(InteractiveButtonStyle(kind: .secondary))
                Button("允许通知", action: onAllow)
                    .buttonStyle(InteractiveButtonStyle(kind: .prominent))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 400)
    }
}
