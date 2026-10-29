import Foundation
import SwiftUI

struct NotchRootView: View {
    let model: NotchViewModel
    let alerts: NotchAlertCenter
    @Environment(\.colorScheme) private var systemColorScheme

    private enum Presentation: Equatable {
        case collapsed
        case alert
        case expanded
    }

    private static let topRadius: [Presentation: CGFloat] = [.collapsed: 6, .alert: 12, .expanded: 14]
    private static let bottomRadius: [Presentation: CGFloat] = [.collapsed: 10, .alert: 22, .expanded: 26]
    private static let morphAnimation = Animation.spring(response: 0.42, dampingFraction: 0.72)
    /// The leading axis of the morph; the other axis follows a beat later.
    private static let morphLeadAnimation = Animation.spring(response: 0.38, dampingFraction: 0.78)
    private static let morphFollowAnimation = Animation.spring(response: 0.42, dampingFraction: 0.74)
    private static let morphStagger: Duration = .milliseconds(70)
    private static let reducedMotionAnimation = Animation.easeInOut(duration: 0.2)
    private static let contentPadding: CGFloat = 20
    private static let alertContentInset: CGFloat = 16
    private static let alertWingGap: CGFloat = 10
    private static let shadowRadius: CGFloat = 18
    private static let shadowOffset: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rendered shape size; trails `shapeSize` so width and height can morph one after the other.
    @State private var morphSize: CGSize?
    @State private var morphFollowTask: Task<Void, Never>?

    private var presentation: Presentation {
        if model.isExpanded { return .expanded }
        if alerts.current != nil { return .alert }
        return .collapsed
    }

    private var topRadius: CGFloat { Self.topRadius[presentation] ?? 6 }
    private var bottomRadius: CGFloat { Self.bottomRadius[presentation] ?? 10 }

    private var shapeSize: CGSize {
        let geometry = model.geometry
        switch presentation {
        case .expanded:
            return geometry.expandedRect.size
        case .alert:
            return geometry.alertRect.size
        case .collapsed:
            let collapsed = geometry.collapsedRect(wingWidth: model.wingWidth)
            return CGSize(width: collapsed.width + topRadius * 2, height: collapsed.height)
        }
    }

    /// Alerts are part of the notch, so they stay black and dark in both themes.
    private var contentColorScheme: ColorScheme {
        if presentation == .alert || model.settings.theme == .dark { return .dark }
        return systemColorScheme
    }

    /// Collapsed state and alerts stay black to match the hardware notch.
    private var fillColor: Color {
        guard presentation == .expanded, contentColorScheme == .light else { return .black }
        return Color(white: 0.96)
    }

    var body: some View {
        let size = morphSize ?? shapeSize
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(fillColor)
                .shadow(
                    color: .black.opacity(presentation == .collapsed ? 0 : 0.45),
                    radius: Self.shadowRadius,
                    y: Self.shadowOffset
                )
                .background(alignment: .bottom) { alertBackdrop }
                .overlay(alignment: .top) { alertHairline }

            content
        }
        .frame(width: size.width, height: size.height)
        .attentionShake(trigger: ShakeTrigger(
            count: model.attentionCount,
            alertID: reduceMotion ? nil : alerts.current?.id
        ))
        .environment(\.colorScheme, contentColorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? Self.reducedMotionAnimation : Self.morphAnimation, value: presentation)
        .animation(Self.morphAnimation, value: model.wingWidth)
        .onAppear { morphSize = shapeSize }
        .onChange(of: shapeSize) { oldSize, newSize in
            morph(from: oldSize, to: newSize)
        }
    }

    /// Grows width first then height, and shrinks height first then width, like the Dynamic Island.
    private func morph(from oldSize: CGSize, to newSize: CGSize) {
        morphFollowTask?.cancel()
        guard !reduceMotion else {
            withAnimation(Self.reducedMotionAnimation) { morphSize = newSize }
            return
        }
        let current = morphSize ?? oldSize
        let isGrowing = newSize.height >= current.height
        let intermediate = isGrowing
            ? CGSize(width: newSize.width, height: current.height)
            : CGSize(width: current.width, height: newSize.height)
        withAnimation(Self.morphLeadAnimation) { morphSize = intermediate }
        // A separate update a beat later; the springs retarget smoothly instead of restarting.
        morphFollowTask = Task { @MainActor in
            try? await Task.sleep(for: Self.morphStagger)
            guard !Task.isCancelled else { return }
            withAnimation(Self.morphFollowAnimation) { morphSize = newSize }
        }
    }

    @ViewBuilder
    private var content: some View {
        let notchHeight = model.geometry.notchSize.height
        switch presentation {
        case .expanded:
            NotchContentView(model: model)
                .padding(.horizontal, topRadius + Self.contentPadding)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        case .alert:
            if let alert = alerts.current {
                let alertSize = model.geometry.alertRect.size
                NotchAlertView(alert: alert, center: alerts, layout: alertLayout(notchHeight: notchHeight)) {
                    openModule(for: alert)
                }
                .id(alert.id)
                // Fixed to the final size so the morph never re-lays out the content.
                .frame(width: alertSize.width, height: alertSize.height)
                .transition(.alertContent(reduceMotion: reduceMotion))
            }
        case .collapsed:
            CompactWingsView(model: model)
                .padding(.horizontal, topRadius)
                .transition(.opacity)
        }
    }

    private func alertLayout(notchHeight: CGFloat) -> NotchAlertView.Layout {
        let sideInset = topRadius + Self.alertContentInset
        let wingSpace = (model.geometry.alertRect.width - model.geometry.notchSize.width) / 2
        return NotchAlertView.Layout(
            notchHeight: notchHeight,
            sideInset: sideInset,
            wingWidth: wingSpace - sideInset - Self.alertWingGap,
            barInset: bottomRadius - Self.alertContentInset
        )
    }

    @ViewBuilder
    private var alertBackdrop: some View {
        if presentation == .alert, let alert = alerts.current {
            ZStack(alignment: .bottom) {
                AlertGlow(style: alert.style, topRadius: topRadius, bottomRadius: bottomRadius)
                AlertStackHint(queuedCount: alerts.queue.count, cornerRadius: bottomRadius)
                    .padding(.horizontal, topRadius)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var alertHairline: some View {
        if presentation == .alert, let alert = alerts.current {
            AlertHairline(style: alert.style, topRadius: topRadius, bottomRadius: bottomRadius)
                .transition(.opacity)
        }
    }

    private func openModule(for alert: NotchAlert) {
        alerts.dismiss()
        if let module = alert.module {
            model.onOpenModule?(module)
        }
    }
}

/// Shakes when the panel asks for attention or a new alert arrives.
private struct ShakeTrigger: Equatable {
    let count: Int
    let alertID: UUID?
}

private struct AttentionShake: ViewModifier {
    let trigger: ShakeTrigger

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-9, duration: 0.07)
                CubicKeyframe(8, duration: 0.08)
                CubicKeyframe(-6, duration: 0.08)
                CubicKeyframe(4, duration: 0.08)
                CubicKeyframe(0, duration: 0.1)
            }
        }
    }
}

extension View {
    fileprivate func attentionShake(trigger: ShakeTrigger) -> some View {
        modifier(AttentionShake(trigger: trigger))
    }
}
