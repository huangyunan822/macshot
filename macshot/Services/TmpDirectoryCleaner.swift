import Foundation

/// Purges stale macshot files from `NSTemporaryDirectory()` on launch.
///
/// Why this exists: macshot writes various temporaries (clipboard
/// pastables, recording outputs before save, upload intermediates, GIF
/// conversion scratch, legacy UUID-named scraps). Most have matching
/// cleanup in the happy path, but not all — an app crash, force quit,
/// or cancelled recording can orphan the file indefinitely. One user
/// reported 1.2 GB of leftovers across ~1,200 files after a few weeks
/// of use (issue #128).
///
/// Strategy: on launch, scan our sandbox tmp dir for files matching
/// patterns we know are ours, and delete any older than `ttl`. The
/// scan is prefix-based so we can't accidentally touch framework or
/// system-managed files (WebKit/, TemporaryItems/). A TTL gate keeps
/// the sweep from racing with anything currently in flight.
enum TmpDirectoryCleaner {

    /// How old a file must be (since last modification) to count as stale.
    /// One day is generous — long enough to cover "I copied yesterday,
    /// didn't paste until today" and short enough that we don't hoard
    /// abandoned recordings for weeks.
    private static let ttl: TimeInterval = 24 * 60 * 60

    /// Filename prefixes we know are ours. Everything else is left alone.
    ///
    /// NOTE: the single-file clipboard files (`macshot-clipboard.png`,
    /// `macshot-clipboard-recording.*`) are intentionally excluded —
    /// they're overwritten in place, not accumulated. The `-` prefix
    /// here catches the *legacy* UUID-named variants (`macshot-clipboard-<uuid>.png`)
    /// that older builds produced. Once everyone has updated, this
    /// one-shot cleanup is the end of them.
    private static let prefixes: [String] = [
        "macshot-clipboard-",   // legacy UUID-named clipboard PNGs
        "macshot_upload_",      // upload intermediates
        "macshot_mic_",         // legacy microphone captures
        "macshot_cursor_debug", // legacy debug log
        "macshot_",             // legacy date-named captures
        // Note: "Recording " files are intentionally NOT swept. When the
        // user configures `recordingOnStop = "finder"`, these files stay
        // in tmp until the user manually moves them. Auto-deleting them
        // after 24h would silently lose the user's recording.
    ]

    /// Suffixes (extensions) we know are our scratch output when paired
    /// with a UUID-ish basename. GIF conversion and video re-encode both
    /// use `<uuid>.gif` / `<uuid>.mp4` tmp paths.
    private static let uuidScratchExtensions: Set<String> = ["gif", "mp4"]

    /// Kick off the sweep. Safe to call from the main thread — the work
    /// dispatches to a background queue.
    static func sweep() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory
            let cutoff = Date().addingTimeInterval(-ttl)

            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return }

            var removed = 0
            var bytesFreed: UInt64 = 0
            for url in contents {
                let name = url.lastPathComponent

                // Keep the fixed clipboard files — they're designed to be
                // overwritten, not swept.
                if name == "macshot-clipboard.png" { continue }
                if name.hasPrefix("macshot-clipboard-recording.") { continue }

                // Must match a known prefix OR be a UUID-named scratch file
                // OR a sandbox write-quarantine leftover that's ours.
                let prefixMatch = prefixes.contains { name.hasPrefix($0) }
                let uuidMatch = isUUIDScratchFile(name: name)
                let sandboxMatch = isSandboxQuarantineFile(name: name)
                guard prefixMatch || uuidMatch || sandboxMatch else { continue }

                // Regular file + older than cutoff.
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified < cutoff else { continue }

                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if (try? fm.removeItem(at: url)) != nil {
                    removed += 1
                    bytesFreed += UInt64(size)
                }
            }

            #if DEBUG
            if removed > 0 {
                print("[TmpDirectoryCleaner] removed \(removed) stale tmp files, freed \(bytesFreed) bytes")
            }
            #endif
        }
    }

    /// A filename like `AB12CD34-....gif` or `12F8...-99AB.mp4` — UUID
    /// basename with a scratch extension. Used by GIF conversion and
    /// quality-preset re-encode tmps.
    private static func isUUIDScratchFile(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard uuidScratchExtensions.contains(ext) else { return false }
        let base = (name as NSString).deletingPathExtension
        return UUID(uuidString: base) != nil
    }

    /// A filename like `AB12CD34-....gif.sb-XXXX-YYYY` — macOS writes
    /// these as temporary quarantine stubs during sandboxed writes and
    /// usually cleans them up itself, but stragglers can linger. They
    /// only appear in our container so they're always ours to clean.
    /// We match on the `.sb-` infix plus a UUID leading component.
    private static func isSandboxQuarantineFile(name: String) -> Bool {
        guard name.contains(".sb-") else { return false }
        // Leading segment before the first `.` should be a UUID.
        guard let firstDot = name.firstIndex(of: ".") else { return false }
        let base = String(name[..<firstDot])
        return UUID(uuidString: base) != nil
    }
}
