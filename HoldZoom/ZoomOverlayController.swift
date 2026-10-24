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
    private var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var escapeMonitor: Any?
    private var localKeyboardMonitor: Any?
    private var localControlMonitor: Any?
    private var globalKeyboardMonitor: Any?
    private var globalControlMonitor: Any?
    private var controlCaptureTask: Task<Void, Never>?
    private var flashlightCaptureTask: Task<Void, Never>?
    private var isControlPressed = false
    private var isHeldOverlay = false
    private var isCommandRFlashlightOverlay = false

    init() {
        requestAccessibilityPermission()
        installCommandRMonitors()
        installControlMonitors()
    }

    func show(image: NSImage) throws {
        flashlightCaptureTask?.cancel()
        flashlightCaptureTask = nil
        isCommandRFlashlightOverlay = false
        closeOverlay()
        isHeldOverlay = false
        try display(image: image)
    }

    private func showWhileControlIsHeld(image: NSImage) throws {
        isCommandRFlashlightOverlay = false
        closeOverlay()
        isHeldOverlay = true
        try display(image: image)
    }

    private func display(image: NSImage, flashlightEnabled: Bool = false) throws {
        guard let screen = NSScreen.main else {
            throw OverlayError.noScreen
        }

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

        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let canvas = ZoomCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image,
            flashlightEnabled: flashlightEnabled
        )
        window.contentView = canvas

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(canvas) else {
            closeOverlay()
            throw OverlayError.firstResponderUnavailable
        }

        installEscapeMonitor()
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { [weak self] in
                    self?.close()
                }
                return nil
            }

            return event
        }
    }

    private func installCommandRMonitors() {
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard Self.isCommandR(event) else { return event }
            DispatchQueue.main.async { [weak self] in
                self?.toggleCommandRFlashlight()
            }
            return nil
        }

        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard Self.isCommandR(event) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.toggleCommandRFlashlight()
            }
        }
    }

    private static func isCommandR(_ event: NSEvent) -> Bool {
        event.keyCode == 15 && event.modifierFlags.contains(.command)
    }

    private func toggleCommandRFlashlight() {
        if isCommandRFlashlightOverlay {
            isCommandRFlashlightOverlay = false
            flashlightCaptureTask?.cancel()
            flashlightCaptureTask = nil
            closeOverlay()
            return
        }

        if let canvas = window?.contentView as? ZoomCanvas {
            canvas.toggleFlashlight()
            return
        }

        isCommandRFlashlightOverlay = true
        flashlightCaptureTask = Task { [weak self] in
            await self?.showFlashlightOverlay()
        }
    }

    private func showFlashlightOverlay() async {
        do {
            let image = try await ScreenCapture.capture()
            guard isCommandRFlashlightOverlay,
                  !Task.isCancelled,
                  window == nil
            else { return }
            try display(image: image, flashlightEnabled: true)
        } catch {
            isCommandRFlashlightOverlay = false
            guard !Task.isCancelled else { return }
            NSLog("HoldZoom failed to show flashlight: %@", error.localizedDescription)
            NSAlert(error: error).runModal()
        }
        flashlightCaptureTask = nil
    }

    private func installControlMonitors() {
        localControlMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            let isPressed = event.modifierFlags.contains(.control)
            DispatchQueue.main.async { [weak self] in
                self?.setControlPressed(isPressed)
            }
            return event
        }

        globalControlMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            let isPressed = event.modifierFlags.contains(.control)
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
        flashlightCaptureTask?.cancel()
        flashlightCaptureTask = nil
        isHeldOverlay = false
        isCommandRFlashlightOverlay = false
        closeOverlay()
    }

    private func closeOverlay() {
        guard window != nil else { return }

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }

        window?.close()
        window = nil
        isCommandRFlashlightOverlay = false

        if let previousApplication {
            self.previousApplication = nil
            previousApplication.activate(options: [])
        }
    }
}
