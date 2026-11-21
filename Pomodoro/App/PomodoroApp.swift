import SwiftUI

@main
enum PomodoroEntry {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == ChromeNativeMessaging.launchArgument {
            try? ChromeNativeMessaging.runHost(arguments: arguments)
        } else {
            PomodoroApp.main()
        }
    }
}

struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = SettingsStore.shared
    @StateObject private var sessions = SessionStore.shared
    @StateObject private var notifications = NotificationService.shared
    @StateObject private var timer = TimerStore.shared
    @StateObject private var focusLimits = FocusLimitService.shared

    var body: some Scene {
        Window("番茄专注", id: "main") {
            RootView()
                .environmentObject(settings)
                .environmentObject(sessions)
                .environmentObject(notifications)
                .environmentObject(timer)
        }
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(timer: timer)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(timer)
                .environmentObject(sessions)
                .environmentObject(settings)
                .environmentObject(notifications)
                .environmentObject(focusLimits)
        } label: {
            Label {
                if timer.status == .idle {
                    Text("番茄专注")
                } else {
                    Text(timer.formattedTime)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: timer.status == .paused ? "pause.circle.fill" : timer.phase.symbol)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(timer)
                .environmentObject(settings)
                .environmentObject(sessions)
                .environmentObject(notifications)
                .environmentObject(focusLimits)
        }
    }
}
