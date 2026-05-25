import SwiftUI
import os

enum LayoutDimensionSanitizer {
    static func frameDimension(from value: CGFloat?) -> CGFloat {
        guard let value, value.isFinite else { return 0 }
        return max(0, value)
    }

    static func normalizedProgress(from value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// A layout that wraps content horizontally, flowing to the next line when space runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let subviewSizes = sanitizedSubviewSizes(subviews)
        return arranged(
            subviewSizes: subviewSizes,
            availableWidth: normalizedWidth(from: proposal.width)
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let subviewSizes = sanitizedSubviewSizes(subviews)
        let result = arranged(
            subviewSizes: subviewSizes,
            availableWidth: normalizedWidth(from: bounds.width)
        )

        for index in subviews.indices {
            guard index < result.positions.count else { continue }
            let position = result.positions[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    /// Test hook for verifying finite sizing without constructing SwiftUI subviews.
    func debugSizeThatFits(proposedWidth: CGFloat?, subviewSizes: [CGSize]) -> CGSize {
        arranged(
            subviewSizes: sanitizedSubviewSizes(subviewSizes),
            availableWidth: normalizedWidth(from: proposedWidth)
        ).size
    }

    private func arranged(subviewSizes: [CGSize], availableWidth: CGFloat?) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        positions.reserveCapacity(subviewSizes.count)

        let rowWidthLimit = availableWidth
        let gap = spacing.isFinite ? max(0, spacing) : 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subviewSize in subviewSizes {
            let shouldWrap: Bool
            if let rowWidthLimit {
                shouldWrap = currentX > 0 && (currentX + subviewSize.width) > rowWidthLimit
            } else {
                shouldWrap = false
            }

            if shouldWrap {
                maxLineWidth = max(maxLineWidth, max(0, currentX - gap))
                currentX = 0
                currentY += lineHeight + gap
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, subviewSize.height)
            currentX += subviewSize.width + gap
        }

        maxLineWidth = max(maxLineWidth, max(0, currentX - (subviewSizes.isEmpty ? 0 : gap)))
        let totalHeight = subviewSizes.isEmpty ? 0 : (currentY + lineHeight)

        return (
            positions,
            CGSize(
                width: maxLineWidth.isFinite ? max(0, maxLineWidth) : 0,
                height: totalHeight.isFinite ? max(0, totalHeight) : 0
            )
        )
    }

    private func sanitizedSubviewSizes(_ subviews: Subviews) -> [CGSize] {
        subviews.map { subview in
            let measured = subview.sizeThatFits(.unspecified)
#if DEBUG
            debugLogInvalidMeasurement(measured, context: "measuredSubview")
#endif
            return CGSize(
                width: LayoutDimensionSanitizer.frameDimension(from: measured.width),
                height: LayoutDimensionSanitizer.frameDimension(from: measured.height)
            )
        }
    }

    private func sanitizedSubviewSizes(_ sizes: [CGSize]) -> [CGSize] {
        sizes.map { size in
#if DEBUG
            debugLogInvalidMeasurement(size, context: "debugSizeThatFits")
#endif
            return CGSize(
                width: LayoutDimensionSanitizer.frameDimension(from: size.width),
                height: LayoutDimensionSanitizer.frameDimension(from: size.height)
            )
        }
    }

    private func normalizedWidth(from width: CGFloat?) -> CGFloat? {
        guard let width else { return nil }
#if DEBUG
        if !width.isFinite || width < 0 {
            Logger.ui.debug(
                "FlowLayout sanitized invalid proposed width. value=\(String(describing: width), privacy: .public)"
            )
        }
#endif
        guard width.isFinite else { return nil }
        return LayoutDimensionSanitizer.frameDimension(from: width)
    }

#if DEBUG
    private func debugLogInvalidMeasurement(_ size: CGSize, context: StaticString) {
        guard !size.width.isFinite || !size.height.isFinite || size.width < 0 || size.height < 0 else { return }
        Logger.ui.debug(
            "FlowLayout sanitized invalid size. context=\(context) width=\(size.width, privacy: .public) height=\(size.height, privacy: .public)"
        )
    }
#endif
}
