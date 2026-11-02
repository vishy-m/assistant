import CoreGraphics

/// Drag math for a resizable split. `translation` is the gesture's total
/// movement from its start, so each update is `origin + sign * translation`
/// and a later smaller translation follows the pointer back.
public enum SplitDragMath {
    public static func apply(origin: CGFloat,
                             translation: CGFloat,
                             range: ClosedRange<CGFloat>,
                             sign: CGFloat) -> CGFloat {
        let next = origin + sign * translation
        return min(max(next, range.lowerBound), range.upperBound)
    }
}
