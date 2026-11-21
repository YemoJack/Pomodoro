import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FocusRestrictionPicker: View {
    @Binding var selection: FocusRestrictionMode

    var body: some View {
        Picker("专注限制", selection: $selection) {
            ForEach(FocusRestrictionMode.allCases, id: \.self) { mode in
                Label(mode.title, systemImage: mode.symbol)
                    .tag(mode)
            }
        }
    }
}

struct FocusLimitSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var timer: TimerStore
    @EnvironmentObject private var focusLimits: FocusLimitService
    @State private var website = ""
    @State private var websiteError: String?
    @State private var chromeRegistration: String?
    @State private var appError: String?

    var body: some View {
        Form {
            FocusRestrictionPicker(selection: $settings.focusRestrictionMode)
                .disabled(timer.isGlobalFocusLocked)
            if settings.focusRestrictionMode == .global {
                Text("下轮专注期间只显示计时器，提前结束需验证 Mac 登录密码。")
                    .foregroundStyle(.secondary)
            }

            if settings.focusRestrictionMode != .global {
                Section("App") {
                    modePicker($settings.focusLimitRules.apps.mode)
                    if settings.focusLimitRules.apps.mode != .off {
                        entries($settings.focusLimitRules.apps, title: appTitle)
                        Button("添加 App…", action: chooseApp)
                        if let appError { Text(appError).foregroundStyle(.red) }
                    }
                }

                Section("网站") {
                    modePicker($settings.focusLimitRules.websites.mode)
                    if settings.focusLimitRules.websites.mode != .off {
                        entries($settings.focusLimitRules.websites) { $0 }
                        HStack {
                            TextField("域名或网址", text: $website)
                                .labelsHidden()
                                .onSubmit(addWebsite)
                            Button("添加", action: addWebsite)
                                .disabled(website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let websiteError { Text(websiteError).foregroundStyle(.red) }
                    }
                }

                Section("Chrome") {
                    LabeledContent("网站限制", value: focusLimits.chromeStatus)
                    Button("注册本机连接") {
                        do {
                            try ChromeNativeMessaging.register()
                            chromeRegistration = "已注册。请在 Chrome 启用 Pomodoro 扩展。"
                        } catch {
                            chromeRegistration = error.localizedDescription
                        }
                    }
                    if let chromeRegistration {
                        Text(chromeRegistration).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func modePicker(_ selection: Binding<FocusLimitMode>) -> some View {
        Picker("模式", selection: selection) {
            ForEach(FocusLimitMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }

    @ViewBuilder
    private func entries(_ list: Binding<FocusLimitList>, title: @escaping (String) -> String) -> some View {
        ForEach(list.wrappedValue.entries, id: \.self) { entry in
            LabeledContent {
                Button(role: .destructive) {
                    list.wrappedValue.entries.removeAll { $0 == entry }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("移除 \(title(entry))")
            } label: {
                Text(title(entry))
            }
        }

        if list.wrappedValue.mode == .allow && list.wrappedValue.entries.isEmpty {
            Text("添加至少一项以启用白名单。")
                .foregroundStyle(.secondary)
        }
    }

    private func appTitle(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "选择 App"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier, !FocusLimitService.isExemptApp(id) else {
            appError = "请选择可限制的 App。"
            return
        }

        if !settings.focusLimitRules.apps.entries.contains(id) {
            settings.focusLimitRules.apps.entries.append(id)
        }
        appError = nil
    }

    private func addWebsite() {
        guard let domain = FocusLimitService.domain(from: website) else {
            websiteError = "请输入有效的域名或网址。"
            return
        }

        if !settings.focusLimitRules.websites.entries.contains(domain) {
            settings.focusLimitRules.websites.entries.append(domain)
        }
        websiteError = nil
        website = ""
    }
}
