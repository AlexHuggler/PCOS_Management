import Testing
import SwiftUI
@testable import PCOS

@Suite("FlowLayout")
struct FlowLayoutTests {
    @Test("Unspecified width produces finite non-negative size")
    func unspecifiedWidthIsFinite() {
        let layout = FlowLayout(spacing: 8)
        let size = layout.debugSizeThatFits(
            proposedWidth: nil,
            subviewSizes: [
                CGSize(width: 100, height: 24),
                CGSize(width: 80, height: 24),
                CGSize(width: 120, height: 24),
            ]
        )

        #expect(size.width.isFinite)
        #expect(size.height.isFinite)
        #expect(size.width >= 0)
        #expect(size.height >= 0)
    }

    @Test("Finite width wraps rows with finite output")
    func finiteWidthWraps() {
        let layout = FlowLayout(spacing: 8)
        let size = layout.debugSizeThatFits(
            proposedWidth: 140,
            subviewSizes: [
                CGSize(width: 90, height: 20),
                CGSize(width: 90, height: 20),
                CGSize(width: 90, height: 20),
            ]
        )

        #expect(size.width <= 140)
        #expect(size.height > 20)
        #expect(size.width.isFinite)
        #expect(size.height.isFinite)
    }

    @Test("Invalid child sizes are sanitized to finite values")
    func invalidSubviewSizesSanitized() {
        let layout = FlowLayout(spacing: 8)
        let size = layout.debugSizeThatFits(
            proposedWidth: CGFloat.infinity,
            subviewSizes: [
                CGSize(width: CGFloat.infinity, height: 20),
                CGSize(width: 50, height: -CGFloat.infinity),
                CGSize(width: -10, height: 18),
            ]
        )

        #expect(size.width.isFinite)
        #expect(size.height.isFinite)
        #expect(size.width >= 0)
        #expect(size.height >= 0)
    }
}
