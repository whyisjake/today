//
//  SwipeNavigableModifier.swift
//  Today
//
//  Reusable horizontal-swipe gesture for gallery-style article navigation.
//

import SwiftUI

#if os(iOS)

private enum GestureDirection {
    case undetermined, horizontal, vertical
}

struct SwipeNavigableModifier: ViewModifier {
    let canGoNext: Bool
    let canGoPrev: Bool
    let onNext: () -> Void
    let onPrev: () -> Void

    @State private var offset: CGFloat = 0
    @State private var gestureDirection: GestureDirection = .undetermined

    private let directionThreshold: CGFloat = 12
    private let commitThreshold: CGFloat = 80
    private let rubberBandFactor: CGFloat = 0.25

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .simultaneousGesture(makeDragGesture())
    }

    private func makeDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if gestureDirection == .undetermined {
                    guard abs(dx) + abs(dy) > directionThreshold else { return }
                    gestureDirection = abs(dx) > abs(dy) ? .horizontal : .vertical
                }

                guard gestureDirection == .horizontal else { return }

                let atLeftBoundary = dx > 0 && !canGoPrev
                let atRightBoundary = dx < 0 && !canGoNext

                if atLeftBoundary || atRightBoundary {
                    offset = dx * rubberBandFactor
                } else {
                    offset = dx
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let predictedDx = value.predictedEndTranslation.width
                let wasHorizontal = gestureDirection == .horizontal
                gestureDirection = .undetermined

                guard wasHorizontal else { return }

                // Use predicted end translation to honour fast flicks
                let effectiveDx = abs(predictedDx) > abs(dx) ? predictedDx : dx

                if effectiveDx > commitThreshold && canGoPrev {
                    onPrev()
                } else if effectiveDx < -commitThreshold && canGoNext {
                    onNext()
                }

                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    offset = 0
                }
            }
    }
}

extension View {
    func swipeNavigable(
        canGoNext: Bool,
        canGoPrev: Bool,
        onNext: @escaping () -> Void,
        onPrev: @escaping () -> Void
    ) -> some View {
        modifier(SwipeNavigableModifier(
            canGoNext: canGoNext,
            canGoPrev: canGoPrev,
            onNext: onNext,
            onPrev: onPrev
        ))
    }
}

#endif
