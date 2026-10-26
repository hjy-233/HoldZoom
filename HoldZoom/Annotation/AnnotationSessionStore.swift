//
//  AnnotationSessionStore.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/25.
//

import AppKit
import CryptoKit
import Foundation

struct AnnotationPoint: Codable, Equatable {
    var normalizedX: Double
    var normalizedY: Double
}

struct AnnotationColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let red = AnnotationColor(red: 1, green: 0, blue: 0, alpha: 1)

    init(color: NSColor) {
        let convertedColor = color.usingColorSpace(.sRGB)
            ?? color.usingColorSpace(.deviceRGB)
            ?? .systemRed
        red = min(max(Double(convertedColor.redComponent), 0), 1)
        green = min(max(Double(convertedColor.greenComponent), 0), 1)
        blue = min(max(Double(convertedColor.blueComponent), 0), 1)
        alpha = min(max(Double(convertedColor.alphaComponent), 0), 1)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            alpha: min(max(alpha, 0), 1)
        )
    }
}

enum AnnotationEraserMode: String, Codable, CaseIterable {
    case partial
    case wholeStroke

    var label: String {
        switch self {
        case .partial: String(localized: "局部")
        case .wholeStroke: String(localized: "整笔")
        }
    }
}

enum AnnotationTool: String, CaseIterable, Codable, Equatable {
    case pen
    case circle
    case rectangle
    case line
    case arrow
    case eraser

    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .circle: "circle"
        case .rectangle: "rectangle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .eraser: "eraser"
        }
    }

    var label: String {
        switch self {
        case .pen: String(localized: "笔")
        case .circle: String(localized: "圈")
        case .rectangle: String(localized: "框")
        case .line: String(localized: "线")
        case .arrow: String(localized: "箭头")
        case .eraser: String(localized: "橡皮")
        }
    }
}

struct AnnotationStroke: Codable, Equatable {
    var points: [AnnotationPoint]
    var tool: AnnotationTool
    var color: AnnotationColor
    var lineWidth: Double
    var isFilled: Bool

    init(
        points: [AnnotationPoint],
        tool: AnnotationTool = .pen,
        color: AnnotationColor = .red,
        lineWidth: Double = 3,
        isFilled: Bool = false
    ) {
        self.points = points
        self.tool = tool
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case tool
        case color
        case lineWidth
        case isFilled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode([AnnotationPoint].self, forKey: .points)
        tool = try container.decodeIfPresent(AnnotationTool.self, forKey: .tool) ?? .pen
        color = try container.decodeIfPresent(AnnotationColor.self, forKey: .color) ?? .red
        lineWidth = try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 3
        isFilled = try container.decodeIfPresent(Bool.self, forKey: .isFilled) ?? false
    }
}

struct SavedAnnotationSession {
    let image: NSImage
    let imageFingerprint: String
    let strokes: [AnnotationStroke]
}

enum AnnotationSessionError: LocalizedError {
    case imageEncodingFailed
    case sessionNotFound
    case noMatchingImage
    case noCurrentOverlay

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            String(localized: "无法编码截图")
        case .sessionNotFound:
            String(localized: "没有已保存的会话")
        case .noMatchingImage:
            String(localized: "最近保存的标注不属于当前截图")
        case .noCurrentOverlay:
            String(localized: "请先打开截图覆盖层")
        }
    }
}

struct AnnotationSessionStore {
    private struct SessionMetadata: Codable {
        let imageFingerprint: String
        let strokes: [AnnotationStroke]
    }

    private struct LatestSessionReference: Codable {
        let id: UUID
    }

    private let fileManager = FileManager.default

    func save(image: NSImage, strokes: [AnnotationStroke]) throws {
        let imageData = try Self.pngData(for: image)
        let fingerprint = Self.fingerprint(for: imageData)
        let id = UUID()
        let sessionsURL = try sessionsDirectory()
        let sessionURL = sessionsURL.appending(path: id.uuidString)
        let temporaryURL = sessionsURL.appending(path: ".\(id.uuidString).tmp")

        do {
            try fileManager.createDirectory(
                at: temporaryURL,
                withIntermediateDirectories: false
            )
            try imageData.write(to: temporaryURL.appending(path: "image.png"), options: .atomic)
            let metadata = SessionMetadata(imageFingerprint: fingerprint, strokes: strokes)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: temporaryURL.appending(path: "session.json"), options: .atomic)
            try fileManager.moveItem(at: temporaryURL, to: sessionURL)

            let latestData = try encoder.encode(LatestSessionReference(id: id))
            try latestData.write(to: sessionsURL.appending(path: "latest.json"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    func loadLatest() throws -> SavedAnnotationSession {
        let sessionsURL = try sessionsDirectory()
        let referenceURL = sessionsURL.appending(path: "latest.json")
        guard fileManager.fileExists(atPath: referenceURL.path) else {
            throw AnnotationSessionError.sessionNotFound
        }
        let referenceData = try Data(contentsOf: referenceURL)
        let reference = try JSONDecoder().decode(LatestSessionReference.self, from: referenceData)
        let sessionURL = sessionsURL.appending(path: reference.id.uuidString)
        let imageData = try Data(contentsOf: sessionURL.appending(path: "image.png"))
        let metadataData = try Data(contentsOf: sessionURL.appending(path: "session.json"))
        let metadata = try JSONDecoder().decode(SessionMetadata.self, from: metadataData)
        guard let image = NSImage(data: imageData) else {
            throw AnnotationSessionError.imageEncodingFailed
        }
        return SavedAnnotationSession(
            image: image,
            imageFingerprint: metadata.imageFingerprint,
            strokes: metadata.strokes
        )
    }

    func latestAnnotations(matching image: NSImage) throws -> [AnnotationStroke] {
        let session = try loadLatest()
        let currentFingerprint = try Self.fingerprint(for: Self.pngData(for: image))
        guard session.imageFingerprint == currentFingerprint else {
            throw AnnotationSessionError.noMatchingImage
        }
        return session.strokes
    }

    private func sessionsDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let sessionsURL = appSupport.appending(path: "HoldZoom/Sessions")
        try fileManager.createDirectory(
            at: sessionsURL,
            withIntermediateDirectories: true
        )
        return sessionsURL
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw AnnotationSessionError.imageEncodingFailed
        }
        return pngData
    }

    private static func fingerprint(for imageData: Data) -> String {
        SHA256.hash(data: imageData)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
