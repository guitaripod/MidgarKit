import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The "Your Midgar" panel: the Midgar apps the person has with what they own in each, then a few more worth a look. It sits over the canvas, between the header and the bottom card.
struct YourMidgarPanel: View {
    let section: YourMidgarSection
    let hostBundleID: String?
    let installed: Set<String>
    let onSelect: (MidgarApp) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group(title: MidgarStrings.yourApps) {
                        ForEach(section.yours) { yours in
                            YourMidgarRow(
                                app: yours.app,
                                owned: yours.owned,
                                status: status(for: yours.app),
                                priceLabel: nil,
                                onSelect: onSelect
                            )
                        }
                    }
                    if !section.suggestions.isEmpty {
                        group(title: MidgarStrings.moreFromMidgar) {
                            ForEach(section.suggestions) { app in
                                YourMidgarRow(app: app, owned: [], status: nil, priceLabel: app.priceLabel, onSelect: onSelect)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18 * PortalMetrics.scale)
                .padding(.bottom, 18 * PortalMetrics.scale)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(PortalColor.space).opacity(0.85)))
        .portalGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text(MidgarStrings.yourMidgar)
                .font(.system(size: 22 * PortalMetrics.scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12 * PortalMetrics.scale, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30 * PortalMetrics.scale, height: 30 * PortalMetrics.scale)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MidgarStrings.close)
        }
        .padding(.horizontal, 18 * PortalMetrics.scale)
        .padding(.top, 16 * PortalMetrics.scale)
        .padding(.bottom, 10 * PortalMetrics.scale)
    }

    private func group<Rows: View>(title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12 * PortalMetrics.scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    private func status(for app: MidgarApp) -> String? {
        let bundle = app.bundleId.lowercased()
        if bundle == hostBundleID?.lowercased() { return MidgarStrings.youAreHere }
        return installed.contains(bundle) ? MidgarStrings.installed : nil
    }
}

/// One app in the panel: icon, name, what they own or the tagline, and for a suggestion its price pill.
struct YourMidgarRow: View {
    let app: MidgarApp
    let owned: [OwnedItem]
    let status: String?
    let priceLabel: String?
    let onSelect: (MidgarApp) -> Void

    var body: some View {
        let accent = PortalColor(hex: app.accentHex)
        Button {
            onSelect(app)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                YourMidgarIcon(app: app, size: 48 * PortalMetrics.scale)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(app.shortName)
                            .font(.system(size: 16 * PortalMetrics.scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let status { PortalChip(text: status, accent: accent) }
                    }
                    details
                }
                Spacer(minLength: 8)
                if let priceLabel {
                    Text(priceLabel)
                        .font(.system(size: 13 * PortalMetrics.scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30 * PortalMetrics.scale)
                        .background(Capsule().fill(Color(accent.darkened(0.15))))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        if owned.isEmpty {
            Text(app.tagline ?? app.genre ?? "")
                .font(.system(size: 13 * PortalMetrics.scale, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(owned, id: \.name) { item in
                    HStack(spacing: 6) {
                        PortalChip(text: item.name, accent: PortalColor(hex: app.accentHex))
                        Text(item.detail)
                            .font(.system(size: 12 * PortalMetrics.scale, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

/// The app's icon: its bundled artwork at once, the App Store's when that loads, a monogram on the app's colour until either does.
struct YourMidgarIcon: View {
    let app: MidgarApp
    let size: CGFloat
    @State private var image: MidgarImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color(PortalColor(hex: app.accentHex).darkened(0.1)))
            if let image {
                Image(midgar: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(app.monogram)
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: app.appId) { await load() }
    }

    private func load() async {
        if let bundled = await midgarBundledIcon(app.appId, maxPixel: size, scale: displayScale) {
            image = bundled
        }
        if let remote = await midgarLoadImage(app.iconURL, maxPixel: size, scale: displayScale) {
            image = remote
        }
    }
}

extension Image {
    init(midgar image: MidgarImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}
