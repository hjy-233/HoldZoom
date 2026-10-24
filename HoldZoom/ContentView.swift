//
//  ContentView.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import SwiftUI

struct ContentView: View {
    @State private var overlay = ZoomOverlayController()
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Button("测试全屏覆盖") {
                Task {
                    do {
                        let image = try await ScreenCapture.capture()
                        overlay.show(image: image)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
