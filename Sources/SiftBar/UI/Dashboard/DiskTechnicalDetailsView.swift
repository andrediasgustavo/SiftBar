import SwiftUI

/// Technical explanation of the disk map. It lives behind a popover so the
/// default Disk page can stay plain-language: commands, APFS volumes and
/// purgeable space are here for people who ask for them.
struct DiskTechnicalDetailsView: View {
    let report: ScanReport

    @Environment(\.dismiss) private var dismiss

    private var breakdown: [ScanItem] {
        report.items
            .filter(\.isBreakdown)
            .sorted { ($0.impactBytes ?? 0) > ($1.impactBytes ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("How SiftBar measured this")
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 8)

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("SiftBar reads folder sizes with macOS's built-in `du` command. It never changes files.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(breakdown) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                Text(item.impactLabel)
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if !item.evidence.isEmpty {
                                Text(item.evidence)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(item.children) { child in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)

                                    Text(child.title)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 6)

                                    Text(child.impactLabel)
                                        .font(.system(size: 11.5).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Text(child.evidence)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                                    .padding(.leading, 14)
                            }
                        }
                    }

                    if !report.disk.volumes.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 5) {
                            Text("macOS volume layout")
                                .font(.system(size: 12, weight: .semibold))

                            ForEach(report.disk.volumes) { volume in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(volume.name)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)

                                    Text(volume.roles.joined(separator: ", "))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)

                                    Spacer(minLength: 8)

                                    Text(format(volume.bytes))
                                        .font(.system(size: 11.5).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if report.disk.purgeableBytes > 0 {
                        Text("macOS can also free \(format(report.disk.purgeableBytes)) on demand (purgeable space). That number is already included in Available.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Folder sizes are estimates: APFS can share blocks between folders, so they may not add up exactly.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 470, height: 430)
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
