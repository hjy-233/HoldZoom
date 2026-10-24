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
    case firstResponderUnavailable

    var errorDescription: String? {
        switch self {
        case .noScreen:
            String(localized: "无法找到屏幕")
        case .firstResponderUnavailable:
            String(localized: "无法接收键盘输入")
        }
    }
}

@MainActor
final class ZoomOverlayController {
    private let settings = HoldZoomSettings.load()
    private var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var escapeMonitor: Any?
    private var localKeyboardMonitor: Any?
    private var localControlMonitor: Any?
    private var globalKeyboardMonitor: Any?
    private var globalControlMonitor: Any?
    private var controlCaptureTask: Task<Void, Never>?
    private var isControlPressed = false
    private var isHeldOverlay = false
    private var isShortcutFlashlightOverlay = false

    init() {
        requestAccessibilityPermission()
        installShortcutMonitors()
        installControlMonitors()
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

        window.level = .screenSaver
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
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            guard window.makeFirstResponder(contentView) else {
                closeOverlay()
                throw OverlayError.firstResponderUnavailable
            }
            installEscapeMonitor()
        }
    }

    private func installEscapeMonitor() {
        let shortcut = settings.shortcuts.exitOverlay
        escapeMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if shortcut.matches(event) {
                DispatchQueue.main.async { [weak self] in
                    self?.dismissOverlay()
                }
                return nil
            }

            return event
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

    private func setControlPressed(_ isPressed: Bool) {
        guard isControlPressed != isPressed else { return }
        isControlPressed = isPressed

        if isPressed {
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

    private func showCapturedImageWhileControlIsHeld() async {
        do {
            let image = try await ScreenCapture.capture()
            guard isControlPressed,
                  !Task.isCancelled,
                  window == nil
            else { return }
            try showWhileControlIsHeld(image: image)
        } catch {
            NSLog("HoldZoom failed to show captured screen: %@", error.localizedDescription)
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
        guard window != nil else { return }

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
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
