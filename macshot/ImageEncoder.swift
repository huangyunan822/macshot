import Cocoa
import UniformTypeIdentifiers

/// Shared image encoding with user-configurable format and quality.
enum ImageEncoder {

    enum Format: String {
        case png = "png"
        case jpeg = "jpeg"
    }

    static var format: Format {
        if let raw = UserDefaults.standard.string(forKey: "imageFormat"),
           let fmt = Format(rawValue: raw) {
            return fmt
        }
        return .png
    }

    /// JPEG quality 0.0–1.0 (only used when format is .jpeg)
    static var quality: CGFloat {
        if let q = UserDefaults.standard.object(forKey: "imageQuality") as? Double {
            return CGFloat(max(0.1, min(1.0, q)))
        }
        return 0.85
    }

    static var fileExtension: String {
        switch format {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    static var utType: UTType {
        switch format {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    /// Encode an NSImage to Data in the configured format.
    static func encode(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }

    /// Copy image to pasteboard in the configured format (always includes TIFF for compatibility).
    static func copyToClipboard(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        if let encoded = encode(image) {
            pasteboard.setData(encoded, forType: format == .jpeg ? .init("public.jpeg") : .png)
        }
    }
}
