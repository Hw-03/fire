import SwiftUI
import AVFoundation

/// UIViewRepresentable that hosts an AVCaptureVideoPreviewLayer.
struct CameraPreviewView: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer
    var onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> TappableView {
        let view = TappableView()
        view.backgroundColor = .black
        view.onTap = onTap

        previewLayer.frame = UIScreen.main.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: TappableView, context: Context) {
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}

/// UIView subclass that forwards tap location to a closure.
final class TappableView: UIView {

    var onTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        onTap?(location)
    }
}
