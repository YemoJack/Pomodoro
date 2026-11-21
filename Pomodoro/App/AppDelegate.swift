import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuTrackingDepth = 0
    private var focusCompletionCancellable: AnyCancellable?
    private let focusCompletionPresenter = FocusCompletionPresenter.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusLimitService.shared.start(timer: .shared, settings: .shared)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )

        focusCompletionCancellable = TimerStore.shared.$focusCompletionEventID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.focusCompletionPresenter.present()
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusLimitService.shared.stop()
        focusCompletionPresenter.dismiss()
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !TimerStore.shared.isGlobalFocusLocked else { return .terminateCancel }
        guard TimerStore.shared.isActive else { return .terminateNow }

        let shouldQuit = ConfirmationService.confirm(
            title: "退出番茄专注？",
            message: "退出后当前计时将停止。关闭主窗口不会停止计时。",
            confirmTitle: "退出",
            isDestructive: true
        )
        return shouldQuit ? .terminateNow : .terminateCancel
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        menuTrackingDepth += 1
        if menuTrackingDepth == 1 {
            TimerStore.shared.setMenuTracking(true)
        }
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        menuTrackingDepth = max(menuTrackingDepth - 1, 0)
        if menuTrackingDepth == 0 {
            TimerStore.shared.setMenuTracking(false)
        }
    }
}

@MainActor
final class FocusCompletionPresenter {
    static let shared = FocusCompletionPresenter()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func present() {
        dismiss()

        let settings = SettingsStore.shared
        guard settings.fullScreenCompletionEnabled else { return }
        guard let screen = screenContainingPointer else { return }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(
            rootView: ScreenFocusCompletionView(
                backgroundOpacity: settings.fullScreenCompletionOpacity,
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )

        self.panel = panel
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TimeInterval(settings.fullScreenCompletionDuration),
            execute: workItem
        )
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private var screenContainingPointer: NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(pointerLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private struct ScreenFocusCompletionView: View {
    let backgroundOpacity: Double
    let onDismiss: () -> Void

    @State private var isPresented = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(isPresented ? backgroundOpacity * 0.4 : 0)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(backgroundOpacity * 0.64),
                        Color.black.opacity(min(backgroundOpacity * 1.34, 1))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 1.25)
                .offset(y: isPresented ? proxy.size.height * 0.06 : proxy.size.height)

                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)

                    Text("专注结束")
                        .font(.system(size: 52, weight: .bold, design: .rounded))

                    Text("做得很好，休息一下吧")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))

                    Text("轻点任意位置关闭")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 10)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .opacity(isPresented ? 1 : 0)
                .scaleEffect(isPresented ? 1 : 0.9)
                .offset(y: isPresented ? 0 : 64)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("专注结束。做得很好，休息一下吧。")
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
                isPresented = true
            }
        }
    }
}
