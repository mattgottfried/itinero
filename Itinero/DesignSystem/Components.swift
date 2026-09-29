import SwiftUI

// MARK: - Status Tile

struct StatusTile: View {
    enum Content { case symbol(String), number(String, unit: String) }
    let tone: StatusTone
    let content: Content
    var size: CGFloat = 46
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            switch content {
            case .symbol(let name):
                Image(systemName: name).font(.title3.weight(.semibold))
            case .number(let value, let unit):
                Text(value).font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.caption2.weight(.semibold)).opacity(0.8) }
            }
        }
        .foregroundStyle(tone.color)
        .frame(width: size, height: size)
        .background(tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - List-row card

/// The everyday repeating row: tile + text stack. Callers supply the accessibility label/value/hint.
struct ListRowCard<Detail: View>: View {
    let tone: StatusTone
    let tile: StatusTile.Content
    let title: String
    var subtitle: String?
    var subtitleSymbol: String?
    var subtitleTone: StatusTone = .neutral
    var featured = false
    var dimmed = false
    let accessibilityValue: String
    let accessibilityHint: String
    @ViewBuilder var detail: () -> Detail

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let theme = AppTheme.standard

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            StatusTile(tone: tone, content: tile)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Label(subtitle, systemImage: subtitleSymbol ?? "info.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(subtitleTone.color)
                }
                detail().font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if featured {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(StatusTone.good.color.opacity(0.6), lineWidth: 1.5)
            }
        }
        .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
        .opacity(dimmed ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

extension ListRowCard where Detail == EmptyView {
    init(tone: StatusTone, tile: StatusTile.Content, title: String, subtitle: String? = nil,
         subtitleSymbol: String? = nil, subtitleTone: StatusTone = .neutral,
         featured: Bool = false, dimmed: Bool = false,
         accessibilityValue: String, accessibilityHint: String) {
        self.init(tone: tone, tile: tile, title: title, subtitle: subtitle, subtitleSymbol: subtitleSymbol,
                  subtitleTone: subtitleTone, featured: featured, dimmed: dimmed,
                  accessibilityValue: accessibilityValue, accessibilityHint: accessibilityHint) { EmptyView() }
    }
}

// MARK: - Section card

struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var tone: StatusTone = .info
    @ViewBuilder var content: () -> Content
    private let theme = AppTheme.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(tone.color)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Stat chip

struct StatChip: View {
    let value: String
    let label: String
    var tone: StatusTone = .info

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(tone.color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Badge / capsule

struct BadgePill: View {
    let text: String
    let systemImage: String
    var tone: StatusTone = .info
    /// Solid fill for urgent/rare, tinted for normal/frequent.
    var solid = false

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(solid ? Color.white : tone.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(solid ? tone.color : tone.color.opacity(0.12), in: Capsule())
    }
}

struct BookingBadge: View {
    let status: BookingStatus
    var daysUntil: Int?
    var body: some View {
        let tone = statusTone(for: status, daysUntil: daysUntil)
        BadgePill(text: status.label, systemImage: status.symbol, tone: tone, solid: tone == .alert)
    }
}

// MARK: - Hero / share card

struct HeroCard<Footer: View>: View {
    let eyebrow: String
    let headline: String
    var stats: [(icon: String, value: String, label: String)] = []
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                Text(headline).font(.title2.bold()).foregroundStyle(.white)
            }
            if !stats.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                        StatBlock(icon: stat.icon, value: stat.value, label: stat.label)
                    }
                }
            }
            footer().font(.subheadline.weight(.medium)).foregroundStyle(.white)
            HStack { Spacer(); Text("Itinero").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6)) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [AppTheme.standard.primaryColor, .indigo],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension HeroCard where Footer == EmptyView {
    init(eyebrow: String, headline: String, stats: [(icon: String, value: String, label: String)] = []) {
        self.init(eyebrow: eyebrow, headline: headline, stats: stats) { EmptyView() }
    }
}

struct StatBlock: View {
    let icon: String, value: String, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Round icon button

struct RoundIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.body.weight(.medium)).padding(8)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Undo toast

struct UndoToast: View {
    let message: String
    let undo: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text(message).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo", action: undo).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .light), trigger: message)
    }
}

// MARK: - Hub tile

/// A compact "jump to" card for a trip's hub: one glanceable number and what it counts.
struct HubTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tone: StatusTone = .info
    let action: () -> Void
    private let theme = AppTheme.standard

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusTile(tone: tone, content: .symbol(systemImage), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Opens \(title)")
        .accessibilityAddTraits(.isButton)
    }
}
