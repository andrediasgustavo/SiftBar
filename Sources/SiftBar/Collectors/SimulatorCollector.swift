import Foundation

/// Reports iOS/iPadOS simulator storage from `simctl`.
///
/// The disk map only sees `~/Library/Developer/CoreSimulator` as one
/// "Developer" number, and the cache whitelist deliberately did not include
/// device data. This collector names the group, itemizes only genuinely large
/// devices, and offers Apple's own `simctl delete` for a specific device.
/// Unavailable devices (runtime removed) get one safe, explicit action.
struct SimulatorCollector: Collector {
    let category: ItemCategory = .caches

    /// Individual devices below this size stay in the summary row; listing
    /// dozens of tiny simulators would recreate the noise this page avoids.
    static let minimumDeviceBytes: Int64 = 500 * 1024 * 1024
    static let limit = 10

    struct Device: Sendable, Equatable {
        let name: String
        let udid: String
        let runtime: String
        let state: String
        let isAvailable: Bool
        let dataPath: String
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        guard let result = try? await CommandRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j"],
            timeout: 10
        ), result.exitCode == 0 else {
            return []
        }

        let devices = Self.parse(Data(result.stdout.utf8))
        guard !devices.isEmpty else { return [] }

        let running = await RunningProcesses.names()
        return Self.items(from: devices, simulatorRunning: running.contains("simulator"))
    }

    static func parse(_ data: Data) -> [Device] {
        struct Payload: Decodable {
            let devices: [String: [RawDevice]]
        }

        struct RawDevice: Decodable {
            let name: String
            let udid: String
            let runtime: String?
            let state: String?
            let isAvailable: Bool?
            let dataPath: String?
            let dataPathSize: Int64?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var devices: [Device] = []

        for (runtimeKey, entries) in payload.devices {
            let runtime = runtimeName(from: runtimeKey)

            for entry in entries {
                guard UUID(uuidString: entry.udid) != nil else { continue }

                devices.append(Device(
                    name: entry.name,
                    udid: entry.udid,
                    runtime: runtime,
                    state: entry.state ?? "Unknown",
                    isAvailable: entry.isAvailable ?? true,
                    dataPath: entry.dataPath
                        ?? "\(home)/Library/Developer/CoreSimulator/Devices/\(entry.udid)/data",
                    bytes: entry.dataPathSize ?? 0
                ))
            }
        }

        return devices
    }

    static func runtimeName(from key: String) -> String {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        let raw = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
        let parts = raw.split(separator: "-")

        guard let platform = parts.first else { return raw }

        let version = parts.dropFirst().prefix(2).joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }

    static func items(from devices: [Device], simulatorRunning: Bool) -> [ScanItem] {
        guard !devices.isEmpty else { return [] }

        let total = devices.reduce(Int64(0)) { $0 + $1.bytes }
        let unavailable = devices.filter { !$0.isAvailable }
        let unavailableBytes = unavailable.reduce(Int64(0)) { $0 + $1.bytes }

        var items: [ScanItem] = []

        items.append(ScanItem(
            category: .caches,
            title: "iOS Simulator devices",
            detail: "\(devices.count) simulators use \(format(total)). \(unavailable.count) cannot boot with the current Xcode.",
            impactLabel: format(total),
            impactBytes: total,
            risk: .safe,
            action: .none,
            evidence: "xcrun simctl list devices",
            isInformational: true
        ))

        if !unavailable.isEmpty {
            items.append(ScanItem(
                category: .caches,
                title: "Unavailable simulators",
                detail: "\(unavailable.count) simulators cannot boot because their runtime is no longer installed. Deleting them is safe.",
                impactLabel: format(unavailableBytes),
                impactBytes: unavailableBytes,
                risk: .safe,
                action: .deleteUnavailableSimulators(count: unavailable.count),
                evidence: "xcrun simctl delete unavailable",
                warning: "Deleting a simulator cannot be undone. Xcode can create a new one."
            ))
        }

        let largeDevices = devices
            .filter { $0.isAvailable && $0.bytes >= minimumDeviceBytes }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)

        for device in largeDevices {
            items.append(ScanItem(
                category: .caches,
                title: "\(device.name) simulator",
                detail: "\(device.runtime) · \(device.state). Simulator data: apps, settings and files. Deleting frees the space immediately; Xcode can create a new one.",
                impactLabel: format(device.bytes),
                impactBytes: device.bytes,
                risk: .caution,
                action: .deleteSimulator(
                    udid: device.udid,
                    name: device.name,
                    path: device.dataPath,
                    bytes: device.bytes
                ),
                evidence: device.dataPath,
                warning: simulatorWarning(for: device, simulatorRunning: simulatorRunning)
            ))
        }

        return items
    }

    static func simulatorWarning(for device: Device, simulatorRunning: Bool) -> String? {
        if simulatorRunning {
            return "Simulator is running. Quit it before deleting this device."
        }
        if device.state.lowercased() == "booted" {
            return "This simulator is booted. Shut it down in Simulator before deleting it."
        }
        return nil
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
