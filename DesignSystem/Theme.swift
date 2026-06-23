import SwiftUI

/// Centralized design tokens: metrics, palette, motion, and typography.
/// The visual language is soft "pill" controls, translucent material surfaces
/// with subtle gradient hairlines, and springy, tactile motion.
enum Theme {
    enum Metrics {
        static let controlHeight: CGFloat = 30
        static let cardCorner: CGFloat = 14
        static let rowCorner: CGFloat = 12
        static let chipCorner: CGFloat = 8
        static let spacing: CGFloat = 12
        static let tightSpacing: CGFloat = 6
        static let cardPadding: CGFloat = 16

        static func pillCorner(forHeight height: CGFloat) -> CGFloat { height / 2 }
    }

    enum Palette {
        static let controlBackground = Color.secondary.opacity(0.12)
        static let controlHover = Color.secondary.opacity(0.20)
        static let cardFill = Color.secondary.opacity(0.06)
        static let hairline = Color.primary.opacity(0.10)
        static let separator = Color.primary.opacity(0.06)

        /// Color used to represent a container's run state.
        static func color(for state: RuntimeState) -> Color {
            switch state {
            case .running: return .green
            case .stopping: return .orange
            case .stopped: return .secondary
            case .unknown: return .gray
            }
        }

        /// Adaptive top→bottom hairline gradient for card borders.
        static var borderGradient: LinearGradient {
            LinearGradient(
                colors: [Color.primary.opacity(0.14), Color.primary.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        static var accentGradient: LinearGradient {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.34, dampingFraction: 0.85)
        static let snappy = Animation.spring(response: 0.18, dampingFraction: 0.9)
        static let smooth = Animation.easeInOut(duration: 0.2)
    }

    enum Typography {
        static let largeTitle = Font.system(size: 22, weight: .bold)
        static let title = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11, weight: .medium)
        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoCaption = Font.system(size: 10.5, design: .monospaced)
    }
}
