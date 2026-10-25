//
//  HoldZoomSettings.swift
//  HoldZoom
//
//  Created by Codex on 2026/10/24.
//

import AppKit
import Foundation

struct HoldZoomSettings: Codable {
    var shortcuts: Shortcuts
    var zoom: Zoom
    var flashlight: Flashlight
    var keyboardPan: KeyboardPan

    static let `default` = HoldZoomSettings(
        shortcuts: Shortcuts(
            flashlight: KeyBinding(key: "r", modifiers: [.command]),
            zoom: .control,
            captureWhileHeld: .control,
            captureDelay: 0.25,
            exitOverlay: KeyBinding(key: "escape", modifiers: []),
            panUp: ["w", "up"],
            panLeft: ["a", "left"],
            panDown: ["s", "down"],
            panRight: ["d", "right"],
            panModifiers: []
        ),
        zoom: Zoom(
            minimum: 1,
            maximum: 8,
            preciseScrollSensitivity: 0.015,
            scrollSensitivity: 0.20
        ),
        flashlight: Flashlight(radius: 100, dimOpacity: 0.82),
        keyboardPan: KeyboardPan(
            initialSpeed: 180,
            maximumSpeed: 2200,
            accelerationDuration: 0.3,
            maximumFrameDelta: 0.05,
            frameInterval: 1.0 / 60.0,
            accelerationResponse: 24,
            decelerationResponse: 10,
            stopSpeed: 5
        )
    )

    struct Shortcuts: Codable {
        var flashlight: KeyBinding
        var zoom: ModifierKey
        var captureWhileHeld: ModifierKey
        var captureDelay: TimeInterval?
        var exitOverlay: KeyBinding
        var panUp: [String]
        var panLeft: [String]
        var panDown: [String]
        var panRight: [String]
        var panModifiers: [ModifierKey]

        func panDirection(for event: NSEvent) -> NSPoint? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let actualModifiers = Set(ModifierKey.allCases.filter { flags.contains($0.eventFlag) })
                .subtracting(Set([captureWhileHeld]))
            let expectedModifiers = Set(panModifiers).subtracting(Set([captureWhileHeld]))
            guard actualModifiers == expectedModifiers else { return nil }

            if panUp.contains(where: { KeyBinding.keyCode(for: $0) == event.keyCode }) {
                return NSPoint(x: 0, y: -1)
            } else if panLeft.contains(where: { KeyBinding.keyCode(for: $0) == event.keyCode }) {
                return NSPoint(x: 1, y: 0)
            } else if panDown.contains(where: { KeyBinding.keyCode(for: $0) == event.keyCode }) {
                return NSPoint(x: 0, y: 1)
            } else if panRight.contains(where: { KeyBinding.keyCode(for: $0) == event.keyCode }) {
                return NSPoint(x: -1, y: 0)
            } else {
                return nil
            }
        }
    }

    struct KeyBinding: Codable {
        private static let keyCodes: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
            "grave": 50, "delete": 51, "escape": 53, "left": 123, "right": 124,
            "down": 125, "up": 126
        ]

        var key: String
        var modifiers: [ModifierKey]

        func matches(_ event: NSEvent) -> Bool {
            guard Self.keyCode(for: key) == event.keyCode else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let actualModifiers = ModifierKey.allCases.filter { flags.contains($0.eventFlag) }
            return Set(actualModifiers) == Set(modifiers)
        }

        static func keyCode(for key: String) -> UInt16? {
            keyCodes[key.lowercased()]
        }
    }

    enum ModifierKey: String, Codable, CaseIterable, Hashable {
        case command
        case control
        case option
        case shift

        var eventFlag: NSEvent.ModifierFlags {
            switch self {
            case .command: .command
            case .control: .control
            case .option: .option
            case .shift: .shift
            }
        }

        var eventSourceFlag: CGEventFlags {
            switch self {
            case .command: .maskCommand
            case .control: .maskControl
            case .option: .maskAlternate
            case .shift: .maskShift
            }
        }
    }

    struct Zoom: Codable {
        var minimum: CGFloat
        var maximum: CGFloat
        var preciseScrollSensitivity: Double
        var scrollSensitivity: Double
    }

    struct Flashlight: Codable {
        var radius: CGFloat
        var dimOpacity: CGFloat
    }

    struct KeyboardPan: Codable {
        var initialSpeed: CGFloat
        var maximumSpeed: CGFloat
        var accelerationDuration: TimeInterval
        var maximumFrameDelta: TimeInterval
        var frameInterval: TimeInterval
        var accelerationResponse: Double
        var decelerationResponse: Double
        var stopSpeed: CGFloat
    }

    private var isValid: Bool {
        let validZoom = zoom.minimum.isFinite
            && zoom.maximum.isFinite
            && zoom.minimum >= 1
            && zoom.maximum >= zoom.minimum
            && zoom.preciseScrollSensitivity.isFinite
            && zoom.preciseScrollSensitivity >= 0
            && zoom.scrollSensitivity.isFinite
            && zoom.scrollSensitivity >= 0
        let validFlashlight = flashlight.radius.isFinite
            && flashlight.radius >= 0
            && flashlight.dimOpacity.isFinite
            && (0 ... 1).contains(flashlight.dimOpacity)
        let validPan = keyboardPan.initialSpeed.isFinite
            && keyboardPan.maximumSpeed.isFinite
            && keyboardPan.initialSpeed >= 0
            && keyboardPan.maximumSpeed >= keyboardPan.initialSpeed
            && keyboardPan.accelerationDuration.isFinite
            && keyboardPan.accelerationDuration > 0
            && keyboardPan.maximumFrameDelta.isFinite
            && keyboardPan.maximumFrameDelta > 0
            && keyboardPan.frameInterval.isFinite
            && keyboardPan.frameInterval > 0
            && keyboardPan.accelerationResponse.isFinite
            && keyboardPan.accelerationResponse > 0
            && keyboardPan.decelerationResponse.isFinite
            && keyboardPan.decelerationResponse > 0
            && keyboardPan.stopSpeed.isFinite
            && keyboardPan.stopSpeed >= 0
        let validShortcuts = KeyBinding.keyCode(for: shortcuts.flashlight.key) != nil
            && KeyBinding.keyCode(for: shortcuts.exitOverlay.key) != nil
            && (shortcuts.captureDelay.map { $0.isFinite && (0 ... 2).contains($0) } ?? true)
            && [shortcuts.panUp, shortcuts.panLeft, shortcuts.panDown, shortcuts.panRight]
            .allSatisfy { !$0.isEmpty && $0.allSatisfy { KeyBinding.keyCode(for: $0) != nil } }

        return validZoom && validFlashlight && validPan && validShortcuts
    }

    static func load() -> HoldZoomSettings {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/holdzoom.json")

        do {
            let data = try Data(contentsOf: configURL)
            let settings = try JSONDecoder().decode(HoldZoomSettings.self, from: data)
            guard settings.isValid else {
                NSLog("HoldZoom settings contain invalid values; using defaults")
                return .default
            }
            return settings
        } catch {
            guard !FileManager.default.fileExists(atPath: configURL.path) else {
                NSLog("HoldZoom could not read settings: %@", error.localizedDescription)
                return .default
            }

            do {
                try FileManager.default.createDirectory(
                    at: configURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(HoldZoomSettings.default)
                try data.write(to: configURL, options: .atomic)
            } catch {
                NSLog("HoldZoom could not create settings: %@", error.localizedDescription)
            }
            return .default
        }
    }
}
