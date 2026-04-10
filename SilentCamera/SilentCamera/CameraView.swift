import SwiftUI
import AVFoundation

/// Main camera screen — mirrors the native iPhone Camera UI.
struct CameraView: View {

    @StateObject private var camera = CameraManager()

    // Focus overlay state
    @State private var focusPoint: CGPoint = .zero
    @State private var showFocusIndicator: Bool = false

    // Shutter animation
    @State private var shutterFlash: Bool = false

    // Pinch-to-zoom
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0

    // Camera mode tabs
    private let modes = ["PHOTO", "VIDEO", "PORTRAIT", "PANO"]
    @State private var selectedMode: String = "PHOTO"

    // Capture animation
    @State private var captureScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // MARK: Live Preview
                if let layer = camera.previewLayer {
                    CameraPreviewView(previewLayer: layer) { tapPoint in
                        handleTap(at: tapPoint, in: geo.size)
                    }
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .updating($pinchScale) { value, state, _ in state = value }
                            .onChanged { value in
                                camera.changeZoomByPinch(scale: value / lastZoom)
                                lastZoom = value
                            }
                            .onEnded { _ in lastZoom = 1.0 }
                    )
                } else {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white)
                }

                // Shutter flash overlay
                if shutterFlash {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Focus indicator
                if showFocusIndicator {
                    FocusIndicatorView(position: focusPoint, isVisible: $showFocusIndicator)
                }

                // MARK: UI Overlay
                VStack(spacing: 0) {
                    topControlBar
                        .padding(.top, geo.safeAreaInsets.top + 8)

                    Spacer()

                    // Zoom selector
                    zoomSelector
                        .padding(.bottom, 20)

                    // Mode selector
                    modeSelectorBar

                    // Bottom controls row
                    bottomControlRow(geo: geo)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                }
            }
        }
        .onAppear { camera.startSession() }
        .onDisappear { camera.stopSession() }
        .preferredColorScheme(.dark)
        .statusBar(hidden: true)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 24) {
            // Flash button
            Button {
                camera.toggleFlash()
                handleBackCameraFlash()
            } label: {
                Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(camera.isFlashOn ? .yellow : .white)
            }

            Spacer()

            // Live indicator (placeholder)
            Image(systemName: "livephoto")
                .font(.system(size: 20))
                .foregroundColor(.white)

            Spacer()

            // HDR toggle
            Button {
                camera.toggleHDR()
            } label: {
                Text(camera.isHDROn ? "HDR" : "HDR")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(camera.isHDROn ? .yellow : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(camera.isHDROn ? Color.yellow : .white, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Zoom Selector

    private var zoomSelector: some View {
        HStack(spacing: 4) {
            ForEach(camera.availableZoomFactors, id: \.self) { factor in
                Button {
                    camera.setZoom(factor)
                } label: {
                    let isSelected = abs(camera.currentZoomFactor - factor) < 0.2
                    Text(factor == 0.5 ? ".5×" : "\(Int(factor))×")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .black : .white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.white.opacity(0.9) : Color.black.opacity(0.4))
                        )
                }
            }
        }
    }

    // MARK: - Mode Selector Bar

    private var modeSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(modes, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMode = mode
                        }
                    } label: {
                        Text(mode)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedMode == mode ? .yellow : .white)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Bottom Control Row

    private func bottomControlRow(geo: GeometryProxy) -> some View {
        HStack {
            // Thumbnail (last saved photo)
            thumbnailButton

            Spacer()

            // Shutter button
            shutterButton

            Spacer()

            // Camera switch button
            cameraSwitchButton
        }
        .padding(.horizontal, 30)
    }

    // MARK: Thumbnail

    private var thumbnailButton: some View {
        Group {
            if let thumb = camera.lastSavedThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 1.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 58, height: 58)
            }
        }
    }

    // MARK: Shutter Button

    private var shutterButton: some View {
        Button {
            triggerCapture()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(captureScale)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: Camera Switch

    private var cameraSwitchButton: some View {
        Button {
            camera.switchCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 58, height: 58)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
    }

    // MARK: - Actions

    private func triggerCapture() {
        // Visual feedback: scale pulse + black flash
        withAnimation(.easeInOut(duration: 0.08)) {
            captureScale = 0.85
            shutterFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.08)) {
                captureScale = 1.0
                shutterFlash = false
            }
        }

        camera.capturePhoto()
    }

    private func handleTap(at point: CGPoint, in size: CGSize) {
        focusPoint = point
        showFocusIndicator = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            showFocusIndicator = true
        }
        camera.focus(at: point, in: CGRect(origin: .zero, size: size))
    }

    /// Toggle torch for back camera flash simulation.
    private func handleBackCameraFlash() {
        guard !camera.isFrontCamera,
              let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = camera.isFlashOn ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }
}

// MARK: - Preview

#Preview {
    CameraView()
}
