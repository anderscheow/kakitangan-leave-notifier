import AppKit
import SwiftUI


struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.leaveTeal.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }
}


struct LiquidGlassButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(isProminent ? .semibold : .regular))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(Color.leaveInk)
            .liquidGlassSurface(
                cornerRadius: 9,
                tint: isProminent ? .leaveTeal : nil,
                interactive: true,
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}


extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(isProminent: false)
    }

    static var liquidGlassProminent: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(isProminent: true)
    }
}


extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedTint = tint ?? Color.leaveTeal
        if #available(macOS 26.0, *) {
            self
                .background(Color.leaveGlassBase, in: shape)
                .overlay {
                    shape
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: tint == nil ? 1 : 1.2)
                }
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(Color.leaveGlassBase, in: shape)
                .overlay {
                    shape
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: tint == nil ? 1 : 1.2)
                }
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        let resolvedTint = tint ?? Color.leaveTeal
        if #available(macOS 26.0, *) {
            self
                .background(Color.leaveGlassBase, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: 1)
                }
                .glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            self
                .background(Color.leaveGlassBase, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: 1)
                }
        }
    }
}


extension Color {
    static let leaveCanvas = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.941, green: 0.992, blue: 0.980, alpha: 1),
        dark: NSColor(calibratedRed: 0.024, green: 0.086, blue: 0.075, alpha: 1),
    ))
    static let leaveSurface = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.94),
        dark: NSColor(calibratedRed: 0.071, green: 0.157, blue: 0.141, alpha: 1),
    ))
    static let leaveElevated = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.910, green: 0.973, blue: 0.949, alpha: 1),
        dark: NSColor(calibratedRed: 0.102, green: 0.220, blue: 0.196, alpha: 1),
    ))
    static let leaveGlassBase = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.965, green: 0.992, blue: 0.984, alpha: 0.74),
        dark: NSColor(calibratedRed: 0.066, green: 0.176, blue: 0.158, alpha: 0.78),
    ))
    static let leaveInk = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.078, green: 0.306, blue: 0.290, alpha: 1),
        dark: NSColor(calibratedRed: 0.894, green: 0.957, blue: 0.933, alpha: 1),
    ))
    static let leaveMuted = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.230, green: 0.392, blue: 0.372, alpha: 1),
        dark: NSColor(calibratedRed: 0.690, green: 0.805, blue: 0.772, alpha: 1),
    ))
    static let leaveTeal = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.030, green: 0.450, blue: 0.400, alpha: 1),
        dark: NSColor(calibratedRed: 0.176, green: 0.831, blue: 0.749, alpha: 1),
    ))
    static let leaveOrange = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.720, green: 0.270, blue: 0.020, alpha: 1),
        dark: NSColor(calibratedRed: 0.992, green: 0.729, blue: 0.455, alpha: 1),
    ))
}


extension NSColor {
    static func leaveAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua]) == .darkAqua ? dark : light
        }
    }
}
