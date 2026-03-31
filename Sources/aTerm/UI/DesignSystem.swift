import SwiftUI

// MARK: - Design System
/// Modern, clean design system for aTerm UI components

enum DesignSystem {
    
    // MARK: - Colors
    enum Colors {
        // Primary accent with adaptive opacity
        static let accent = Color.accentColor
        static let accentSecondary = Color.accentColor.opacity(0.7)
        
        // Background hierarchy
        static let backgroundPrimary = Color(nsColor: .windowBackgroundColor)
        static let backgroundSecondary = Color(nsColor: .controlBackgroundColor)
        static let backgroundTertiary = Color.white.opacity(0.03)
        
        // Text colors
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.7)
        
        // Semantic colors
        static let success = Color.green.opacity(0.8)
        static let warning = Color.orange.opacity(0.8)
        static let error = Color.red.opacity(0.8)
        static let info = Color.blue.opacity(0.8)
        
        // Terminal chrome
        static let terminalBackground = Color.black
        static let paneBorder = Color.white.opacity(0.06)
        static let paneBorderActive = Color.accentColor.opacity(0.4)
        
        // Card backgrounds
        static let cardBackground = Color.white.opacity(0.04)
        static let cardBackgroundHover = Color.white.opacity(0.06)
        static let cardBorder = Color.white.opacity(0.08)
    }
    
    // MARK: - Typography
    enum Typography {
        // Font sizes
        static let sizeXS: CGFloat = 10
        static let sizeS: CGFloat = 11
        static let sizeM: CGFloat = 12
        static let sizeL: CGFloat = 13
        static let sizeXL: CGFloat = 14
        static let size2XL: CGFloat = 16
        static let size3XL: CGFloat = 18
        
        // Font weights
        static let weightRegular = Font.Weight.regular
        static let weightMedium = Font.Weight.medium
        static let weightSemibold = Font.Weight.semibold
        static let weightBold = Font.Weight.bold
        
        // Common font combinations
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        
        static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        
        static func defaultFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    enum Shadows {
        static let subtle = ShadowStyle(
            color: .black.opacity(0.15),
            radius: 4,
            x: 0,
            y: 2
        )
        
        static let medium = ShadowStyle(
            color: .black.opacity(0.2),
            radius: 8,
            x: 0,
            y: 4
        )
        
        static let large = ShadowStyle(
            color: .black.opacity(0.25),
            radius: 16,
            x: 0,
            y: 8
        )
        
        static let glow = ShadowStyle(
            color: Colors.accent.opacity(0.3),
            radius: 12,
            x: 0,
            y: 0
        )
    }
    
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        
        var swiftUIShadow: some ViewModifier {
            ShadowModifier(style: self)
        }
    }
    
    struct ShadowModifier: ViewModifier {
        let style: ShadowStyle
        
        func body(content: Content) -> some View {
            content
                .shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
        }
    }
    
    // MARK: - Animation
    enum Animation {
        static let fast = SwiftUI.Animation.easeOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeOut(duration: 0.2)
        static let slow = SwiftUI.Animation.easeOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
    }
    
    // MARK: - Layout
    enum Layout {
        static let sidebarWidth: CGFloat = 300
        static let sidebarMaxWidth: CGFloat = 360
        static let minPaneWidth: CGFloat = 200
        static let minPaneHeight: CGFloat = 120
        static let tabHeight: CGFloat = 36
        static let inputBarHeight: CGFloat = 44
        static let headerHeight: CGFloat = 32
    }
}

// MARK: - View Modifiers

/// Card style for panels and containers
struct CardModifier: ViewModifier {
    let isHoverable: Bool
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                    .fill(DesignSystem.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.cardBorder, lineWidth: 0.5)
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                    .fill(isHovered ? DesignSystem.Colors.cardBackgroundHover : Color.clear)
            )
            .onHover { hovering in
                if isHoverable {
                    withAnimation(DesignSystem.Animation.fast) {
                        isHovered = hovering
                    }
                }
            }
    }
}

/// Modern button style
struct ModernButtonStyle: ButtonStyle {
    let variant: ButtonVariant
    let size: ButtonSize
    
    enum ButtonVariant {
        case primary
        case secondary
        case ghost
        case danger
    }
    
    enum ButtonSize {
        case xs
        case s
        case m
        case l
        
        var padding: EdgeInsets {
            switch self {
            case .xs: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .s: return EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            case .m: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            case .l: return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            }
        }
        
        var font: Font {
            switch self {
            case .xs: return DesignSystem.Typography.defaultFont(10, weight: .medium)
            case .s: return DesignSystem.Typography.defaultFont(11, weight: .medium)
            case .m: return DesignSystem.Typography.defaultFont(12, weight: .medium)
            case .l: return DesignSystem.Typography.defaultFont(13, weight: .medium)
            }
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .padding(size.padding)
            .background(background(for: variant, isPressed: configuration.isPressed))
            .foregroundColor(foreground(for: variant))
            .cornerRadius(DesignSystem.Radius.s)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
    
    private func background(for variant: ButtonVariant, isPressed: Bool) -> some View {
        Group {
            switch variant {
            case .primary:
                Color.accentColor.opacity(isPressed ? 0.8 : 1)
            case .secondary:
                DesignSystem.Colors.backgroundSecondary.opacity(isPressed ? 0.8 : 1)
            case .ghost:
                Color.clear
            case .danger:
                Color.red.opacity(isPressed ? 0.8 : 0.7)
            }
        }
    }
    
    private func foreground(for variant: ButtonVariant) -> Color {
        switch variant {
        case .primary, .danger:
            return .white
        case .secondary, .ghost:
            return .primary
        }
    }
}

/// Modern text field style
struct ModernTextFieldStyle: TextFieldStyle {
    @Environment(\.controlSize) private var controlSize
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DesignSystem.Typography.defaultFont(13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.s)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.s)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
}

/// Badge style for status indicators
struct BadgeModifier: ViewModifier {
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.defaultFont(10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(DesignSystem.Radius.s)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply card styling
    func cardStyle(hoverable: Bool = false) -> some View {
        modifier(CardModifier(isHoverable: hoverable))
    }
    
    /// Apply badge styling
    func badgeStyle(color: Color) -> some View {
        modifier(BadgeModifier(color: color))
    }
    
    /// Apply modern shadow
    func modernShadow(_ style: DesignSystem.ShadowStyle = DesignSystem.Shadows.subtle) -> some View {
        modifier(DesignSystem.ShadowModifier(style: style))
    }
    
    /// Compact padding for dense layouts
    func compactPadding() -> some View {
        padding(DesignSystem.Spacing.s)
    }
    
    /// Standard padding for most components
    func standardPadding() -> some View {
        padding(DesignSystem.Spacing.m)
    }
    
    /// Relaxed padding for cards and sections
    func relaxedPadding() -> some View {
        padding(DesignSystem.Spacing.l)
    }
}

// MARK: - Utility Components

/// A divider with configurable opacity
struct SubtleDivider: View {
    let opacity: Double
    
    init(opacity: Double = 0.08) {
        self.opacity = opacity
    }
    
    var body: some View {
        Divider()
            .opacity(opacity)
    }
}

/// An icon button with consistent styling
struct IconButton: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false
    var size: CGFloat = 16
    var tooltip: String?
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.75, weight: .medium))
                .frame(width: size + 4, height: size + 4)
        }
        .buttonStyle(IconButtonStyle(isActive: isActive))
        .help(tooltip ?? "")
    }
}

struct IconButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? .accentColor : .secondary)
            .background(
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.white.opacity(0.05) : Color.clear)
            )
            .contentShape(Circle())
            .animation(DesignSystem.Animation.fast, value: isActive)
    }
}

/// A tag/label component
struct Tag: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(DesignSystem.Typography.defaultFont(10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

/// Loading indicator with modern styling
struct ModernProgressView: View {
    let size: ControlSize
    
    var body: some View {
        ProgressView()
            .controlSize(size)
            .scaleEffect(size == .small ? 0.8 : 1.0)
    }
}

/// Section header for sidebar/organizing content
struct SectionHeader: View {
    let title: String
    let icon: String?
    var action: (() -> Void)?
    var actionIcon: String?
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.defaultFont(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Text(title)
                .font(DesignSystem.Typography.defaultFont(11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Spacer()
            
            if let action = action, let actionIcon = actionIcon {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(DesignSystem.Typography.defaultFont(11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.s)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

/// Empty state view
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text(title)
                .font(DesignSystem.Typography.defaultFont(14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(DesignSystem.Typography.defaultFont(12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
