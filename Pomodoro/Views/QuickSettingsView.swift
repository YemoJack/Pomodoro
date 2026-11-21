import SwiftUI

struct TimerPresetPicker: View {
    let isTiming: Bool

    @EnvironmentObject private var settings: SettingsStore
    @State private var showsPresets = false
    @State private var showsPresetManager = false

    private var presetName: String { settings.activePreset?.name ?? "自定义" }

    var body: some View {
        Button {
            showsPresets.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text(presetName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: 228)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(InteractiveButtonStyle(kind: .secondary))
        .accessibilityLabel("计时预设")
        .accessibilityValue(presetName)
        .popover(isPresented: $showsPresets, arrowEdge: .bottom) {
            TimerPresetPopover(isTiming: isTiming) {
                showsPresets = false
                showsPresetManager = true
            } onSelect: { id in
                settings.selectPreset(id: id)
                showsPresets = false
            }
        }
        .sheet(isPresented: $showsPresetManager) {
            PresetManagerView()
        }
    }
}

private struct TimerPresetPopover: View {
    let isTiming: Bool
    let onManage: () -> Void
    let onSelect: (String) -> Void

    @EnvironmentObject private var settings: SettingsStore
    @State private var showsTimingParameters = false

    var body: some View {
        Group {
            if showsTimingParameters {
                timingParameters
            } else {
                presetList
            }
        }
        .padding(12)
        .frame(width: 348)
        .background(.background)
    }

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(settings.presets) { preset in
                            presetRow(preset)
                                .id(preset.id)
                        }
                    }
                }
                .frame(height: 32 * CGFloat(min(settings.presets.count, 6)))
                .onAppear {
                    if let selectedPresetID = settings.selectedPresetID {
                        proxy.scrollTo(selectedPresetID)
                    }
                }
            }

            Divider()

            HStack {
                Button("自定义…") {
                    showsTimingParameters = true
                }
                Spacer()
                Button("管理预设…", action: onManage)
            }
            .buttonStyle(InteractiveButtonStyle(kind: .quiet))

            if isTiming {
                nextPhaseHint
            }
        }
    }

    private func presetRow(_ preset: TimerPreset) -> some View {
        let isSelected = preset.id == settings.selectedPresetID
        return Button {
            onSelect(preset.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(preset.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(preset.summary)
                    .font(.caption.monospacedDigit())
                    .fixedSize()
            }
            .font(.subheadline)
            .frame(height: 22)
        }
        .buttonStyle(InteractiveButtonStyle(kind: .quiet))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(preset.name)
    }

    private var timingParameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showsTimingParameters = false
            } label: {
                Label("计时预设", systemImage: "chevron.left")
            }
            .buttonStyle(InteractiveButtonStyle(kind: .quiet))
            .accessibilityLabel("返回计时预设")

            Divider()

            TimingParametersView()

            if isTiming {
                nextPhaseHint
            }
        }
        .padding(4)
    }

    private var nextPhaseHint: some View {
        Text("时长从下一阶段生效")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
    }
}

private struct TimingParametersView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $settings.focusMinutes, in: 1...TimerDurationLimits.customFocusMinutes) {
                LabeledContent("专注时间", value: "\(settings.focusMinutes) 分钟")
            }

            Stepper(value: $settings.breakMinutes, in: 1...60) {
                LabeledContent("休息时间", value: "\(settings.breakMinutes) 分钟")
            }

            Stepper(value: $settings.totalRounds, in: 1...12) {
                LabeledContent("专注轮数", value: "\(settings.totalRounds) 轮")
            }

            Divider()

            Toggle("专注结束后自动休息", isOn: $settings.autoStartBreaks)
            Toggle("休息结束后自动专注", isOn: $settings.autoStartFocus)

        }
    }
}

struct PresetManagerView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPresetID: String?
    @State private var draft = PresetDraft(preset: .defaultPreset)
    @State private var isCreating = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("管理计时预设")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(InteractiveButtonStyle(kind: .secondary))
            }
            .padding(18)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    List(settings.presets, selection: $selectedPresetID) { preset in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(preset.name)
                                if preset.isDefault {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(preset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(preset.id)
                    }

                    Button {
                        beginCreatingPreset()
                    } label: {
                        Label("新建预设", systemImage: "plus")
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .secondary))
                    .padding(.bottom, 12)
                }
                .frame(width: 210)

                Divider()

                presetEditor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 620, height: 440)
        .onAppear {
            let initialID = settings.selectedPresetID ?? TimerPreset.defaultID
            selectedPresetID = initialID
            if let preset = settings.presets.first(where: { $0.id == initialID }) {
                draft = PresetDraft(preset: preset)
            }
        }
        .onChange(of: selectedPresetID) { _, newValue in
            guard let newValue,
                  let preset = settings.presets.first(where: { $0.id == newValue })
            else { return }
            draft = PresetDraft(preset: preset)
            isCreating = false
        }
        .confirmationDialog(
            "删除“\(draft.name)”？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除预设", role: .destructive) {
                deleteSelectedPreset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，当前计时参数会保留为自定义配置。")
        }
    }

    private var presetEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isCreating ? "新建预设" : "预设详情")
                    .font(.headline)
                Spacer()
                if draft.isDefault {
                    Label("默认预设不可修改", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("名称", text: $draft.name)

                Stepper(value: $draft.focusMinutes, in: 1...TimerDurationLimits.customFocusMinutes) {
                    LabeledContent("专注时间", value: "\(draft.focusMinutes) 分钟")
                }

                Stepper(value: $draft.breakMinutes, in: 1...60) {
                    LabeledContent("休息时间", value: "\(draft.breakMinutes) 分钟")
                }

                Stepper(value: $draft.rounds, in: 1...12) {
                    LabeledContent("专注轮数", value: "\(draft.rounds) 轮")
                }

                Toggle("专注结束后自动休息", isOn: $draft.autoStartBreaks)
                Toggle("休息结束后自动专注", isOn: $draft.autoStartFocus)
            }
            .disabled(draft.isDefault)

            HStack {
                if !isCreating && !draft.isDefault {
                    Button("删除", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }

                Spacer()

                if !draft.isDefault {
                    Button(isCreating ? "创建预设" : "保存修改") {
                        saveDraft()
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .prominent))
                    .disabled(draft.trimmedName.isEmpty)
                }
            }
        }
        .padding(20)
    }

    private func beginCreatingPreset() {
        selectedPresetID = nil
        draft = PresetDraft(
            id: nil,
            name: "新预设",
            focusMinutes: settings.focusMinutes,
            breakMinutes: settings.breakMinutes,
            rounds: settings.totalRounds,
            autoStartBreaks: settings.autoStartBreaks,
            autoStartFocus: settings.autoStartFocus,
            isDefault: false
        )
        isCreating = true
    }

    private func saveDraft() {
        if isCreating {
            let preset = settings.createPreset(
                name: draft.trimmedName,
                focusMinutes: draft.focusMinutes,
                breakMinutes: draft.breakMinutes,
                rounds: draft.rounds,
                autoStartBreaks: draft.autoStartBreaks,
                autoStartFocus: draft.autoStartFocus
            )
            selectedPresetID = preset.id
            draft = PresetDraft(preset: preset)
            isCreating = false
        } else if let id = draft.id {
            let preset = draft.makePreset(id: id)
            settings.updatePreset(preset)
            draft = PresetDraft(preset: preset)
        }
    }

    private func deleteSelectedPreset() {
        guard let id = draft.id else { return }
        settings.deletePreset(id: id)
        selectedPresetID = TimerPreset.defaultID
        draft = PresetDraft(preset: .defaultPreset)
        isCreating = false
    }
}

private struct PresetDraft {
    var id: String?
    var name: String
    var focusMinutes: Int
    var breakMinutes: Int
    var rounds: Int
    var autoStartBreaks: Bool
    var autoStartFocus: Bool
    var isDefault: Bool

    init(preset: TimerPreset) {
        id = preset.id
        name = preset.name
        focusMinutes = preset.focusMinutes
        breakMinutes = preset.breakMinutes
        rounds = preset.rounds
        autoStartBreaks = preset.autoStartBreaks
        autoStartFocus = preset.autoStartFocus
        isDefault = preset.isDefault
    }

    init(
        id: String?,
        name: String,
        focusMinutes: Int,
        breakMinutes: Int,
        rounds: Int,
        autoStartBreaks: Bool,
        autoStartFocus: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.rounds = rounds
        self.autoStartBreaks = autoStartBreaks
        self.autoStartFocus = autoStartFocus
        self.isDefault = isDefault
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makePreset(id: String) -> TimerPreset {
        TimerPreset(
            id: id,
            name: trimmedName,
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes,
            rounds: rounds,
            autoStartBreaks: autoStartBreaks,
            autoStartFocus: autoStartFocus
        )
    }
}
