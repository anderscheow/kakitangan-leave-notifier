import AppKit
import SwiftUI


// Liquid Glass belongs to the control layer only. Apple's HIG: "Don't use Liquid Glass in the
// content layer." Cards, rows, badges, and callouts therefore use opaque, bordered surfaces so text
// stays legible and hierarchy reads clearly; buttons and pickers pick up glass from the system.


private enum LeaveMetrics {
    static let cardRadius: CGFloat = 16
    static let rowRadius: CGFloat = 10
}


// MARK: - Window backdrop


/// Neutral canvas with faint brand glows, giving glass controls some color to refract without
/// washing out the content cards on top.
struct LeaveBackdrop: View {
    var body: some View {
        ZStack {
            Color.leaveCanvas

            RadialGradient(
                colors: [Color.leaveAccent.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 620,
            )

            RadialGradient(
                colors: [Color.leaveOrange.opacity(0.06), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520,
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}


// MARK: - Content layer


/// Primary content container: an opaque card that separates clearly from the window backdrop.
struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LeaveMetrics.cardRadius, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.leaveSurface, in: shape)
            .overlay {
                shape.strokeBorder(Color.leaveBorder, lineWidth: 1)
            }
            .shadow(color: Color.leaveShadow, radius: 12, y: 4)
    }
}


/// Makes a whole `SurfaceCard` a link to more detail. Feedback is color and opacity only
/// (no scaling, which would shift the grid), and cards should show a chevron as the visible cue.
struct LeaveCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: LeaveMetrics.cardRadius, style: .continuous)
        configuration.label
            .leaveHoverHighlight(cornerRadius: LeaveMetrics.cardRadius)
            .overlay {
                shape
                    .fill(Color.leaveInk.opacity(configuration.isPressed ? 0.06 : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .leaveAnimation(LeaveMotion.quick, value: configuration.isPressed)
    }
}


extension ButtonStyle where Self == LeaveCardButtonStyle {
    static var leaveCard: LeaveCardButtonStyle {
        LeaveCardButtonStyle()
    }
}


/// Trailing "opens more" cue for clickable cards.
struct CardChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.leaveMuted)
            .accessibilityHidden(true)
    }
}


/// Rounded symbol on a soft tint of its status color. Replaces the old glass icon tiles.
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous),
            )
            .accessibilityHidden(true)
    }
}


extension View {
    /// List row inside a card. An `accent` draws a leading status bar so rows differ at a glance.
    func leaveRow(accent: Color? = nil) -> some View {
        modifier(LeaveRowModifier(accent: accent, isSelected: false))
    }

    /// Row that can be toggled on and off, such as a person in the monitoring picker.
    func leaveSelectableRow(isSelected: Bool) -> some View {
        modifier(LeaveRowModifier(accent: nil, isSelected: isSelected))
    }

    /// Small capsule for statuses and counts, colored by meaning.
    func statusChip(_ color: Color) -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1)
            }
    }

    /// Tinted, full-width box for banners and explanatory notes.
    func callout(_ color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: LeaveMetrics.rowRadius, style: .continuous)
        return padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: shape)
            .overlay {
                shape.strokeBorder(color.opacity(0.28), lineWidth: 1)
            }
    }
}


// MARK: - Inputs


extension View {
    /// Shared well for text fields, secure fields, date fields, and text editors. Replaces the
    /// AppKit bezels, whose near-black dark-mode fill clashed with the card and row surfaces.
    func leaveInputField() -> some View {
        modifier(LeaveInputFieldModifier())
    }

    /// Lets a `TextEditor` show the input well instead of its own opaque background (macOS 13+).
    @ViewBuilder
    func hidingScrollContentBackground() -> some View {
        if #available(macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}


private struct LeaveInputFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.leaveInputFill, in: shape)
            .overlay {
                // The plain style drops the system focus ring, so draw one in the accent color.
                shape.strokeBorder(
                    isFocused ? Color.leaveAccent : Color.leaveBorder,
                    lineWidth: isFocused ? 2 : 1,
                )
            }
    }
}


/// Borderless `NSDatePicker` text field. SwiftUI's `DatePicker` always draws an AppKit bezel on
/// macOS, so this lets date and time entry sit inside `leaveInputField()` like every other input.
struct LeaveDateField: NSViewRepresentable {
    @Binding var selection: Date
    var elements: NSDatePicker.ElementFlags = .hourMinute
    let accessibilityLabel: String

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.setContentHuggingPriority(.required, for: .horizontal)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection
        picker.datePickerElements = elements
        if picker.dateValue != selection {
            picker.dateValue = selection
        }
        picker.setAccessibilityLabel(accessibilityLabel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}


private struct LeaveRowModifier: ViewModifier {
    let accent: Color?
    let isSelected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LeaveMetrics.rowRadius, style: .continuous)
        content
            .padding(.leading, accent == nil ? 0 : 3)
            .background(isSelected ? Color.leaveAccent.opacity(0.10) : Color.leaveRowFill)
            .overlay(alignment: .leading) {
                if let accent {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 3)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Color.leaveAccent.opacity(0.55) : Color.leaveBorder,
                    lineWidth: isSelected ? 1.5 : 1,
                )
            }
    }
}


// MARK: - Control layer (Liquid Glass)


/// Glass button on macOS 26+, falling back to the standard bordered styles on older systems.
/// Implemented as a `PrimitiveButtonStyle` so it can wrap the system glass styles directly.
///
/// Color rules (HIG: keep labels on glass monochrome, reserve color for emphasis):
/// - `.standard`: neutral ink label on clear glass, for secondary actions.
/// - `.tinted`: colored label for an action with its own meaning, such as Join or an RSVP answer.
/// - `.selected`: colored label on lightly tinted glass, for the chosen option in a set.
/// - `.prominent`: filled accent, for the one primary action in an area.
/// - `role: .destructive` always renders a red label, whatever the tone.
struct LiquidGlassButtonStyle: PrimitiveButtonStyle {
    enum Tone {
        case standard
        case tinted(Color)
        case selected(Color)
        case prominent
    }

    let tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        LeaveGlassButton(configuration: configuration, tone: tone)
    }
}


extension PrimitiveButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tone: .standard)
    }

    static var liquidGlassProminent: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tone: .prominent)
    }

    static func liquidGlassTinted(_ color: Color) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tone: .tinted(color))
    }

    static func liquidGlassSelected(_ color: Color) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tone: .selected(color))
    }
}


/// A view rather than inline style code so it can read `isEnabled`: explicit label colors would
/// otherwise stay at full strength on disabled buttons.
private struct LeaveGlassButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let tone: LiquidGlassButtonStyle.Tone

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if case .prominent = tone {
            prominent
        } else {
            secondary
        }
    }

    @ViewBuilder
    private var prominent: some View {
        if #available(macOS 26.0, *) {
            Button(configuration)
                .buttonStyle(.glassProminent)
                .tint(.leaveAccentFill)
        } else {
            Button(configuration)
                .buttonStyle(.borderedProminent)
                .tint(.leaveAccentFill)
        }
    }

    @ViewBuilder
    private var secondary: some View {
        if #available(macOS 26.0, *) {
            // On macOS the glass style takes its color from the tint, so clear it; otherwise the
            // app-wide accent would turn every secondary button into colored glass.
            Button(configuration)
                .buttonStyle(.glass)
                .tint(glassTint)
                .foregroundStyle(labelColor)
        } else {
            Button(configuration)
                .buttonStyle(.bordered)
                .foregroundStyle(labelColor)
        }
    }

    /// Only a selected option colors its glass, and only faintly, so the label stays readable.
    private var glassTint: Color {
        if case let .selected(color) = tone, isEnabled {
            return color.opacity(0.22)
        }
        return .clear
    }

    private var labelColor: Color {
        let color: Color
        if configuration.role == .destructive {
            color = .leaveRed
        } else {
            switch tone {
            case let .tinted(tint), let .selected(tint):
                color = tint
            case .standard, .prominent:
                color = .leaveInk
            }
        }
        return isEnabled ? color : color.opacity(0.4)
    }
}


/// Groups neighbouring glass controls so they render as one glass layer on macOS 26+.
struct GlassControlGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            // Below the stack spacing, so neighbouring buttons share a glass layer without merging at rest.
            GlassEffectContainer(spacing: spacing / 2) {
                HStack(spacing: spacing) {
                    content
                }
            }
        } else {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}


// MARK: - Motion


/// Motion tokens from the UI/UX guidance: 150–300 ms for interface motion (never over 500 ms),
/// ease-out to enter and ease-in to exit, never linear, and motion on only one or two key
/// elements per view. Reduce Motion swaps slides for short fades.
enum LeaveMotion {
    /// Hover, selection, and other small state changes.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Rows, banners, and values appearing or changing.
    static let standard = Animation.easeOut(duration: 0.25)
    /// Screen and tab changes.
    static let screen = Animation.spring(response: 0.3, dampingFraction: 0.88)
    /// Used in place of the above when Reduce Motion is on.
    static let reduced = Animation.easeOut(duration: 0.12)
}


extension View {
    /// `animation(_:value:)` that shortens to a quick fade when Reduce Motion is on.
    func leaveAnimation<V: Equatable>(_ animation: Animation = LeaveMotion.standard, value: V) -> some View {
        modifier(LeaveAnimationModifier(animation: animation, value: value))
    }

    /// Fades in with a small slide from `edge` and fades out quickly. Fade only under Reduce Motion.
    func leaveTransition(edge: Edge = .top) -> some View {
        modifier(LeaveTransitionModifier(edge: edge))
    }

    /// Faint highlight while the pointer is over a clickable row.
    func leaveHoverHighlight(cornerRadius: CGFloat = 10) -> some View {
        modifier(LeaveHoverModifier(cornerRadius: cornerRadius))
    }

    /// Changing numbers roll to their new value instead of jumping (macOS 13+).
    @ViewBuilder
    func leaveNumericTransition() -> some View {
        if #available(macOS 13.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    /// A single bounce of the symbol when `value` changes, to confirm a choice (macOS 14+).
    func leaveSymbolBounce<V: Equatable>(value: V) -> some View {
        modifier(LeaveSymbolBounceModifier(value: value))
    }
}


private struct LeaveAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? LeaveMotion.reduced : animation, value: value)
    }
}


private struct LeaveTransitionModifier: ViewModifier {
    let edge: Edge

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : slide)
    }

    /// A short offset rather than `.move(edge:)`, which would travel the view's full height.
    private var slide: AnyTransition {
        let offset: CGFloat = edge == .top ? -6 : 6
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offset)),
            removal: .opacity.animation(.easeIn(duration: 0.15)),
        )
    }
}


private struct LeaveHoverModifier: ViewModifier {
    let cornerRadius: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.leaveInk.opacity(isHovering ? 0.05 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                withAnimation(LeaveMotion.quick) {
                    isHovering = hovering
                }
            }
    }
}


private struct LeaveSymbolBounceModifier<V: Equatable>: ViewModifier {
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *), !reduceMotion {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}


// MARK: - Hints


extension Text {
    /// Placeholder ("hint") text in the muted secondary color, so it never picks up the system accent.
    static func leavePrompt(_ text: String) -> Text {
        Text(text).foregroundColor(.leaveMuted)
    }
}


// MARK: - Palette


// Text and accent colors meet WCAG AA (4.5:1) against both `leaveSurface` and `leaveRowFill`.
extension Color {
    /// Window background. A neutral mid-light grey rather than the old bright mint, so white cards stand out.
    static let leaveCanvas = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.910, green: 0.925, blue: 0.929, alpha: 1),
        dark: NSColor(calibratedRed: 0.067, green: 0.078, blue: 0.082, alpha: 1),
    ))
    /// Card background.
    static let leaveSurface = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(calibratedRed: 0.122, green: 0.137, blue: 0.141, alpha: 1),
    ))
    /// Row background inside a card.
    static let leaveRowFill = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.953, green: 0.961, blue: 0.965, alpha: 1),
        dark: NSColor(calibratedRed: 0.165, green: 0.184, blue: 0.188, alpha: 1),
    ))
    /// Input well fill. Lighter than rows in dark mode (as macOS fields are), white in light mode.
    static let leaveInputFill = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(calibratedRed: 0.208, green: 0.227, blue: 0.231, alpha: 1),
    ))
    static let leaveBorder = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.11),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10),
    ))
    static let leaveShadow = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.07),
        dark: NSColor(calibratedWhite: 0, alpha: 0.35),
    ))
    /// Primary text. Near-neutral so it contrasts with the accent and status colors.
    static let leaveInk = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.067, green: 0.102, blue: 0.106, alpha: 1),
        dark: NSColor(calibratedRed: 0.945, green: 0.953, blue: 0.957, alpha: 1),
    ))
    /// Secondary text.
    static let leaveMuted = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.329, green: 0.373, blue: 0.384, alpha: 1),
        dark: NSColor(calibratedRed: 0.667, green: 0.702, blue: 0.710, alpha: 1),
    ))
    // Accent and success share the brand teal today but are separate tokens, so "interactive" and
    // "all good" can diverge later without hunting through every call site. The accent is also the
    // app-wide tint (see `ContentView` and the AccentColor asset), replacing macOS system blue.

    /// Brand accent: native controls, buttons, selection, focus, counts, links, and informational notes.
    static let leaveAccent = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.000, green: 0.431, blue: 0.384, alpha: 1),
        dark: NSColor(calibratedRed: 0.333, green: 0.835, blue: 0.769, alpha: 1),
    ))
    /// Fill for prominent buttons and the app mark; dark enough in both appearances to carry white labels.
    static let leaveAccentFill = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.000, green: 0.431, blue: 0.384, alpha: 1),
        dark: NSColor(calibratedRed: 0.000, green: 0.490, blue: 0.435, alpha: 1),
    ))
    /// Success status: active schedule, connected, enabled, free, accepted, nothing pending.
    static let leaveSuccess = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.000, green: 0.431, blue: 0.384, alpha: 1),
        dark: NSColor(calibratedRed: 0.333, green: 0.835, blue: 0.769, alpha: 1),
    ))
    /// Warning status.
    static let leaveOrange = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.690, green: 0.275, blue: 0.000, alpha: 1),
        dark: NSColor(calibratedRed: 1.000, green: 0.667, blue: 0.392, alpha: 1),
    ))
    /// Error status.
    static let leaveRed = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.749, green: 0.141, blue: 0.141, alpha: 1),
        dark: NSColor(calibratedRed: 1.000, green: 0.451, blue: 0.424, alpha: 1),
    ))
}


extension NSColor {
    static func leaveAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
