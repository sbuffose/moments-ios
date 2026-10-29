// Full-screen review photo: pinch zoom, double-tap zoom, swipe down to dismiss.

import SwiftUI

struct ReviewPhotoViewer: View {
    let localIdentifier: String
    var onDismiss: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(1 - min(Double(dismissDrag) / 420, 0.5))
                .ignoresSafeArea()
            
            AsyncPhotoThumbnail(
                localIdentifier: localIdentifier,
                targetSize: CGSize(width: 1600, height: 1600)
            )
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height + dismissDrag)
            .gesture(pinch)
            .simultaneousGesture(drag)
            .onTapGesture(count: 2, perform: toggleZoom)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, MomentsColors.coral.opacity(0.9))
                    .padding(16)
            }
            .accessibilityIdentifier("review.photoViewer.dismiss")
            .accessibilityLabel("Cerrar")
        }
        .accessibilityIdentifier("review.photoViewer")
        .accessibilityAddTraits(.isModal)
    }
    
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(4, max(1, lastScale * value.magnification))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { resetZoom() }
            }
    }
    
    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if scale > 1.01 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else if value.translation.height > 0,
                          abs(value.translation.height) > abs(value.translation.width) {
                    dismissDrag = value.translation.height
                }
            }
            .onEnded { value in
                if scale > 1.01 {
                    lastOffset = offset
                    return
                }
                if value.translation.height > 120 {
                    onDismiss()
                } else if reduceMotion {
                    dismissDrag = 0
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dismissDrag = 0
                    }
                }
            }
    }
    
    private func toggleZoom() {
        if scale > 1.01 {
            resetZoom()
        } else {
            scale = 2.2
            lastScale = 2.2
        }
    }
    
    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        dismissDrag = 0
    }
}
