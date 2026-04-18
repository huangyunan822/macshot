import Foundation

/// A dedicated tmp subdirectory for short-lived share/drag files.
///
/// Drag-to-Finder and share-sheet flows write a file to tmp with the
/// user-configured filename (e.g. "Screenshot 2026-04-18.png") so the
/// destination app gets a recognizable name. The file has to exist as a
/// *real* file URL — we can't use raw data for drag — but there's no
/// deterministic signal for "drop accepted, safe to delete." Delegate
/// callbacks fire too early for some targets (they read the file
/// *after* the callback in their own async handler).
///
/// Solution: isolate these writes in a subfolder we 100% own, then sweep
/// the whole folder aggressively on launch. Anything older than a few
/// minutes is definitely not being read any more.
enum TmpScratchDirectory {

    /// Path to the scratch subfolder. Created lazily on first access.
    static let url: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macshot-share")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    /// Files older than this on launch are deleted. Five minutes is far
    /// longer than any drag/share takes in practice, short enough that
    /// abandoned scratch files don't accumulate.
    private static let ttl: TimeInterval = 5 * 60

    /// Build a URL inside the scratch dir with the given filename. Creates
    /// the dir if needed. Callers write their data here.
    static func makeURL(filename: String) -> URL {
        return url.appendingPathComponent(filename)
    }

    /// Delete everything in the scratch dir older than `ttl`. Call on
    /// app launch — runs off the main thread.
    static func sweep() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            let cutoff = Date().addingTimeInterval(-ttl)
            for fileURL in contents {
                guard let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      mod < cutoff else { continue }
                try? fm.removeItem(at: fileURL)
            }
        }
    }
}
