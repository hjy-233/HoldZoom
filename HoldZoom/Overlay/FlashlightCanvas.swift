//
//  FlashlightCanvas.swift
//  HoldZoom
//
//  Created by Codex on 2026/10/24.
//

import AppKit

final class FlashlightCanvas: NSView {
    private let settings: HoldZoomSettings
    private var spotlightCenter: NSPoint?
    private var animationStart: TimeInterval?
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0
    private var animationProgress: CGFloat = 0
    private var animationCompletion: (() -> Void)?
    private var animationTimer: Timer?
    private var lastUpdate: TimeInterval?
    private var cursorIsHidden = false

    init(frame: NSRect, settings: HoldZoomSettings) {
        self.settings = settings
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder _: NSCoder) {
        return nil
    }

    override var isOpaque: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        setCursorHidden(true)
        spotlightCenter = currentMouseLocation()
        animate(to: 1)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            animationTimer?.invalidate()
            animationTimer = nil
            animationCompletion = nil
            setCursorHidden(false)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        guard animationProgress > 0 else { return }

        let center = spotlightCenter ?? NSPoint(x: bounds.midX, y: bounds.midY)
        context.setBlendMode(.normal)
        context.setFillColor(
            NSColor.black.withAlphaComponent(
                settings.flashlight.dimOpacity * animationProgress
            ).cgColor
        )
        context.fill(bounds)

        let maximumRadius = hypot(bounds.width, bounds.height)
        let radius = maximumRadius
            + (settings.flashlight.radius - maximumRadius) * animationProgress

        let colors = [
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 0)
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceGray(),
            colors: colors,
            locations: [0, 0.68, 1]
        ) else { return }

        context.setBlendMode(.destinationOut)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
        context.setBlendMode(.normal)
    }

    func dismiss(completion: @escaping () -> Void) {
        animationCompletion = completion
        animate(to: 0)
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard cursorIsHidden != hidden else { return }
        cursorIsHidden = hidden
        if hidden {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
    }

    private func animate(to target: CGFloat) {
        animationFrom = animationProgress
        animationTo = target
        animationStart = ProcessInfo.processInfo.systemUptime
        guard animationTimer == nil else { return }

        lastUpdate = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateAnimation()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateAnimation() {
        let now = ProcessInfo.processInfo.systemUptime
        let previousUpdate = lastUpdate ?? now
        let deltaTime = min(now - previousUpdate, 0.05)
        lastUpdate = now

        if let animationStart {
            let progress = min((now - animationStart) / 0.2, 1)
            let easedProgress = 1 - pow(1 - progress, 3)
            animationProgress = animationFrom + (animationTo - animationFrom) * easedProgress
            if progress >= 1 {
                animationProgress = animationTo
                self.animationStart = nil
                if animationTo == 0 {
                    finishDismissal()
                    return
                }
            }
        }

        let target = currentMouseLocation()
        let center = spotlightCenter ?? target
        let blend = 1 - exp(-22 * deltaTime)
        let nextCenter = NSPoint(
            x: center.x + (target.x - center.x) * blend,
            y: center.y + (target.y - center.y) * blend
        )
        spotlightCenter = hypot(target.x - nextCenter.x, target.y - nextCenter.y) > 0.25
            ? nextCenter
            : target
        needsDisplay = true
    }

    private func finishDismissal() {
        animationTimer?.invalidate()
        animationTimer = nil
        lastUpdate = nil
        setCursorHidden(false)
        needsDisplay = true
        let completion = animationCompletion
        animationCompletion = nil
        completion?()
    }

    private func currentMouseLocation() -> NSPoint {
        guard let window else { return NSPoint(x: bounds.midX, y: bounds.midY) }
        let locationInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let location = convert(locationInWindow, from: nil)
        return NSPoint(
            x: min(max(location.x, bounds.minX), bounds.maxX),
            y: min(max(location.y, bounds.minY), bounds.maxY)
        )
    }
}
