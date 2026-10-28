import AppKit
import SwiftUI

struct RootView: View {
    @AppStorage("mainWindowAlwaysOnTop") private var isWindowPinned = false
    @State private var selection = Page.timer
    @State private var showsQuickSettings = false

    private enum Page: Hashable {
        case timer
        case today
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Picker("页面", selection: $selection) {
                    Text("计时器").tag(Page.timer)
                    Text("今日").tag(Page.today)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                HStack {
                    Spacer()

                    Button {
                        isWindowPinned.toggle()
                    } label: {
                        Image(systemName: isWindowPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .icon))
                    .foregroundStyle(isWindowPinned ? Color.accentColor : Color.primary)
                    .help(isWindowPinned ? "取消窗口置顶" : "将窗口保持在最上层")
                    .accessibilityLabel(isWindowPinned ? "取消窗口置顶" : "窗口置顶")

                    Button {
                        showsQuickSettings.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(InteractiveButtonStyle(kind: .icon))
                    .help("计时设置")
                    .popover(isPresented: $showsQuickSettings, arrowEdge: .top) {
                        QuickSettingsView()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            switch selection {
            case .timer:
                TimerView()
            case .today:
                TodayView {
                    selection = .timer
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(WindowLevelController(isPinned: isWindowPinned))
    }
}

private struct WindowLevelController: NSViewRepresentable {
    let isPinned: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateWindowLevel(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindowLevel(for: nsView)
    }

    private func updateWindowLevel(for view: NSView) {
        let level: NSWindow.Level = isPinned ? .floating : .normal
        DispatchQueue.main.async {
            view.window?.level = level
        }
    }
}
