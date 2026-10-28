import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var timer: TimerStore

    var body: some Commands {
        CommandMenu("计时") {
            Button(timer.primaryActionTitle) {
                timer.performPrimaryAction()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("跳过当前阶段") {
                if ConfirmationService.confirm(
                    title: "跳过当前阶段？",
                    message: timer.phase.isFocus ? "本轮不会被记录为完成番茄。" : "将直接进入下一轮专注。",
                    confirmTitle: "跳过"
                ) {
                    timer.skipCurrentPhase()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!timer.isActive)
        }
    }
}
