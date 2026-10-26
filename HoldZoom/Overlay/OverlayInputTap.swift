//
//  OverlayInputTap.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/25.
//

import AppKit
import CoreGraphics

final class OverlayInputTap {
    private let panKeyCodes: Set<UInt16>
    private let panModifiers: Set<HoldZoomSettings.ModifierKey>
    private let exitKeyCode: UInt16?
    private let exitModifiers: Set<HoldZoomSettings.ModifierKey>
    private let annotationShortcuts: [HoldZoomSettings.KeyBinding]
    private let annotationEnterKeyCode: UInt16?
    private let captureModifier: HoldZoomSettings.ModifierKey
    private let overlayWindowNumber: Int
    private let handler: (NSEvent, NSPoint) -> Void
    private var capturedMouseButtons = Set<CGEventType>()
    private var capturedKeyboardKeys = Set<UInt16>()
    var annotationMode = false
    var annotationToolDetailsIsShown = false
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        panKeyCodes: Set<UInt16>,
        panModifiers: Set<HoldZoomSettings.ModifierKey>,
        exitShortcut: HoldZoomSettings.KeyBinding,
        annotationEnterShortcut: HoldZoomSettings.KeyBinding,
        annotationShortcuts: [HoldZoomSettings.KeyBinding],
        captureModifier: HoldZoomSettings.ModifierKey,
        overlayWindowNumber: Int,
        handler: @escaping (NSEvent, NSPoint) -> Void
    ) {
        self.panKeyCodes = panKeyCodes
        self.panModifiers = panModifiers
        exitKeyCode = HoldZoomSettings.KeyBinding.keyCode(for: exitShortcut.key)
        exitModifiers = Set(exitShortcut.modifiers)
        annotationEnterKeyCode = HoldZoomSettings.KeyBinding.keyCode(for: annotationEnterShortcut.key)
        self.annotationShortcuts = annotationShortcuts
        self.captureModifier = captureModifier
        self.overlayWindowNumber = overlayWindowNumber
        self.handler = handler
    }

    func install() -> Bool {
        let eventMask = [
            CGEventType.scrollWheel,
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp
        ]
        .reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: overlayInputTapCallback,
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        else {
            NSLog("HoldZoom could not install the overlay input tap")
            return false
        }

        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func invalidate() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        runLoopSource = nil
    }

    fileprivate func shouldHandle(
        _ event: CGEvent,
        type: CGEventType
    ) -> Bool {
        if shouldPassMouseEvent(type) {
            releaseCapturedMouseButton(for: type)
            return false
        }
        if type == .scrollWheel {
            return pointerIsOverOverlay(event)
        }
        switch type {
        case .leftMouseDown, .rightMouseDown:
            guard pointerIsOverOverlay(event) else { return false }
            capturedMouseButtons.insert(type == .leftMouseDown ? .leftMouseDragged : .rightMouseDragged)
            return true
        case .leftMouseDragged, .rightMouseDragged:
            return capturedMouseButtons.contains(type)
        case .leftMouseUp, .rightMouseUp:
            let dragType: CGEventType = type == .leftMouseUp ? .leftMouseDragged : .rightMouseDragged
            return capturedMouseButtons.remove(dragType) != nil
        default:
            break
        }
        guard type == .keyDown || type == .keyUp else { return false }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            return capturedKeyboardKeys.remove(keyCode) != nil
        }
        let actualModifiers = Set(
            HoldZoomSettings.ModifierKey.allCases.filter { event.flags.contains($0.eventSourceFlag) }
        ).subtracting([captureModifier])
        let expectedPanModifiers = panModifiers.subtracting([captureModifier])
        let expectedExitModifiers = exitModifiers.subtracting([captureModifier])
        let isPanKey = !annotationToolDetailsIsShown
            && panKeyCodes.contains(keyCode)
            && actualModifiers == expectedPanModifiers
        let isExitKey = keyCode == exitKeyCode && actualModifiers == expectedExitModifiers
        let isAnnotationActionShortcut = annotationMode
            && keyCode != annotationEnterKeyCode
            && matchesAnnotationShortcut(keyCode, modifiers: actualModifiers)
        let isAnnotationEntryShortcut = !annotationMode
            && keyCode == annotationEnterKeyCode
            && event.flags.contains(captureModifier.eventSourceFlag)
            && matchesAnnotationShortcut(keyCode, modifiers: actualModifiers)
        let shouldHandle = isPanKey || isExitKey || isAnnotationActionShortcut || isAnnotationEntryShortcut
        if shouldHandle {
            capturedKeyboardKeys.insert(keyCode)
        }
        return shouldHandle
    }

    private func isRightMouseEvent(_ type: CGEventType) -> Bool {
        switch type {
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            true
        default:
            false
        }
    }

    private func shouldPassMouseEvent(_ type: CGEventType) -> Bool {
        (annotationMode && isRightMouseEvent(type))
            || (annotationToolDetailsIsShown && shouldPassPointerEvent(type))
    }

    private func pointerIsOverOverlay(_ event: CGEvent) -> Bool {
        let windowUnderPointer = Int(
            event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        )
        return windowUnderPointer == overlayWindowNumber
    }

    private func shouldPassPointerEvent(_ type: CGEventType) -> Bool {
        switch type {
        case .scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            true
        default:
            false
        }
    }

    private func releaseCapturedMouseButton(for type: CGEventType) {
        switch type {
        case .leftMouseUp:
            capturedMouseButtons.remove(.leftMouseDragged)
        case .rightMouseUp:
            capturedMouseButtons.remove(.rightMouseDragged)
        default:
            break
        }
    }

    private func matchesAnnotationShortcut(
        _ keyCode: UInt16,
        modifiers: Set<HoldZoomSettings.ModifierKey>
    ) -> Bool {
        annotationShortcuts.contains { shortcut in
            HoldZoomSettings.KeyBinding.keyCode(for: shortcut.key) == keyCode
                && Set(shortcut.modifiers).subtracting([captureModifier]) == modifiers
        }
    }

    fileprivate func send(_ event: CGEvent, at location: NSPoint) {
        guard let nativeEvent = NSEvent(cgEvent: event) else { return }
        DispatchQueue.main.async { [handler] in
            handler(nativeEvent, location)
        }
    }
}

private func overlayInputTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let inputTap = Unmanaged<OverlayInputTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap = inputTap.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    let location = NSEvent.mouseLocation
    guard inputTap.shouldHandle(event, type: type) else {
        return Unmanaged.passUnretained(event)
    }

    inputTap.send(event, at: location)
    return nil
}
