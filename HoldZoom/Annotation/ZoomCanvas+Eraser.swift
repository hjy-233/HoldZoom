//
//  ZoomCanvas+Eraser.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/26.
//

import AppKit

extension ZoomCanvas {
    var annotationEraserRadius: CGFloat {
        max(annotationEraserSize / 2, 1)
    }

    func eraseAnnotations(from start: NSPoint, to end: NSPoint) {
        var updatedStrokes: [AnnotationStroke] = []
        var didErase = false

        for stroke in annotationStrokes {
            let polylines = annotationPolylines(points: stroke.points, tool: stroke.tool)
            if annotationEraserMode == .wholeStroke {
                let didHitStroke = polylines.contains { polyline in
                    erase(polyline, from: start, to: end, radius: annotationEraserRadius).didErase
                }
                if didHitStroke {
                    didErase = true
                } else {
                    updatedStrokes.append(stroke)
                }
                continue
            }

            var strokeWasErased = false
            var fragments: [AnnotationStroke] = []

            for polyline in polylines {
                let result = erase(
                    polyline,
                    from: start,
                    to: end,
                    radius: annotationEraserRadius
                )
                strokeWasErased = strokeWasErased || result.didErase
                fragments += result.remaining.map { points in
                    AnnotationStroke(
                        points: points.map(annotationPoint(at:)),
                        tool: .pen,
                        color: stroke.color,
                        lineWidth: stroke.lineWidth
                    )
                }
            }

            if strokeWasErased {
                didErase = true
                updatedStrokes += fragments
            } else {
                updatedStrokes.append(stroke)
            }
        }

        guard didErase else { return }
        if !hasRecordedEraserGesture {
            recordAnnotationUndoState()
            hasRecordedEraserGesture = true
        }
        annotationStrokes = updatedStrokes
        needsDisplay = true
    }

    private func erase(
        _ polyline: [NSPoint],
        from eraserStart: NSPoint,
        to eraserEnd: NSPoint,
        radius: CGFloat
    ) -> (remaining: [[NSPoint]], didErase: Bool) {
        guard let first = polyline.first else { return ([], false) }
        let radiusSquared = radius * radius
        if polyline.count == 1 {
            let hit = squaredDistance(from: first, to: eraserStart, end: eraserEnd) <= radiusSquared
            return (hit ? [] : [polyline], hit)
        }

        var remaining: [[NSPoint]] = []
        var current: [NSPoint] = []
        var didErase = false
        for (start, end) in zip(polyline, polyline.dropFirst()) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            let steps = max(1, Int(ceil(distance / 2)))
            for step in 0 ... steps {
                if !current.isEmpty, step == 0 {
                    continue
                }
                let fraction = CGFloat(step) / CGFloat(steps)
                let point = NSPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction
                )
                let hit = squaredDistance(from: point, to: eraserStart, end: eraserEnd) <= radiusSquared
                if hit {
                    didErase = true
                    if !current.isEmpty {
                        remaining.append(current)
                        current = []
                    }
                } else if current.last != point {
                    current.append(point)
                }
            }
        }
        if !current.isEmpty {
            remaining.append(current)
        }
        return (didErase ? remaining : [polyline], didErase)
    }

    private func squaredDistance(from point: NSPoint, to start: NSPoint, end: NSPoint) -> CGFloat {
        let delta = NSPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared > 0 else {
            return squaredDistance(point, start)
        }
        let projection = ((point.x - start.x) * delta.x + (point.y - start.y) * delta.y) / lengthSquared
        let fraction = min(max(projection, 0), 1)
        let nearest = NSPoint(x: start.x + fraction * delta.x, y: start.y + fraction * delta.y)
        return squaredDistance(point, nearest)
    }

    private func squaredDistance(_ first: NSPoint, _ second: NSPoint) -> CGFloat {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }
}
