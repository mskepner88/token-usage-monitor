import SwiftUI
import TUMCore

struct ProviderCardView: View {
    let snapshot: ProviderSnapshot
    var compactHeight: Bool = false
    @State private var expanded = false

    private var accent: Color {
        Color(hex: snapshot.id.accentHex) ?? .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let message = snapshot.message, snapshot.meters.isEmpty {
                Text(shortMessage(message))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if snapshot.meters.count == 1, let meter = snapshot.meters.first {
                singleMeter(meter)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(snapshot.meters.prefix(snapshot.fullWidth ? 3 : 2)) { meter in
                        meterColumn(meter)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            footer
        }
        .padding(11)
        .frame(minHeight: compactHeight || snapshot.fullWidth ? 120 : 148, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.id.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(snapshot.planLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(liveLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(liveColor)
        }
    }

    private func singleMeter(_ meter: UsageMeter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meter.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(meter.percentLeft)% left")
                    .font(.system(size: 12, weight: .semibold))
            }
            SegmentedMeterView(fractionRemaining: meter.remainingFraction, color: accent)
            if let reset = meter.resetDescription {
                Text(reset)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = meter.footnote {
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func meterColumn(_ meter: UsageMeter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meter.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(meter.percentLeft)% left")
                    .font(.system(size: 11, weight: .semibold))
            }
            SegmentedMeterView(
                fractionRemaining: meter.remainingFraction,
                color: accent,
                segments: 14
            )
            if let reset = meter.resetDescription {
                Text(reset)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = meter.footnote {
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(snapshot.detailSummary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            if let url = snapshot.id.dashboardURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(TUMFormatting.time(snapshot.fetchedAt))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    private var iconName: String {
        switch snapshot.id {
        case .grok: "x.circle.fill"
        case .codex: "terminal"
        case .claude: "sparkle"
        case .cursor: "cursorarrow.click.2"
        case .ollama: "cloud"
        case .gemini: "sparkles"
        case .cerebras: "bolt.fill"
        case .bedrock: "cloud.fill"
        case .vercelGateway: "triangle.fill"
        }
    }

    private var liveLabel: String {
        switch snapshot.state {
        case .live: "LIVE"
        case .stale: "STALE"
        case .offline: "OFF"
        case .needsAuth: "AUTH"
        case .error: "ERR"
        }
    }

    private var liveColor: Color {
        switch snapshot.state {
        case .live: accent
        case .stale: .orange
        case .offline: .secondary
        case .needsAuth: .red
        case .error: .red
        }
    }

    private func shortMessage(_ message: String) -> String {
        if message.contains("rate_limit_error") || message.contains("HTTP 429") {
            return "Rate limited — try again shortly."
        }
        if message.count > 120 {
            return String(message.prefix(117)) + "…"
        }
        return message
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
