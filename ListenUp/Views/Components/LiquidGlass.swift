import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liquid Glass Shape Kind

public enum LiquidGlassShapeKind {
    case capsule
    case circle
    case roundedRectangle(cornerRadius: CGFloat)
}

// MARK: - Liquid Glass View Modifier

/// Reusable view modifier providing a luminous, multi-layered Liquid Glass aesthetic.
/// Combines ultra-thin material, specular rim lighting, ambient fluid refraction, and soft depth shadows.
public struct LiquidGlassModifier: ViewModifier {
    public let shapeKind: LiquidGlassShapeKind
    public let tint: Color?
    public let isInteractive: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false
    
    public init(
        shapeKind: LiquidGlassShapeKind = .roundedRectangle(cornerRadius: 16),
        tint: Color? = nil,
        isInteractive: Bool = false
    ) {
        self.shapeKind = shapeKind
        self.tint = tint
        self.isInteractive = isInteractive
    }
    
    public func body(content: Content) -> some View {
        clippedContent(content)
            .background {
                glassBackdrop
            }
            .overlay {
                specularRimBorder
            }
            .overlay {
                innerSheenHighlight
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                radius: isPressed ? 6 : 14,
                x: 0,
                y: isPressed ? 2 : 6
            )
            .shadow(
                color: (tint ?? Color.accentColor).opacity(colorScheme == .dark ? 0.12 : 0.05),
                radius: 12,
                x: 0,
                y: 2
            )
            .scaleEffect(isInteractive && isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
    }
    
    @ViewBuilder
    private func clippedContent(_ content: Content) -> some View {
        switch shapeKind {
        case .capsule:
            content.clipShape(Capsule())
        case .circle:
            content.clipShape(Circle())
        case .roundedRectangle(let radius):
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
    
    // MARK: - Glass Backdrop & Fluid Radiance
    
    @ViewBuilder
    private var glassBackdrop: some View {
        switch shapeKind {
        case .capsule:
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    if let tint = tint {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                        tint.opacity(colorScheme == .dark ? 0.05 : 0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
        case .circle:
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    if let tint = tint {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                        tint.opacity(colorScheme == .dark ? 0.05 : 0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    if let tint = tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                        tint.opacity(colorScheme == .dark ? 0.05 : 0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
        }
    }
    
    // MARK: - Specular Rim Border
    
    @ViewBuilder
    private var specularRimBorder: some View {
        let strokeGradient = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.45 : 0.65), location: 0.0),
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25), location: 0.4),
                .init(color: Color.primary.opacity(0.04), location: 0.7),
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.20 : 0.35), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        switch shapeKind {
        case .capsule:
            Capsule()
                .strokeBorder(strokeGradient, lineWidth: 1)
        case .circle:
            Circle()
                .strokeBorder(strokeGradient, lineWidth: 1)
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(strokeGradient, lineWidth: 1)
        }
    }
    
    // MARK: - Inner Sheen Highlight
    
    @ViewBuilder
    private var innerSheenHighlight: some View {
        let sheen = LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
        
        switch shapeKind {
        case .capsule:
            Capsule()
                .fill(sheen)
                .allowsHitTesting(false)
        case .circle:
            Circle()
                .fill(sheen)
                .allowsHitTesting(false)
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(sheen)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies the Liquid Glass aesthetic with continuous rounded corners.
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                shapeKind: .roundedRectangle(cornerRadius: cornerRadius),
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }
    
    /// Applies the Liquid Glass aesthetic formatted as a Capsule.
    func liquidGlassCapsule(
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                shapeKind: .capsule,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }
    
    /// Applies the Liquid Glass aesthetic formatted as a Circle.
    func liquidGlassCircle(
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                shapeKind: .circle,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }
}

// MARK: - Liquid Glass Card Container

/// Grouped card container with frosted glass substrate and luminous specular border.
public struct LiquidGlassCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let tint: Color?
    @ViewBuilder public let content: () -> Content
    
    public init(
        cornerRadius: CGFloat = 18,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content
    }
    
    public var body: some View {
        content()
            .liquidGlass(cornerRadius: cornerRadius, tint: tint)
    }
}

// MARK: - Liquid Glass Pill Button

/// Tactile interactive pill button encased in liquid glass.
public struct LiquidGlassPillButton: View {
    public let title: String?
    public let systemImage: String?
    public let tint: Color?
    public let action: () -> Void
    
    public init(
        title: String? = nil,
        systemImage: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }
    
    public var body: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                if let title = title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(tint ?? Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassCapsule(tint: tint, isInteractive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid Glass Ambient Mesh Background

/// Ambient dynamic mesh gradient backdrop providing fluid refraction colors behind glass surfaces.
public struct LiquidGlassMeshBackground: View {
    public let primaryColor: Color
    public let secondaryColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        primaryColor: Color = Color.accentColor,
        secondaryColor: Color = Color.purple
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }
    
    public var body: some View {
        ZStack {
            #if canImport(UIKit)
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #else
            Color.black
                .ignoresSafeArea()
            #endif
            
            // Soft fluid ambient orbs
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                
                Circle()
                    .fill(primaryColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .frame(width: w * 0.85, height: w * 0.85)
                    .blur(radius: 65)
                    .offset(x: -w * 0.2, y: -h * 0.1)
                
                Circle()
                    .fill(secondaryColor.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    .frame(width: w * 0.75, height: w * 0.75)
                    .blur(radius: 75)
                    .offset(x: w * 0.35, y: h * 0.25)
                
                Circle()
                    .fill(primaryColor.opacity(colorScheme == .dark ? 0.14 : 0.07))
                    .frame(width: w * 0.6, height: w * 0.6)
                    .blur(radius: 55)
                    .offset(x: 0, y: h * 0.5)
            }
            .ignoresSafeArea()
        }
    }
}

#Preview("Liquid Glass Showcase") {
    ZStack {
        LiquidGlassMeshBackground(primaryColor: .blue, secondaryColor: .indigo)
        
        VStack(spacing: 20) {
            Text("Liquid Glass")
                .font(.title.bold())
            
            LiquidGlassCard(tint: .blue) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Luminous Card", systemImage: "sparkles")
                        .font(.headline)
                    Text("Ultra-thin material layered with specular rim lighting and subtle ambient glow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                LiquidGlassPillButton(title: "Capsule Pill", systemImage: "play.fill", tint: .blue) {}
                LiquidGlassPillButton(title: "Bookmark", systemImage: "bookmark.fill") {}
            }
        }
    }
}
