import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var notifications: NotificationService
    @State private var soundImportError: String?

    var body: some View {
        TabView {
            notificationView
            .tabItem { Label("通知", systemImage: "bell") }

            dataView
            .tabItem { Label("数据", systemImage: "externaldrive") }
        }
        .frame(width: 660, height: 640)
        .onAppear {
            notifications.refreshAuthorizationStatus()
        }
        .alert("无法导入音乐", isPresented: soundImportErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(soundImportError ?? "请选择其他音乐文件。")
        }
    }

    private var notificationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("通知与提示音")
                            .font(.headline)

                        HStack {
                            Text("通知权限")
                            Spacer()
                            Text(authorizationText)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Toggle("阶段完成时发送通知", isOn: $settings.notificationsEnabled)
                        Toggle("播放阶段完成提示音", isOn: $settings.soundEnabled)

                        HStack {
                            Button("发送测试通知") {
                                notifications.sendTestNotification()
                            }
                            .buttonStyle(InteractiveButtonStyle(kind: .secondary))

                            Text("用于检查系统权限和通知图标。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let deliveryError = notifications.lastDeliveryError {
                            Label(deliveryError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if notifications.authorizationStatus == .denied {
                            HStack(alignment: .firstTextBaseline) {
                                Text("系统通知已关闭，阶段完成时将不会显示通知。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("打开系统设置") {
                                    notifications.openSystemSettings()
                                }
                                .buttonStyle(InteractiveButtonStyle(kind: .secondary))
                            }
                        } else if notifications.authorizationStatus == .notDetermined {
                            Button("允许通知") {
                                Task { await notifications.requestAuthorization() }
                            }
                            .buttonStyle(InteractiveButtonStyle(kind: .secondary))
                        }
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("全屏完成提示")
                            .font(.headline)

                        Toggle(
                            "专注结束时显示全屏提示",
                            isOn: $settings.fullScreenCompletionEnabled
                        )

                        Text("在当前使用的显示器最上层显示，不会切换应用或抢占键盘焦点。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if settings.fullScreenCompletionEnabled {
                            Divider()

                            HStack(spacing: 12) {
                                Text("背景不透明度")
                                Slider(
                                    value: $settings.fullScreenCompletionOpacity,
                                    in: 0.2...1,
                                    step: 0.05
                                )
                                Text("\(Int((settings.fullScreenCompletionOpacity * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 42, alignment: .trailing)
                            }

                            Stepper(value: $settings.fullScreenCompletionDuration, in: 1...15) {
                                LabeledContent(
                                    "显示持续时间",
                                    value: "\(settings.fullScreenCompletionDuration) 秒"
                                )
                            }

                            Button("预览全屏提示") {
                                FocusCompletionPresenter.shared.present()
                            }
                            .buttonStyle(InteractiveButtonStyle(kind: .secondary))
                        }
                    }
                }

                if settings.soundEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("阶段提示音")
                            .font(.title3.weight(.semibold))
                        Text("每个阶段可以分别使用默认提示音或自定义音乐。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 16) {
                        ForEach(TimerSoundCue.allCases) { cue in
                            soundSection(for: cue)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var authorizationText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "已允许"
        case .denied:
            "未允许"
        case .notDetermined:
            "尚未询问"
        @unknown default:
            "未知"
        }
    }

    @ViewBuilder
    private func soundSection(for cue: TimerSoundCue) -> some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: soundSymbol(for: cue))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(cue.title)
                            .font(.headline)
                        Text(cue.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    Text("声音来源")
                    Spacer()
                    Picker("声音来源", selection: soundModeBinding(for: cue)) {
                        ForEach(CompletionSoundMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                if soundConfiguration(for: cue).mode == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("音乐文件")
                            Spacer(minLength: 16)
                            Text(settings.customSoundFileName(for: cue) ?? "尚未选择")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 190, alignment: .trailing)
                                .foregroundStyle(settings.customSoundFileName(for: cue) == nil ? .secondary : .primary)

                            Button("选择…") {
                                chooseCustomSoundFile(for: cue)
                            }

                            if settings.customSoundFileName(for: cue) != nil {
                                Button("移除") {
                                    notifications.stopCompletionSound()
                                    settings.clearCustomSoundFile(for: cue)
                                }
                            }
                        }

                        Text("自定义音乐将按照文件的实际长度完整播放。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("试听") {
                        notifications.playTimerSound(
                            cue,
                            configuration: soundConfiguration(for: cue)
                        )
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .secondary))

                    Button("停止") {
                        notifications.stopCompletionSound()
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .quiet))
                }
            }
        }
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
    }

    private func soundSymbol(for cue: TimerSoundCue) -> String {
        switch cue {
        case .focusCompleted: "timer"
        case .breakCompleted: "cup.and.saucer.fill"
        case .planCompleted: "flag.checkered"
        }
    }

    private func chooseCustomSoundFile(for cue: TimerSoundCue) {
        let panel = NSOpenPanel()
        panel.title = "选择\(cue.title)提示音"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        notifications.stopCompletionSound()
        do {
            try settings.setCustomSoundFile(url, for: cue)
        } catch {
            soundImportError = error.localizedDescription
        }
    }

    private var soundImportErrorBinding: Binding<Bool> {
        Binding(
            get: { soundImportError != nil },
            set: { isPresented in
                if !isPresented {
                    soundImportError = nil
                }
            }
        )
    }

    private func soundConfiguration(for cue: TimerSoundCue) -> TimerSoundConfiguration {
        settings.soundConfiguration(for: cue)
    }

    private func soundModeBinding(for cue: TimerSoundCue) -> Binding<CompletionSoundMode> {
        Binding(
            get: { soundConfiguration(for: cue).mode },
            set: { mode in
                var configuration = soundConfiguration(for: cue)
                configuration.mode = mode
                settings.updateSoundConfiguration(configuration, for: cue)
            }
        )
    }

    private var dataView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("累计数据")
                        .font(.title3.weight(.semibold))
                    Text("所有记录都保存在这台 Mac 上。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("清空记录…", role: .destructive) {
                    clearSessionsAfterConfirmation()
                }
                .buttonStyle(InteractiveButtonStyle(kind: .destructive))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                dataStatCard(value: "\(sessions.totalFocusCount)", label: "累计完成番茄")
                dataStatCard(value: durationText(sessions.totalFocusSeconds), label: "累计专注时间")
                dataStatCard(value: "\(sessions.todayFocusCount)", label: "今日完成番茄")
                dataStatCard(value: durationText(sessions.todayFocusSeconds), label: "今日专注时间")
            }

            HStack {
                Text("全部记录")
                    .font(.headline)
                Spacer()
                Text("\(sessions.sessions.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                if sessions.sessionsNewestFirst.isEmpty {
                    ContentUnavailableView("暂无计时记录", systemImage: "tray")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sessions.sessionsNewestFirst) { session in
                                dataSessionRow(session)
                                if session.id != sessions.sessionsNewestFirst.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
    }

    private func dataStatCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func dataSessionRow(_ session: FocusSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sessionSymbol(session))
                .foregroundStyle(sessionColor(session))

            VStack(alignment: .leading, spacing: 3) {
                Text(sessionTitle(session))
                Text(session.endedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(durationText(session.actualDuration))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func sessionTitle(_ session: FocusSession) -> String {
        if session.phase.isFocus {
            return session.completed ? "专注完成" : "专注未完成"
        }
        return session.completed ? "休息完成" : "休息未完成"
    }

    private func sessionSymbol(_ session: FocusSession) -> String {
        session.completed ? (session.phase.isFocus ? "checkmark.circle.fill" : "cup.and.saucer.fill") : "xmark.circle"
    }

    private func sessionColor(_ session: FocusSession) -> Color {
        guard session.completed else { return .secondary }
        return session.phase.isFocus ? .green : .blue
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)时\(totalMinutes % 60)分"
        }
        return "\(totalMinutes)分钟"
    }

    private func clearSessionsAfterConfirmation() {
        if ConfirmationService.confirm(
            title: "清空所有记录？",
            message: "此操作不可恢复。",
            confirmTitle: "清空记录",
            isDestructive: true
        ) {
            sessions.clear()
        }
    }
}
