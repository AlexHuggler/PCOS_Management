import SwiftUI

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
            return CGSize(
                width: (measured.width.isFinite && measured.width > 0) ? measured.width : 0,
                height: (measured.height.isFinite && measured.height > 0) ? measured.height : 0
            )
        }
    }

    private func sanitizedSubviewSizes(_ sizes: [CGSize]) -> [CGSize] {
        sizes.map { size in
            CGSize(
                width: (size.width.isFinite && size.width > 0) ? size.width : 0,
                height: (size.height.isFinite && size.height > 0) ? size.height : 0
            )
        }
    }

    private func normalizedWidth(from width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite else { return nil }
        return max(0, width)
    }
}
