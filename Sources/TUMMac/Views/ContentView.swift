import SwiftUI
import TUMCore

struct ContentView: View {
    @ObservedObject var store: UsageStore
    var onOpenSettings: (() -> Void)?
    var onContentHeight: ((CGFloat) -> Void)?
    @Environment(\.openURL) private var openURL

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var gridProviders: [ProviderSnapshot] {
        store.dashboard.providers.filter { !$0.fullWidth }
    }

    private var wideProviders: [ProviderSnapshot] {
        store.dashboard.providers.filter(\.fullWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(gridProviders) { snapshot in
                        ProviderCardView(snapshot: snapshot)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                ForEach(wideProviders) { snapshot in
                    ProviderCardView(snapshot: snapshot, compactHeight: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .overlay {
                if store.dashboard.providers.isEmpty && !store.isRefreshing {
                    Text("No providers enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 760, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onContentHeight?(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in
                        onContentHeight?(height)
                    }
            }
        }
        .task {
            await store.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TUM")
                    .font(.system(size: 24, weight: .bold))
                Text(SkeptacularBrand.pitch)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(
                        store.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh")
            Button {
                store.shareSnapshot()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Share snapshot")
        }
    }

    private var tipNudge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TipJar.nudgeMessage)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(TipJar.buyButtonTitle) {
                    store.dismissTipNudge(.buyCoffee)
                    openURL(SkeptacularBrand.tipURL)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(TipJar.dismissButtonTitle) {
                    store.dismissTipNudge(.notNow)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.showTipNudge {
                tipNudge
            }
            if let shareNotice = store.shareNotice {
                Text(shareNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Refreshes when opened")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Share snapshot") {
                    store.shareSnapshot()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                Button("Settings") {
                    onOpenSettings?()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                Button("Quit") {
                    store.quit()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                Link("Leave a tip", destination: SkeptacularBrand.tipURL)
                Link("Also from Skeptacular Apps", destination: SkeptacularBrand.activeClipboardURL)
            }
            .font(.system(size: 11, weight: .medium))
        }
    }
}
