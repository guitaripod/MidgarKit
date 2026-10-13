import SwiftUI

extension Color {
    init(_ color: PortalColor) {
        self.init(.sRGB, red: color.r, green: color.g, blue: color.b, opacity: color.a)
    }
}

/// The whole portal: a deep-space backdrop that takes the focused app's colour, the canvas, a
/// slim header and a card describing whatever sits at the centre.
struct PortalScreen: View {
    @ObservedObject var model: PortalModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let headerHeight: CGFloat = 64 * PortalMetrics.scale
    static let cardHeight: CGFloat = 156 * PortalMetrics.scale

    var body: some View {
        GeometryReader { proxy in
            let layout = PortalScreenLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
            ZStack {
                PortalBackdrop(accent: model.accent, animated: !reduceMotion)
                PortalCanvas(model: model, insets: layout.canvasInsets)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    PortalHeader(model: model)
                        .padding(.top, proxy.safeAreaInsets.top > 0 ? 0 : 8)
                    Spacer(minLength: 0)
                    if !layout.isSideCard {
                        PortalCard(model: model)
                            .frame(maxWidth: 560 * PortalMetrics.scale)
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 16))
                    }
                }
                if layout.isSideCard {
                    PortalCard(model: model)
                        .frame(width: layout.sideCardWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, max(proxy.safeAreaInsets.trailing, 16))
                }
            }
        }
        .background(Color(PortalColor.space).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

/// Where the card goes: under the canvas on tall screens, beside it when the screen is too short
/// for both, as on a phone held sideways.
struct PortalScreenLayout {
    let size: CGSize
    let safeArea: EdgeInsets

    var isSideCard: Bool { size.width > size.height && size.height < 560 }

    var sideCardWidth: CGFloat { min(340 * PortalMetrics.scale, size.width * 0.42) }

    var canvasInsets: PortalInsets {
        let top = safeArea.top + PortalScreen.headerHeight
        if isSideCard {
            return PortalInsets(
                top: top,
                bottom: max(safeArea.bottom, 12),
                trailing: sideCardWidth + max(safeArea.trailing, 16) + 8
            )
        }
        return PortalInsets(top: top, bottom: safeArea.bottom + PortalScreen.cardHeight + 28)
    }
}

struct PortalBackdrop: View {
    let accent: PortalColor
    let animated: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(PortalColor.space), Color(PortalColor(r: 0.045, g: 0.05, b: 0.15))],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(accent.withAlpha(0.42)), Color(accent.withAlpha(0.12)), .clear],
                center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 460
            )
            .id(accent.hashKey)
            .transition(.opacity)
            RadialGradient(
                colors: [Color(PortalColor.midgar.withAlpha(0.14)), .clear],
                center: UnitPoint(x: 0.95, y: 0.02), startRadius: 0, endRadius: 360
            )
        }
        .animation(animated ? .easeInOut(duration: 0.7) : nil, value: accent.hashKey)
        .ignoresSafeArea()
    }
}

extension PortalColor {
    var hashKey: String { "\(Int(r * 255))-\(Int(g * 255))-\(Int(b * 255))" }
}

struct PortalHeader: View {
    @ObservedObject var model: PortalModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Midgar")
                    .font(.system(size: 20 * PortalMetrics.scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12 * PortalMetrics.scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            Spacer()
            #if !os(tvOS)
            Button {
                model.perform(.close)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14 * PortalMetrics.scale, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36 * PortalMetrics.scale, height: 36 * PortalMetrics.scale)
                    .portalGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .closeShortcut()
            .accessibilityLabel(MidgarStrings.close)
            #endif
        }
        .padding(.horizontal, 20)
        .frame(height: PortalScreen.headerHeight)
    }

    private var subtitle: String {
        MidgarStrings.installedCount(model.installedCount, of: model.availableHere)
    }
}

struct PortalCard: View {
    @ObservedObject var model: PortalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.selection {
            case .core:
                coreContent
            case .app(let app):
                appContent(app)
            }
        }
        .id(model.selection)
        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.16)), removal: .identity))
        .padding(18 * PortalMetrics.scale)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, minHeight: PortalScreen.cardHeight, maxHeight: PortalScreen.cardHeight, alignment: .topLeading)
        .portalGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var coreContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Midgar Oy")
                .font(.system(size: 22 * PortalMetrics.scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(MidgarStrings.coreBlurb)
                .font(.system(size: 15 * PortalMetrics.scale, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                PortalPillButton(title: MidgarStrings.allApps, accent: PortalColor.midgar) {
                    model.perform(.developerPage)
                }
            }
        }
    }

    private func appContent(_ app: MidgarApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(app.shortName)
                    .font(.system(size: 22 * PortalMetrics.scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if app.hasRating {
                    Label(String(format: "%.1f", app.rating ?? 0), systemImage: "star.fill")
                        .font(.system(size: 13 * PortalMetrics.scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(PortalColor(r: 1, g: 0.8, b: 0.25)))
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                }
            }
            Text(app.tagline ?? app.genre ?? "")
                .font(.system(size: 15 * PortalMetrics.scale, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let status = statusLabel(for: app) { PortalChip(text: status, accent: PortalColor(hex: app.accentHex)) }
                if let genre = app.genre { PortalChip(text: genre, accent: nil) }
                Spacer(minLength: 0)
                if let title = model.buttonTitle(for: app) {
                    PortalPillButton(title: title, accent: PortalColor(hex: app.accentHex)) {
                        model.perform(model.action(for: app))
                    }
                }
            }
        }
    }

    private func statusLabel(for app: MidgarApp) -> String? {
        if model.isHost(app) { return MidgarStrings.youAreHere }
        if model.isInstalled(app) { return MidgarStrings.installed }
        return nil
    }
}

struct PortalChip: View {
    let text: String
    let accent: PortalColor?

    var body: some View {
        Text(text)
            .font(.system(size: 11 * PortalMetrics.scale, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(accent.map { Color($0.withAlpha(0.42)) } ?? Color.white.opacity(0.12))
            )
            .lineLimit(1)
    }
}

struct PortalPillButton: View {
    let title: String
    let accent: PortalColor
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        pill
        #else
        Button(action: action) { pill }
            .buttonStyle(.plain)
        #endif
    }

    private var pill: some View {
        Text(title)
            .font(.system(size: 15 * PortalMetrics.scale, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22 * PortalMetrics.scale)
            .frame(height: 38 * PortalMetrics.scale)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(accent.lightened(0.18)), Color(accent.darkened(0.2))],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .shadow(color: Color(accent.withAlpha(0.5)), radius: 10, y: 3)
    }
}

extension View {
    /// Liquid Glass where the OS has it, a frosted material everywhere else.
    @ViewBuilder
    func portalGlass<S: InsettableShape>(in shape: S) -> some View {
        #if os(visionOS)
        frostedGlass(in: shape)
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            frostedGlass(in: shape)
        }
        #endif
    }

    private func frostedGlass<S: InsettableShape>(in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    /// Escape closes the portal wherever a hardware keyboard exists.
    @ViewBuilder
    func closeShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(.cancelAction)
        #endif
    }
}
