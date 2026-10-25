//
//  ZoomCanvas.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import AppKit

final class ZoomCanvas: NSView {
    private let image: NSImage
    private let settings: HoldZoomSettings
    private var zoom: CGFloat
    private var imageOrigin: NSPoint = .zero
    private var dragLocation: NSPoint?
    private var pressedKeyboardDirections: [UInt16: NSPoint] = [:]
    private var keyboardPanTimer: Timer?
    private var keyboardPanStartedAt: TimeInterval?
    private var keyboardPanLastUpdate: TimeInterval?
    private var keyboardPanVelocity: NSPoint = .zero

    init(
        frame: NSRect,
        image: NSImage,
        settings: HoldZoomSettings
    ) {
        self.image = image
        self.settings = settings
        zoom = settings.zoom.minimum
        super.init(frame: frame)
    }

    required init?(coder _: NSCoder) {
        return nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()

        let previousInterpolation = context.imageInterpolation
        context.imageInterpolation = .none
        defer { context.imageInterpolation = previousInterpolation }

        let imageRect = NSRect(
            x: imageOrigin.x,
            y: imageOrigin.y,
            width: bounds.width * zoom,
            height: bounds.height * zoom
        )

        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    override func scrollWheel(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        let controlPressed = event.modifierFlags.contains(settings.shortcuts.zoom.eventFlag)
        handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            controlPressed: controlPressed,
            at: mouse
        )
    }

    override func mouseDown(with event: NSEvent) {
        beginDragging(at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        beginDragging(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        continueDragging(at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDragged(with event: NSEvent) {
        continueDragging(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with _: NSEvent) {
        endDragging()
    }

    override func rightMouseUp(with _: NSEvent) {
        endDragging()
    }

    override func keyDown(with event: NSEvent) {
        guard let direction = settings.shortcuts.panDirection(for: event) else {
            super.keyDown(with: event)
            return
        }

        if pressedKeyboardDirections.isEmpty {
            keyboardPanStartedAt = ProcessInfo.processInfo.systemUptime
        }
        pressedKeyboardDirections[event.keyCode] = direction
        startKeyboardPanTimerIfNeeded()
    }

    override func keyUp(with event: NSEvent) {
        guard settings.shortcuts.panDirection(for: event) != nil else {
            super.keyUp(with: event)
            return
        }

        pressedKeyboardDirections[event.keyCode] = nil
        if pressedKeyboardDirections.isEmpty {
            keyboardPanStartedAt = nil
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            keyboardPanTimer?.invalidate()
            keyboardPanTimer = nil
            pressedKeyboardDirections.removeAll()
            keyboardPanVelocity = .zero
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func beginDragging(at location: NSPoint) {
        dragLocation = location
    }

    func continueDragging(at location: NSPoint) {
        guard let previousLocation = dragLocation else { return }

        moveImage(
            by: NSPoint(
                x: location.x - previousLocation.x,
                y: location.y - previousLocation.y
            )
        )
        dragLocation = location
    }

    func endDragging() {
        dragLocation = nil
    }

    private func moveImage(by distance: NSPoint) {
        imageOrigin.x += distance.x
        imageOrigin.y += distance.y
        clampImageOrigin()
        needsDisplay = true
    }

    func handleScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        isPrecise: Bool,
        controlPressed: Bool,
        at mouse: NSPoint
    ) {
        guard controlPressed else {
            imageOrigin.x += deltaX
            imageOrigin.y += deltaY
            clampImageOrigin()
            needsDisplay = true
            return
        }

        let sensitivity = isPrecise
            ? settings.zoom.preciseScrollSensitivity
            : settings.zoom.scrollSensitivity
        let factor = CGFloat(exp(Double(deltaY) * sensitivity))
        let newZoom = min(
            max(zoom * factor, settings.zoom.minimum),
            settings.zoom.maximum
        )
        guard newZoom != zoom else { return }

        let imageX = (mouse.x - imageOrigin.x) / zoom
        let imageY = (mouse.y - imageOrigin.y) / zoom

        zoom = newZoom
        imageOrigin.x = mouse.x - imageX * zoom
        imageOrigin.y = mouse.y - imageY * zoom
        clampImageOrigin()
        needsDisplay = true
    }

    private func clampImageOrigin() {
        imageOrigin.x = min(0, max(minimumImageOriginX, imageOrigin.x))
        imageOrigin.y = min(0, max(minimumImageOriginY, imageOrigin.y))
    }

    private var minimumImageOriginX: CGFloat {
        bounds.width * (1 - zoom)
    }

    private var minimumImageOriginY: CGFloat {
        bounds.height * (1 - zoom)
    }
}

private extension ZoomCanvas {
    func keyboardDirection(for keyCode: UInt16) -> NSPoint? {
        switch keyCode {
        case 13, 126:
            NSPoint(x: 0, y: -1)
        case 0, 123:
            NSPoint(x: 1, y: 0)
        case 1, 125:
            NSPoint(x: 0, y: 1)
        case 2, 124:
            NSPoint(x: -1, y: 0)
        default:
            nil
        }
    }

    func startKeyboardPanTimerIfNeeded() {
        guard keyboardPanTimer == nil else { return }
        keyboardPanLastUpdate = ProcessInfo.processInfo.systemUptime

        let timer = Timer(timeInterval: settings.keyboardPan.frameInterval, repeats: true) { [weak self] _ in
            self?.updateKeyboardPan()
        }
        keyboardPanTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateKeyboardPan() {
        let now = ProcessInfo.processInfo.systemUptime
        let previousUpdate = keyboardPanLastUpdate ?? now
        let deltaTime = min(now - previousUpdate, settings.keyboardPan.maximumFrameDelta)
        keyboardPanLastUpdate = now

        let direction = pressedKeyboardDirections.values.reduce(.zero) { result, value in
            NSPoint(x: result.x + value.x, y: result.y + value.y)
        }
        let directionLength = hypot(direction.x, direction.y)
        let hasDirection = directionLength > 0
        let targetVelocity = keyboardPanTargetVelocity(
            direction: direction,
            directionLength: directionLength,
            now: now
        )
        let response = hasDirection
            ? settings.keyboardPan.accelerationResponse
            : settings.keyboardPan.decelerationResponse
        let blend = 1 - exp(-response * deltaTime)
        keyboardPanVelocity.x += (targetVelocity.x - keyboardPanVelocity.x) * blend
        keyboardPanVelocity.y += (targetVelocity.y - keyboardPanVelocity.y) * blend

        if deltaTime > 0 {
            moveImage(
                by: NSPoint(
                    x: keyboardPanVelocity.x * deltaTime,
                    y: keyboardPanVelocity.y * deltaTime
                )
            )
        }

        let shouldStop = !hasDirection
            && hypot(keyboardPanVelocity.x, keyboardPanVelocity.y) < settings.keyboardPan.stopSpeed
        if shouldStop {
            keyboardPanTimer?.invalidate()
            keyboardPanTimer = nil
            keyboardPanLastUpdate = nil
            keyboardPanVelocity = .zero
        }
    }

    func keyboardPanTargetVelocity(
        direction: NSPoint,
        directionLength: CGFloat,
        now: TimeInterval
    ) -> NSPoint {
        guard directionLength > 0,
              let keyboardPanStartedAt
        else { return .zero }

        let elapsed = now - keyboardPanStartedAt
        let progress = min(elapsed / settings.keyboardPan.accelerationDuration, 1)
        let easedProgress = CGFloat(progress * progress)
        let speed = settings.keyboardPan.initialSpeed
            + (settings.keyboardPan.maximumSpeed - settings.keyboardPan.initialSpeed) * easedProgress

        return NSPoint(
            x: direction.x / directionLength * speed,
            y: direction.y / directionLength * speed
        )
    }
}
