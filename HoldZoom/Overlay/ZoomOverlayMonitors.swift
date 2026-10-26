//
//  ZoomOverlayMonitors.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/25.
//

import AppKit

@MainActor
extension ZoomOverlayController {
    func installShortcutMonitors() {
        let shortcut = settings.shortcuts.flashlight
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if shortcut.matches(event) {
                DispatchQueue.main.async { [weak self] in
                    self?.toggleShortcutFlashlight()
                }
                return nil
            }
            guard let self, self.isAnnotationEntryShortcut(event) else { return event }
            DispatchQueue.main.async { [weak self] in
                self?.beginAnnotationCaptureFromShortcut()
            }
            return nil
        }

        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if shortcut.matches(event) {
                DispatchQueue.main.async { [weak self] in
                    self?.toggleShortcutFlashlight()
                }
                return
            }
            guard let self, self.isAnnotationEntryShortcut(event) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.beginAnnotationCaptureFromShortcut()
            }
        }
    }

    func installControlMonitors() {
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
}
