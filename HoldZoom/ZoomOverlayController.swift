//
//  ZoomOverlayController.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import AppKit
import ApplicationServices

private final class ZoomOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

private enum OverlayError: LocalizedError {
    case noScreen
    case inputTapUnavailable

    var errorDescription: String? {
        switch self {
        case .noScreen:
            String(localized: "无法找到屏幕")
        case .inputTapUnavailable:
            String(localized: "请在系统设置中允许 HoldZoom 使用辅助功能")
        }
    }
}

@MainActor
final class ZoomOverlayController {
    private let settings = HoldZoomSettings.load()
    private var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var overlayInputTap: OverlayInputTap?
    private var localKeyboardMonitor: Any?
    private var localControlMonitor: Any?
    private var globalKeyboardMonitor: Any?
    private var globalControlMonitor: Any?
    private var controlCaptureTask: Task<Void, Never>?
    private var controlStateTimer: Timer?
    private var isControlPressed = false
    private var isHeldOverlay = false
    private var isShortcutFlashlightOverlay = false
    private var hasPresentedCaptureError = false

    init() {
        requestAccessibilityPermission()
        requestScreenCapturePermission()
        installShortcutMonitors()
        installControlMonitors()
        startControlStatePolling()
    }

    func show(image: NSImage) throws {
        isShortcutFlashlightOverlay = false
        closeOverlay()
        isHeldOverlay = false
        try display(image: image)
    }

    private func showWhileControlIsHeld(image: NSImage) throws {
        isShortcutFlashlightOverlay = false
        closeOverlay()
        isHeldOverlay = true
        try display(image: image)
    }

    private func display(image: NSImage) throws {
        guard let screen = NSScreen.main else {
            throw OverlayError.noScreen
        }

        let canvas = ZoomCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image,
            settings: settings
        )
        try display(canvas, on: screen, ignoresMouseEvents: false)
    }

    private func displayFlashlight() throws {
        guard let screen = NSScreen.main else {
            throw OverlayError.noScreen
        }

        let canvas = FlashlightCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            settings: settings
        )
        try display(canvas, on: screen, ignoresMouseEvents: true)
    }

    private func display(
        _ contentView: NSView,
        on screen: NSScreen,
        ignoresMouseEvents: Bool
    ) throws {
        previousApplication = NSWorkspace.shared.frontmostApplication

        let window = ZoomOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        // Keep status menus above the overlay.
        window.level = .mainMenu
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        window.backgroundColor = ignoresMouseEvents ? .clear : .black
        window.isOpaque = !ignoresMouseEvents
        window.hasShadow = false
        window.ignoresMouseEvents = ignoresMouseEvents
        window.acceptsMouseMovedEvents = true
        window.contentView = contentView

        self.window = window

        if ignoresMouseEvents {
            window.orderFrontRegardless()
        } else {
            window.orderFrontRegardless()
            if let canvas = contentView as? ZoomCanvas {
                guard installInputTap(for: canvas) else {
                    closeOverlay()
                    throw OverlayError.inputTapUnavailable
                }
            }
        }
    }

    private func installShortcutMonitors() {
        let shortcut = settings.shortcuts.flashlight
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard shortcut.matches(event) else { return event }
            DispatchQueue.main.async { [weak self] in
                self?.toggleShortcutFlashlight()
            }
            return nil
        }

        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard shortcut.matches(event) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.toggleShortcutFlashlight()
            }
        }
    }

    private func toggleShortcutFlashlight() {
        if isShortcutFlashlightOverlay {
            isShortcutFlashlightOverlay = false
            closeFlashlightOverlay()
            return
        }

        controlCaptureTask?.cancel()
        controlCaptureTask = nil
        isHeldOverlay = false
        closeOverlay()
        isShortcutFlashlightOverlay = true
        do {
            try displayFlashlight()
        } catch {
            isShortcutFlashlightOverlay = false
            NSLog("HoldZoom failed to show flashlight: %@", error.localizedDescription)
            NSAlert(error: error).runModal()
        }
    }

    func toggleFlashlight() {
        toggleShortcutFlashlight()
    }

    private func closeFlashlightOverlay() {
        guard let flashlightWindow = window,
              let canvas = flashlightWindow.contentView as? FlashlightCanvas
        else {
            closeOverlay()
            return
        }

        canvas.dismiss { [weak self, weak flashlightWindow] in
            guard let self,
                  let flashlightWindow,
                  self.window === flashlightWindow
            else { return }
            self.closeOverlay()
        }
    }

    private func installControlMonitors() {
        let captureModifier = settings.shortcuts.captureWhileHeld.eventFlag
        localControlMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            let isPressed = event.modifierFlags.contains(captureModifier)
            DispatchQueue.main.async { [weak self] in
                self?.setControlPressed(isPressed)
            }
            return event
        }

        globalControlMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            let isPressed = event.modifierFlags.contains(captureModifier)
            DispatchQueue.main.async { [weak self] in
                self?.setControlPressed(isPressed)
            }
        }
    }

    private func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestScreenCapturePermission() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    private func setControlPressed(_ isPressed: Bool) {
        guard isControlPressed != isPressed else { return }
        isControlPressed = isPressed

        if isPressed {
            startControlStatePolling()
            guard window == nil else { return }
            controlCaptureTask = Task { [weak self] in
                await self?.showCapturedImageWhileControlIsHeld()
            }
        } else {
            controlCaptureTask?.cancel()
            controlCaptureTask = nil
            if isHeldOverlay {
                closeOverlay()
                isHeldOverlay = false
            }
        }
    }

    func close() {
        controlCaptureTask?.cancel()
        controlCaptureTask = nil
        isHeldOverlay = false
        isShortcutFlashlightOverlay = false
        closeOverlay()
    }

    private func dismissOverlay() {
        guard isShortcutFlashlightOverlay else {
            closeOverlay()
            return
        }

        isShortcutFlashlightOverlay = false
        closeFlashlightOverlay()
    }

    private func closeOverlay() {
        overlayInputTap?.invalidate()
        overlayInputTap = nil
        guard window != nil else {
            return
        }

        window?.close()
        window = nil
        isShortcutFlashlightOverlay = false

        let shouldRestorePreviousApplication = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == Bundle.main.bundleIdentifier
        if let previousApplication {
            self.previousApplication = nil
            if shouldRestorePreviousApplication {
                previousApplication.activate(options: [])
            }
        }
    }
}

private extension ZoomOverlayController {
    func startControlStatePolling() {
        guard controlStateTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let captureModifier = self.settings.shortcuts.captureWhileHeld.eventSourceFlag
            let isPressed = CGEventSource.flagsState(.combinedSessionState).contains(captureModifier)
            DispatchQueue.main.async { [weak self] in
                self?.setControlPressed(isPressed)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        controlStateTimer = timer
    }

    func installInputTap(for canvas: ZoomCanvas) -> Bool {
        let panKeys = settings.shortcuts.panUp
            + settings.shortcuts.panLeft
            + settings.shortcuts.panDown
            + settings.shortcuts.panRight
        let keyCodes = Set(panKeys.compactMap(HoldZoomSettings.KeyBinding.keyCode(for:)))
        guard let overlayWindowNumber = canvas.window?.windowNumber else { return false }
        let tap = OverlayInputTap(
            panKeyCodes: keyCodes,
            panModifiers: Set(settings.shortcuts.panModifiers),
            exitShortcut: settings.shortcuts.exitOverlay,
            captureModifier: settings.shortcuts.captureWhileHeld,
            overlayWindowNumber: overlayWindowNumber
        ) { [weak self, weak canvas] event, location in
            guard let self, let canvas else { return }
            handleOverlayInput(event, at: location, canvas: canvas)
        }
        guard tap.install() else { return false }
        overlayInputTap = tap
        return true
    }

    func handleOverlayInput(_ event: NSEvent, at location: NSPoint, canvas: ZoomCanvas) {
        guard let window = canvas.window else { return }
        let windowLocation = window.convertPoint(fromScreen: location)
        let mouse = canvas.convert(windowLocation, from: nil)

        if event.type == .scrollWheel {
            canvas.handleScroll(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                isPrecise: event.hasPreciseScrollingDeltas,
                controlPressed: event.modifierFlags.contains(settings.shortcuts.zoom.eventFlag),
                at: mouse
            )
            return
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            canvas.beginDragging(at: mouse)
        case .leftMouseDragged, .rightMouseDragged:
            canvas.continueDragging(at: mouse)
        case .leftMouseUp, .rightMouseUp:
            canvas.endDragging()
        case .keyDown where event.keyCode
            == (HoldZoomSettings.KeyBinding.keyCode(for: settings.shortcuts.exitOverlay.key) ?? .max):
            dismissOverlay()
        case .keyDown:
            canvas.keyDown(with: event)
        case .keyUp:
            canvas.keyUp(with: event)
        default:
            break
        }
    }

    func showCapturedImageWhileControlIsHeld() async {
        do {
            let delay = settings.shortcuts.captureDelay ?? 0.25
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }

            let image = try await ScreenCapture.capture()
            guard isControlPressed,
                  !Task.isCancelled,
                  window == nil
            else { return }
            try showWhileControlIsHeld(image: image)
        } catch is CancellationError {
            return
        } catch {
            NSLog("HoldZoom failed to show captured screen: %@", error.localizedDescription)
            guard !hasPresentedCaptureError else { return }
            hasPresentedCaptureError = true
            NSAlert(error: error).runModal()
        }
    }
}
