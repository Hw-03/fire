import AVFoundation
import UIKit
import Photos
import Combine

/// Manages AVFoundation camera session, frame capture (silent shutter), focus, zoom, and flash.
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var capturedImage: UIImage?
    @Published var lastSavedThumbnail: UIImage?
    @Published var isFlashOn: Bool = false
    @Published var isHDROn: Bool = false
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var availableZoomFactors: [CGFloat] = [1.0]
    @Published var isFrontCamera: Bool = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let session = AVCaptureSession()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var currentDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?

    private let sessionQueue = DispatchQueue(label: "com.silentcamera.sessionQueue", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "com.silentcamera.captureQueue", qos: .userInitiated)

    /// When true, the next video frame will be saved as a photo.
    private var captureNextFrame: Bool = false

    // MARK: - Lifecycle

    override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationStatus = .authorized
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted { self?.setupSession() }
                }
            }
        default:
            authorizationStatus = .denied
        }
    }

    // MARK: - Session Setup

    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Add video input
            self.addVideoInput(position: .back)

            // Add video data output (silent frame capture)
            self.addVideoDataOutput()

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                self.previewLayer = layer
            }

            self.session.startRunning()
        }
    }

    private func addVideoInput(position: AVCaptureDevice.Position) {
        // Remove existing input
        if let existing = currentInput {
            session.removeInput(existing)
            currentInput = nil
        }

        // Pick best camera device
        let device = bestDevice(for: position)
        currentDevice = device

        // Populate zoom factors
        DispatchQueue.main.async {
            self.availableZoomFactors = self.zoomFactors(for: device)
        }

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)
        currentInput = input
    }

    private func addVideoDataOutput() {
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: captureQueue)

        // Prefer BGRA pixel format for easy UIImage conversion
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoDataOutput) else { return }
        session.addOutput(videoDataOutput)

        // Set orientation
        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = isFrontCamera
            }
        }
    }

    // MARK: - Camera Controls

    func startSession() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == false {
                self?.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true {
                self?.session.stopRunning()
            }
        }
    }

    /// Trigger a silent capture — grabs the next video frame instead of using AVCapturePhotoOutput.
    func capturePhoto() {
        captureNextFrame = true
    }

    /// Toggle between front / back camera.
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.isFrontCamera.toggle()
            let position: AVCaptureDevice.Position = self.isFrontCamera ? .front : .back

            // Remove existing video output before switching
            self.session.removeOutput(self.videoDataOutput)
            self.addVideoInput(position: position)
            self.addVideoDataOutput()

            // Update mirror for front camera
            if let connection = self.videoDataOutput.connection(with: .video) {
                connection.isVideoMirrored = self.isFrontCamera
            }

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.currentZoomFactor = 1.0
            }
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let clamped = min(max(factor, 1.0), device.activeFormat.videoMaxZoomFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.currentZoomFactor = clamped }
        } catch {}
    }

    func changeZoomByPinch(scale: CGFloat) {
        guard let device = currentDevice else { return }
        let desired = currentZoomFactor * scale
        let clamped = min(max(desired, 1.0), device.activeFormat.videoMaxZoomFactor)
        setZoom(clamped)
    }

    // MARK: - Focus

    func focus(at point: CGPoint, in viewBounds: CGRect) {
        guard let device = currentDevice,
              let previewLayer else { return }

        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Flash

    func toggleFlash() {
        isFlashOn.toggle()
    }

    // MARK: - HDR

    func toggleHDR() {
        isHDROn.toggle()
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            // HDR / tone-mapping hint (available on supported devices)
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = !isHDROn
                device.isVideoHDREnabled = isHDROn
            }
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Helpers

    private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Try triple/dual camera system first, fall back to wide angle
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: position
        )
        return session.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func zoomFactors(for device: AVCaptureDevice?) -> [CGFloat] {
        guard let device else { return [1.0] }
        // Expose 1×, 2×, and optionally 0.5× for ultrawide
        var factors: [CGFloat] = []
        if device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera {
            factors.append(0.5)
        }
        factors.append(1.0)
        if device.activeFormat.videoMaxZoomFactor >= 2.0 {
            factors.append(2.0)
        }
        if device.activeFormat.videoMaxZoomFactor >= 5.0 {
            factors.append(5.0)
        }
        return factors
    }

    // MARK: - Photo Saving

    private func saveToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { [weak self] success, _ in
                if success {
                    DispatchQueue.main.async {
                        self?.lastSavedThumbnail = image.thumbnailImage(size: CGSize(width: 80, height: 80))
                        self?.capturedImage = image
                    }
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard captureNextFrame else { return }
        captureNextFrame = false // consume the flag

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        var uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        // Apply flash (torch) effect – torch was already on during preview for back camera
        // Front camera flash: overlay a white flash UIImage
        if isFlashOn && isFrontCamera {
            uiImage = uiImage.withFrontFlash() ?? uiImage
        }

        saveToPhotoLibrary(uiImage)
    }
}

// MARK: - UIImage helpers

private extension UIImage {

    func thumbnailImage(size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        draw(in: CGRect(origin: .zero, size: size))
        let thumb = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return thumb
    }

    func withFrontFlash() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(at: .zero)
        UIColor.white.withAlphaComponent(0.6).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}
