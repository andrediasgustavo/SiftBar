import SwiftUI

struct HistoryView: View {
    let records: [HistoryRecord]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(records) { record in
                            recordView(record)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 680, height: 500)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.title2.weight(.semibold))

                Text("Actions applied by SiftBar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No actions yet")
                .font(.callout.weight(.medium))

            Text("History appears here after you apply a cleanup.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recordView(_ record: HistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)

                Spacer()

                if record.reclaimedBytes > 0 {
                    Text("\(format(record.reclaimedBytes)) freed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }

                Text("\(record.succeeded) succeeded · \(record.failed) failed")
                    .font(.caption)
                    .foregroundStyle(record.failed > 0 ? Color.orange : Color.secondary)
            }

            ForEach(record.entries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(entry.success ? Color.green : Color.red)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.callout)
                            .lineLimit(1)

                        Text(entry.command.replacingOccurrences(of: "\n", with: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !entry.success {
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if entry.reclaimedBytes > 0 {
                        Text(format(entry.reclaimedBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
