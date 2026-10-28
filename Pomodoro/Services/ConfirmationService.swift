import AppKit

enum ConfirmationService {
    @MainActor
    static func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        isDestructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = isDestructive ? .warning : .informational
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: confirmTitle)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
