import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class GestureTipWindow {
    private var window: NSWindow?
    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var dismissWorkItem: DispatchWorkItem?
    private var isPrepared = false

    public init() {}

    /// Show tip asynchronously — does NOT block the caller.
    public func hide() {
        dismissWorkItem?.cancel()
        window?.orderOut(nil)
    }

    public func updateDetail(_ detail: String) {
        detailLabel?.stringValue = detail
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self?.window?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.window?.orderOut(nil)
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    public func show(title: String, detail: String, at cgPoint: CGPoint?) {
        dismissWorkItem?.cancel()
        prepareIfNeeded()

        titleLabel?.stringValue = title
        detailLabel?.stringValue = detail

        guard let tipWindow = window else { return }

        // Position at bottom center of the screen containing the cursor
        let converter = ScreenCoordinateConverter()
        let screenFrame: CGRect
        if let cgPoint,
           let mapping = converter.mappings.first(where: { $0.containsCGPoint(cgPoint) }),
           let nsScreen = NSScreen.screens.first(where: { $0.frame == mapping.appKitFrame }) {
            screenFrame = nsScreen.visibleFrame
        } else {
            screenFrame = NSScreen.main?.visibleFrame ?? converter.appKitDesktopFrame
        }

        let size = tipWindow.frame.size
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + 20
        )

        tipWindow.setFrame(CGRect(origin: origin, size: size), display: false)
        tipWindow.alphaValue = 1.0
        tipWindow.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self?.window?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.window?.orderOut(nil)
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true

        let tipWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 280, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tipWindow.isOpaque = false
        tipWindow.backgroundColor = .clear
        tipWindow.ignoresMouseEvents = true
        tipWindow.level = .screenSaver
        tipWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        tipWindow.hasShadow = true
        tipWindow.alphaValue = 0

        let container = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 64))

        // Background pill
        let bg = NSVisualEffectView(frame: container.bounds)
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        container.addSubview(bg)

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.frame = CGRect(x: 16, y: 32, width: 248, height: 22)
        title.lineBreakMode = .byTruncatingTail
        container.addSubview(title)

        let detail = NSTextField(labelWithString: "")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.frame = CGRect(x: 16, y: 10, width: 248, height: 18)
        detail.lineBreakMode = .byTruncatingTail
        container.addSubview(detail)

        tipWindow.contentView = container
        window = tipWindow
        titleLabel = title
        detailLabel = detail
    }
}
