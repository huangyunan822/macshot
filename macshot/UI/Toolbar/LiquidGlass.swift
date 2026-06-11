import Cocoa

/// Liquid Glass theme support (macOS 26 Tahoe+).
///
/// When the user enables the Liquid Glass theme, toolbars, popovers, and HUDs
/// render their background as Apple's `NSGlassEffectView` material instead of a
/// solid dark fill — translucent and refractive, showing the content behind.
///
/// This is a *material* theme, independent of the color-based toolbar
/// customization. It is gated to macOS 26.0+ (where `NSGlassEffectView` exists);
/// on older systems `isAvailable` is false and every call site falls back to the
/// existing solid background, so behavior is unchanged when off.
///
/// IMPORTANT: `NSGlassEffectView` only renders the glass for the view assigned to
/// its `contentView`. Glass added merely as a sibling background does nothing.
/// So a glass surface must HOST its controls inside the glass `contentView`.
enum LiquidGlass {

    static let defaultsKey = "liquidGlassTheme"

    /// True only on macOS 26+ where the glass API exists.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// True when the user has enabled the theme AND the API is available.
    static var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
    }

    /// Create a glass host view that embeds `content` as its `contentView`, or
    /// `nil` when glass isn't enabled/available (caller keeps its solid bg).
    /// The returned host should be placed where the solid background view used
    /// to be; `content` (carrying the controls) is rendered on the glass.
    static func host(_ content: NSView, frame: NSRect, cornerRadius: CGFloat) -> NSView? {
        guard isEnabled else { return nil }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            // `.clear` is the most transparent variant (vs frosted `.regular`) —
            // shows the most of the content behind it.
            glass.style = .clear
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            return glass
        }
        return nil
    }

    /// Keep the glass host and its guaranteed `contentView` exactly aligned with
    /// the owner. This avoids relying on autoresizing from a zero-sized initial
    /// frame, which is especially fragile for material/compositing views.
    static func syncHost(_ host: NSView?, in owner: NSView) {
        guard let host else { return }
        host.frame = owner.bounds
        if #available(macOS 26.0, *), let glass = host as? NSGlassEffectView {
            glass.contentView?.frame = glass.bounds
        }
    }
}
