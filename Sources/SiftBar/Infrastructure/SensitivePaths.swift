import Foundation

/// Folders that make macOS show a media or photo privacy prompt when a broad
/// `du` walk enters them. Even a read-only size measurement is enough to
/// trigger the prompt, so broad walks skip these names entirely; their bytes
/// stay in "System & other".
///
/// `du -I` matches names case-sensitively, so the ignore list carries the
/// lowercase form and the capitalization used on disk.
enum SensitivePaths {
    /// Lowercased names for in-memory filtering (`PathSizer.excludingNames`).
    static let mediaNames: Set<String> = Set(duIgnoreNames.map { $0.lowercased() })

    /// Names passed to `du -I`. Duplicates are harmless; both casings are kept
    /// so a case-sensitive volume behaves like the default one.
    static let duIgnoreNames: [String] = [
        "Music", "music",
        "Photos", "photos",
        "TV", "tv",
        "Podcasts", "podcasts",
        "com.apple.Music", "com.apple.music",
        "com.apple.MediaPlayer", "com.apple.mediaplayer",
        "com.apple.MediaLibraryService", "com.apple.medialibraryservice",
        "com.apple.mediaanalysisd",
        "com.apple.MediaPlaybackCore.PlaybackEventStreams",
        "com.apple.mediaplaybackcore.playbackeventstreams",
        "com.apple.photos",
        "com.apple.mobileslideshow",
        "com.apple.Podcasts", "com.apple.podcasts",
        "com.apple.TV", "com.apple.tv",
        "iLifeMediaBrowser", "ilifemediabrowser",
        "group.com.apple.podcasts",
        "group.com.apple.tv.sharedcontainer",
        "group.tvappservices.container",
        "group.com.apple.photolibraryd.private",
        "group.com.apple.mobileslideshow.PhotosFileProvider",
        "group.com.apple.mobileslideshow.photosfileprovider",
        "group.com.apple.Photos.PhotosFileProvider",
        "group.com.apple.photos.photosfileprovider"
    ]
}
