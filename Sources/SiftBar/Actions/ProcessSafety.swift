import Foundation

/// Decides which processes SiftBar must never suggest terminating.
enum ProcessSafety {
    /// Critical macOS processes. Killing any of these can log the user out,
    /// freeze the UI, or destabilize the system.
    static let protectedNames: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "Dock",
        "Finder",
        "SystemUIServer",
        "ControlCenter",
        "NotificationCenter",
        "hidd",
        "coreaudiod",
        "configd",
        "powerd",
        "opendirectoryd",
        "securityd",
        "syslogd",
        "logd",
        "mds",
        "mds_stores",
        "mdworker",
        "UserEventAgent",
        "cfprefsd",
        "distnoted",
        "runningboardd",
        "watchdogd",
        "thermalmonitord",
        "corebrightnessd",
        "bluetoothd",
        "airportd"
    ]

    /// System binaries are managed by macOS and should be stopped through
    /// their launch service, never by killing the process.
    static let systemPathPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/sbin/",
        "/Library/Apple/"
    ]

    static func isProtected(pid: Int32, user: String, command: String, name: String) -> Bool {
        if pid <= 1 { return true }
        if protectedNames.contains(name) { return true }
        if user == "root" { return true }
        return systemPathPrefixes.contains { command.hasPrefix($0) }
    }

    static func isProtected(_ entry: ProcessCollector.Entry) -> Bool {
        isProtected(
            pid: entry.pid,
            user: entry.user,
            command: entry.command,
            name: entry.name
        )
    }
}
