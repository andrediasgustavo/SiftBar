import Foundation

/// Paths SiftBar is allowed to move to the Trash.
///
/// Collectors only produce these paths today, but the executor checks again so
/// a collector bug (or a forged item) can never delete data outside the known
/// cache locations. The check also rejects path traversal and symlink escapes.
enum CleanupWhitelist {
    static func roots(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [String] {
        [
            "\(home)/.npm/_cacache",
            "\(home)/.expo",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.gradle/caches",
            "\(home)/Library/Caches/Homebrew",
            "\(home)/Library/Developer/CoreSimulator/Caches",
            "\(home)/Library/Caches",
            "/Library/Developer/CoreSimulator/Caches"
        ]
    }

    static func allows(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Bool {
        allows(path, roots: roots(home: home))
    }

    /// Roots are passed explicitly so tests can use a temporary directory.
    static func allows(_ path: String, roots: [String]) -> Bool {
        guard path.hasPrefix("/") else { return false }

        let candidate = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        return roots.contains { root in
            let resolvedRoot = URL(fileURLWithPath: root)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path

            return candidate == resolvedRoot || candidate.hasPrefix(resolvedRoot + "/")
        }
    }
}
