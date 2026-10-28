import SwiftUI

struct InteractiveButtonStyle: ButtonStyle {
    enum Kind: Equatable {
        case prominent
        case secondary
        case quiet
        case destructive
        case icon
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButton(
            configuration: configuration,
            kind: kind
        )
    }
}

private struct InteractiveButton: View {
    let configuration: ButtonStyle.Configuration
    let kind: InteractiveButtonStyle.Kind

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Keep the hover hit area stable. Scaling while hovering can make
            // the pointer repeatedly enter and leave buttons near their edges.
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .shadow(
                color: shadowColor,
                radius: configuration.isPressed ? 1 : (isHovered ? 6 : 2),
                y: configuration.isPressed ? 0 : (isHovered ? 3 : 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .animation(animation, value: configuration.isPressed)
            .animation(animation, value: isHovered)
            .onHover { hovering in
                isHovered = hovering && isEnabled
            }
    }

    private var foregroundColor: Color {
        switch kind {
        case .prominent:
            .white
        case .quiet:
            isHovered || configuration.isPressed ? .primary : .secondary
        case .destructive:
            .red
        case .secondary, .icon:
            .primary
        }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            switch kind {
            case .prominent:
                return .accentColor.opacity(0.72)
            case .destructive:
                return .red.opacity(0.20)
            case .secondary, .quiet, .icon:
                return .primary.opacity(0.14)
            }
        }

        if isHovered {
            switch kind {
            case .prominent:
                return .accentColor.opacity(0.88)
            case .destructive:
                return .red.opacity(0.12)
            case .secondary:
                return .primary.opacity(0.10)
            case .quiet, .icon:
                return .primary.opacity(0.08)
            }
        }

        switch kind {
        case .prominent:
            return .accentColor
        case .secondary:
            return .primary.opacity(0.06)
        case .destructive:
            return .red.opacity(0.05)
        case .quiet, .icon:
            return .clear
        }
    }

    private var borderColor: Color {
        switch kind {
        case .prominent:
            return .white.opacity(isHovered ? 0.24 : 0.14)
        case .secondary:
            return .primary.opacity(isHovered ? 0.18 : 0.10)
        case .destructive:
            return .red.opacity(isHovered ? 0.28 : 0.12)
        case .quiet, .icon:
            return .clear
        }
    }

    private var shadowColor: Color {
        guard kind == .prominent else { return .clear }
        return .accentColor.opacity(isHovered ? 0.28 : 0.14)
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .prominent:
            18
        case .secondary, .destructive:
            12
        case .quiet:
            9
        case .icon:
            8
        }
    }

    private var verticalPadding: CGFloat {
        switch kind {
        case .prominent:
            9
        case .secondary, .destructive:
            7
        case .quiet:
            5
        case .icon:
            8
        }
    }

    private var cornerRadius: CGFloat {
        kind == .icon ? 8 : 9
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}
