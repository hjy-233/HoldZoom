//
//  OverlayInputTap.swift
//  HoldZoom
//

import AppKit
import CoreGraphics

final class OverlayInputTap {
    private let panKeyCodes: Set<UInt16>
    private let panModifiers: Set<HoldZoomSettings.ModifierKey>
    private let exitKeyCode: UInt16?
    private let exitModifiers: Set<HoldZoomSettings.ModifierKey>
    private let captureModifier: HoldZoomSettings.ModifierKey
    private let overlayWindowNumber: Int
    private let handler: (NSEvent, NSPoint) -> Void
    private var capturedMouseButtons = Set<CGEventType>()
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        panKeyCodes: Set<UInt16>,
        panModifiers: Set<HoldZoomSettings.ModifierKey>,
        exitShortcut: HoldZoomSettings.KeyBinding,
        captureModifier: HoldZoomSettings.ModifierKey,
        overlayWindowNumber: Int,
        handler: @escaping (NSEvent, NSPoint) -> Void
    ) {
        self.panKeyCodes = panKeyCodes
        self.panModifiers = panModifiers
        exitKeyCode = HoldZoomSettings.KeyBinding.keyCode(for: exitShortcut.key)
        exitModifiers = Set(exitShortcut.modifiers)
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
        if type == .scrollWheel {
            return true
        }
        let windowUnderPointer = Int(
            event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        )
        switch type {
        case .leftMouseDown, .rightMouseDown:
            guard windowUnderPointer == overlayWindowNumber else { return false }
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
        let actualModifiers = Set(
            HoldZoomSettings.ModifierKey.allCases.filter { event.flags.contains($0.eventSourceFlag) }
        ).subtracting([captureModifier])
        let expectedPanModifiers = panModifiers.subtracting([captureModifier])
        let expectedExitModifiers = exitModifiers.subtracting([captureModifier])
        let isPanKey = panKeyCodes.contains(keyCode) && actualModifiers == expectedPanModifiers
        let isExitKey = keyCode == exitKeyCode && actualModifiers == expectedExitModifiers
        return isPanKey || isExitKey
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
