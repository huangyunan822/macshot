import Cocoa

/// Real NSView-based HUD for scroll capture. Hosted in its own NSPanel so it receives
/// mouse events independently of the overlay window (which has ignoresMouseEvents = true).
class ScrollCaptureHUDView: NSView {

    private let infoLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton()
    private let hintLabel = NSTextField(labelWithString: "")

    var onStop: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = ToolbarLayout.bgColor.cgColor
        layer?.cornerRadius = ToolbarLayout.cornerRadius

        infoLabel.font = .systemFont(ofSize: 12, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.isEditable = false
        infoLabel.isBordered = false
        infoLabel.drawsBackground = false
        infoLabel.lineBreakMode = .byTruncatingTail
        addSubview(infoLabel)

        stopButton.title = "Stop"
        stopButton.bezelStyle = .recessed
        stopButton.isBordered = false
        stopButton.wantsLayer = true
        stopButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        stopButton.layer?.cornerRadius = 12
        stopButton.contentTintColor = .white
        stopButton.font = .systemFont(ofSize: 12, weight: .semibold)
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        addSubview(stopButton)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .white.withAlphaComponent(0.55)
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.drawsBackground = false
        hintLabel.stringValue = "Scroll to capture  ·  Esc to cancel"
        // Hint is added to the panel's content view, not this view (positioned separately)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(stripCount: Int, pixelSize: CGSize, backingScale: CGFloat) {
        if stripCount == 0 {
            infoLabel.stringValue = "Scroll Capture  ·  Capturing first frame…"
        } else {
            let pw = Int(pixelSize.width)
            let ph = Int(pixelSize.height)
            let ptW = Int(CGFloat(pw) / backingScale)
            let ptH = Int(CGFloat(ph) / backingScale)
            infoLabel.stringValue =
                "Scroll Capture  ·  \(stripCount) strip\(stripCount == 1 ? "" : "s")  ·  \(ptW)×\(ptH)"
        }
        infoLabel.sizeToFit()
        layoutSubviews()
    }

    func layoutSubviews() {
        let pad: CGFloat = 8
        let btnW: CGFloat = 56
        let btnH: CGFloat = 24

        let infoW = infoLabel.frame.width
        let totalW = pad + infoW + pad * 2 + btnW + pad
        let barH: CGFloat = 36

        frame.size = NSSize(width: totalW, height: barH)

        infoLabel.frame.origin = NSPoint(x: pad, y: (barH - infoLabel.frame.height) / 2)
        stopButton.frame = NSRect(
            x: totalW - pad - btnW, y: (barH - btnH) / 2, width: btnW, height: btnH)
    }

    @objc private func stopClicked() {
        onStop?()
    }

    var preferredSize: NSSize {
        infoLabel.sizeToFit()
        let pad: CGFloat = 8
        let btnW: CGFloat = 56
        return NSSize(
            width: pad + infoLabel.frame.width + pad * 2 + btnW + pad,
            height: 36
        )
    }
}

/// Floating panel that hosts the scroll capture HUD. Uses its own window so it receives
/// mouse events even when the overlay window has ignoresMouseEvents = true.
class ScrollCaptureHUDPanel: NSPanel {

    let hudView = ScrollCaptureHUDView()
    let hintLabel = NSTextField(labelWithString: "Scroll to capture  ·  Esc to cancel")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 2  // above the overlay window
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let container = NSView()
        contentView = container
        container.addSubview(hudView)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .white.withAlphaComponent(0.55)
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.drawsBackground = false
        container.addSubview(hintLabel)
    }

    func position(relativeTo selectionRect: NSRect, in overlayWindow: NSWindow) {
        hudView.layoutSubviews()
        let hudSize = hudView.frame.size
        hintLabel.sizeToFit()
        let hintSize = hintLabel.frame.size

        // Total content: HUD bar + hint label below or above
        let totalH = hudSize.height + 4 + hintSize.height
        let totalW = max(hudSize.width, hintSize.width + 12)

        // Convert selection rect to screen coords
        let selScreen = overlayWindow.convertToScreen(selectionRect)

        // Position below selection
        var barX = selScreen.midX - totalW / 2
        var barY = selScreen.minY - totalH - 6

        // If below screen, put above selection
        if let screen = overlayWindow.screen {
            if barY < screen.visibleFrame.minY + 4 {
                barY = selScreen.maxY + 6
            }
            barX = max(
                screen.visibleFrame.minX + 4, min(barX, screen.visibleFrame.maxX - totalW - 4))
        }

        setFrame(NSRect(x: barX, y: barY, width: totalW, height: totalH), display: true)

        // Layout inside content view
        hudView.frame.origin = NSPoint(x: (totalW - hudSize.width) / 2, y: hintSize.height + 4)
        hintLabel.frame.origin = NSPoint(x: 6, y: 0)

        contentView?.frame = NSRect(origin: .zero, size: NSSize(width: totalW, height: totalH))
    }
}
