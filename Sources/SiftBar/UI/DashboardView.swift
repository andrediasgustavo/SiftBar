import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            metrics
            analysisPanel
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("SiftBar")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            }

            Text("Analyze first. Change only what you choose.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            MetricCard(
                title: "Memory",
                value: formattedMemory,
                subtitle: "Physical RAM"
            )
            MetricCard(
                title: "Disk Free",
                value: formattedDisk,
                subtitle: "Startup volume"
            )
            MetricCard(
                title: "Scan",
                value: appState.isScanning ? "Running" : "Idle",
                subtitle: "Read-only"
            )
        }
    }

    private var analysisPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis")
                .font(.headline)

            Text(appState.errorMessage ?? appState.status)
                .font(.callout)
                .foregroundStyle(appState.errorMessage == nil ? Color.secondary : Color.red)

            HStack(spacing: 12) {
                Button {
                    Task { await appState.analyze() }
                } label: {
                    Label(appState.isScanning ? "Analyzing..." : "Analyze", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isScanning)

                if appState.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("Read-only by default. Nothing is changed without confirmation.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var formattedMemory: String {
        guard let snapshot = appState.snapshot else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(snapshot.totalMemoryBytes), countStyle: .memory)
    }

    private var formattedDisk: String {
        guard let snapshot = appState.snapshot else { return "—" }
        return ByteCountFormatter.string(fromByteCount: snapshot.freeDiskBytes, countStyle: .file)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
