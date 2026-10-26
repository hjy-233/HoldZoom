//
//  ZoomCanvas+AnnotationState.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/26.
//

import AppKit

extension ZoomCanvas {
    func enterAnnotationMode() {
        guard !annotationMode else { return }
        annotationMode = true
        currentAnnotationPoints = nil
        annotationToolPicker?.isHidden = false
        needsDisplay = true
    }

    func exitAnnotationMode() {
        guard annotationMode else { return }
        annotationMode = false
        annotationToolDetailsPopover?.close()
        annotationToolDetailsPopover = nil
        annotationToolDetailsTool = nil
        annotationToolDetailsStateDidChange?(false)
        currentAnnotationPoints = nil
        annotationToolPicker?.isHidden = true
        needsDisplay = true
    }

    func beginAnnotation(at location: NSPoint) {
        guard annotationMode else { return }
        currentAnnotationTool = selectedAnnotationTool
        hasRecordedEraserGesture = false
        currentAnnotationPoints = [annotationPoint(at: location)]
        if currentAnnotationTool == .eraser {
            eraseAnnotations(from: location, to: location)
        }
        needsDisplay = true
    }

    func continueAnnotation(at location: NSPoint) {
        guard annotationMode,
              currentAnnotationPoints != nil
        else { return }
        let previousLocation = currentAnnotationPoints?.last.map(viewPoint(for:)) ?? location
        currentAnnotationPoints?.append(annotationPoint(at: location))
        if currentAnnotationTool == .eraser {
            eraseAnnotations(from: previousLocation, to: location)
        }
        needsDisplay = true
    }

    func endAnnotation() {
        guard let points = currentAnnotationPoints else { return }
        currentAnnotationPoints = nil
        if !points.isEmpty, currentAnnotationTool != .eraser {
            recordAnnotationUndoState()
            annotationStrokes.append(
                AnnotationStroke(
                    points: points,
                    tool: currentAnnotationTool,
                    color: annotationColor,
                    lineWidth: annotationLineWidth,
                    isFilled: annotationFillShapes
                )
            )
        }
        hasRecordedEraserGesture = false
        needsDisplay = true
    }

    func undoAnnotation() {
        guard let previous = annotationUndoHistory.popLast() else { return }
        annotationRedoHistory.append(annotationStrokes)
        annotationStrokes = previous
        updateAnnotationHistoryButtons()
        needsDisplay = true
    }

    func redoAnnotation() {
        guard let next = annotationRedoHistory.popLast() else { return }
        annotationUndoHistory.append(annotationStrokes)
        annotationStrokes = next
        updateAnnotationHistoryButtons()
        needsDisplay = true
    }

    func clearAnnotations() {
        guard !annotationStrokes.isEmpty || currentAnnotationPoints != nil else { return }
        if !annotationStrokes.isEmpty {
            recordAnnotationUndoState()
        }
        annotationStrokes.removeAll()
        currentAnnotationPoints = nil
        hasRecordedEraserGesture = false
        updateAnnotationHistoryButtons()
        needsDisplay = true
    }

    func replaceAnnotations(with strokes: [AnnotationStroke]) {
        guard annotationStrokes != strokes else { return }
        recordAnnotationUndoState()
        annotationStrokes = strokes
        currentAnnotationPoints = nil
        updateAnnotationHistoryButtons()
        needsDisplay = true
    }

    func recordAnnotationUndoState() {
        if annotationUndoHistory.count == 50 {
            annotationUndoHistory.removeFirst()
        }
        annotationUndoHistory.append(annotationStrokes)
        annotationRedoHistory.removeAll()
        updateAnnotationHistoryButtons()
    }

    func updateAnnotationHistoryButtons() {
        annotationUndoButton?.isEnabled = !annotationUndoHistory.isEmpty
        annotationRedoButton?.isEnabled = !annotationRedoHistory.isEmpty
    }

    @objc func undoAnnotationFromToolbar() {
        undoAnnotation()
    }

    @objc func redoAnnotationFromToolbar() {
        redoAnnotation()
    }
}
