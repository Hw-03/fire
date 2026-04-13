import SwiftUI

/// Yellow focus square that animates in on tap-to-focus.
struct FocusIndicatorView: View {

    let position: CGPoint
    @Binding var isVisible: Bool

    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 80, height: 80)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) {
                    scale = 1.0
                }
                // Fade out after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        isVisible = false
                    }
                }
            }
    }
}
